import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageModel: ObservableObject {
    // 5h / 週の枠と月間のクレジット消費。表示する行は設定と合わせて claudeLimits で組み立てる
    @Published private var claudeRateLimits: [UsageLimit] = []
    @Published private(set) var claudeSpend: ClaudeSpend?
    // API から取れた行と支出上限。目安の行は codexLimits で足す
    @Published private var codexRawLimits: [UsageLimit] = []
    @Published private var codexSpend: CodexSpend?
    @Published var claudeError: String?
    @Published var codexError: String?
    @Published var codexAvailable = false
    @Published var lastUpdated: Date?
    // ログイン項目の状態はシステム側が持つので、UserDefaults ではなくここに反映する
    @Published var launchAtLogin = false
    @Published var loginItemMessage: String?

    let settings: UsageSettings

    private static let baseInterval: TimeInterval = 180
    private static let maxInterval: TimeInterval = 1800
    private var currentInterval: TimeInterval = UsageModel.baseInterval
    private var timer: Timer?
    private var lastAttempt: Date?
    private var started = false
    private var isFetching = false
    private var cancellables: Set<AnyCancellable> = []
    // 今日・今週に使った分を出すための、日ごとの累計の記録
    private var claudeHistory = UsageHistory(key: "usageHistory.claude")
    private var codexHistory = UsageHistory(key: "usageHistory.codex")

    init(settings: UsageSettings) {
        self.settings = settings
        codexAvailable = CodexUsageAPI.isConfigured
        launchAtLogin = LoginItem.isEnabled
        // 設定は別 ObservableObject なので、変更をこちらの再描画にも伝える
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemMessage = LoginItem.requiresApproval
                ? "システム設定 → 一般 → ログイン項目 で許可してください"
                : nil
        } catch {
            loginItemMessage = "ログイン項目を変更できませんでした (\(error.localizedDescription))"
        }
        // 成否にかかわらずシステム側の状態に合わせる
        launchAtLogin = LoginItem.isEnabled
    }

    // Codex を表示対象として扱えるか (設定 ON かつ auth.json がある)
    var codexActive: Bool { settings.codexEnabled && codexAvailable }

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    // ポップオーバーを開いた時用。直近に試行済みなら API を叩かない
    func refreshIfStale() {
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        refresh()
    }

    func refresh() {
        guard !isFetching else { return }
        isFetching = true
        lastAttempt = Date()
        Task {
            defer {
                isFetching = false
                scheduleNext()
            }
            codexAvailable = CodexUsageAPI.isConfigured
            var succeeded = false
            var claudeRateLimited = false
            var codexRateLimited = false

            if settings.claudeEnabled {
                do {
                    let usage = try await ClaudeUsageAPI.fetch()
                    claudeRateLimits = usage.rateLimits
                    claudeSpend = usage.spend
                    if let spend = usage.spend { claudeHistory.record(spend.used.amount, dayStart: paceOptions.calendar.dayStart) }
                    claudeError = nil
                    succeeded = true
                } catch {
                    claudeError = error.localizedDescription
                    claudeRateLimited = isRateLimit(error)
                }
            } else {
                claudeRateLimits = []
                claudeSpend = nil
                claudeError = nil
            }

            if codexActive {
                do {
                    let usage = try await CodexUsageAPI.fetch()
                    codexRawLimits = usage.limits
                    codexSpend = usage.spend
                    if let spend = usage.spend { codexHistory.record(spend.used, dayStart: paceOptions.calendar.dayStart) }
                    codexError = nil
                    succeeded = true
                } catch {
                    codexError = error.localizedDescription
                    codexRateLimited = isRateLimit(error)
                }
            } else {
                codexRawLimits = []
                codexSpend = nil
                codexError = nil
            }

            if succeeded { lastUpdated = Date() }

            // 429 は叩き続けると回復しないため、間隔を倍々で広げる
            if claudeRateLimited || codexRateLimited {
                currentInterval = min(currentInterval * 2, Self.maxInterval)
                let note = "\n次の再試行まで \(Int(currentInterval)) 秒空けます"
                if claudeRateLimited { claudeError = (claudeError ?? "") + note }
                if codexRateLimited { codexError = (codexError ?? "") + note }
            } else {
                currentInterval = Self.baseInterval
            }
        }
    }

    private func isRateLimit(_ error: Error) -> Bool {
        if case UsageError.httpStatus(429, _, _) = error { return true }
        return false
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    // メニューバーに並べるゲージ。
    // アイコン表示なら 1 つでも識別子を出し、テキストは幅を取るので両方出す時だけ添える
    var menuBarGauges: [MenuBarGauge] {
        var sources: [(provider: UsageProvider, percent: Double?)] = []
        if settings.claudeEnabled && settings.claudeInMenuBar {
            sources.append((.claude, claudeMenuBarLimit?.percent))
        }
        if codexActive && settings.codexInMenuBar {
            sources.append((.codex, codexMenuBarPercent))
        }
        // 何も出さない設定でもクリック先が必要なので、空のゲージだけ残す
        guard !sources.isEmpty else {
            return [MenuBarGauge(id: "empty", text: nil, symbolName: nil, percent: nil)]
        }
        let useIcons = settings.useMenuBarIcons
        let showsLabel = useIcons || sources.count > 1
        return sources.map { source in
            MenuBarGauge(
                id: source.provider.rawValue,
                text: showsLabel && !useIcons ? source.provider.shortLabel : nil,
                symbolName: showsLabel && useIcons ? source.provider.symbolName : nil,
                percent: source.percent
            )
        }
    }

    var claudeLimits: [UsageLimit] {
        guard let claudeSpend else { return claudeRateLimits }
        // 0 以下は上書きしていない扱い
        let limitOverride = settings.claudeLimitOverride.flatMap { $0 > 0 ? $0 : nil }
        return claudeRateLimits + ClaudeBudget.limits(
            spend: claudeSpend,
            limitOverride: limitOverride,
            pace: settings.claudeShowsPace ? paceOptions : nil,
            history: claudeHistory
        )
    }

    // 目安の行はクレジットの行の手前に差し込む
    var codexLimits: [UsageLimit] {
        guard settings.codexShowsPace, let codexSpend, let period = codexSpend.period() else {
            return codexRawLimits
        }
        let pace = SpendPace.limits(
            provider: .codex,
            used: codexSpend.used,
            limit: codexSpend.limit,
            period: period,
            options: paceOptions,
            history: codexHistory,
            format: CodexUsageAPI.formatted
        )
        return codexRawLimits.filter { $0.group != "credits" } + pace + codexRawLimits.filter { $0.group == "credits" }
    }

    private var paceOptions: PaceOptions {
        PaceOptions(
            daily: settings.dailyPaceMode,
            weekly: settings.weeklyPaceMode,
            calendar: PaceCalendar(
                dayStart: TimeInterval(settings.dayStartMinutes * 60),
                excludesHolidays: settings.paceExcludesHolidays
            )
        )
    }

    var claudeMenuBarLimit: UsageLimit? {
        let limits = claudeLimits
        let dailyPace = limits.first { $0.kind == "pace_daily" }
        let weeklyPace = limits.first { $0.kind == "pace_weekly" }
        let credits = limits.first { $0.group == "credits" }
        // 目安を切っている時や、5h / 週の枠しか無いプランではクレジット → 全体の最大で代用する
        switch settings.claudeMetric {
        case .dailyPace:
            return dailyPace ?? credits ?? highest(in: limits)
        case .weeklyPace:
            return weeklyPace ?? credits ?? highest(in: limits)
        case .credits:
            return credits
        }
    }

    // クレジット行 (percent を持つものを優先)
    var codexCreditsLimit: UsageLimit? {
        codexRawLimits.first { $0.group == "credits" && $0.percent != nil }
            ?? codexRawLimits.first { $0.group == "credits" }
    }

    var codexMenuBarPercent: Double? {
        let limits = codexLimits
        switch settings.codexMetric {
        case .dailyPace:
            return (limits.first { $0.kind == "pace_daily" } ?? codexCreditsLimit)?.percent
        case .weeklyPace:
            return (limits.first { $0.kind == "pace_weekly" } ?? codexCreditsLimit)?.percent
        case .credits:
            return codexCreditsLimit?.percent
        case .creditTier:
            return codexCreditsLimit?.creditTier?.percent
        }
    }

    private func highest(in limits: [UsageLimit]) -> UsageLimit? {
        limits.filter { $0.percent != nil }.max { ($0.percent ?? -1) < ($1.percent ?? -1) }
    }
}
