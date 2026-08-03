import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageModel: ObservableObject {
    @Published var claudeLimits: [UsageLimit] = []
    @Published var codexLimits: [UsageLimit] = []
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
                    claudeLimits = try await ClaudeUsageAPI.fetch()
                    claudeError = nil
                    succeeded = true
                } catch {
                    claudeError = error.localizedDescription
                    claudeRateLimited = isRateLimit(error)
                }
            } else {
                claudeLimits = []
                claudeError = nil
            }

            if codexActive {
                do {
                    codexLimits = try await CodexUsageAPI.fetch()
                    codexError = nil
                    succeeded = true
                } catch {
                    codexError = error.localizedDescription
                    codexRateLimited = isRateLimit(error)
                }
            } else {
                codexLimits = []
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

    var claudeMenuBarLimit: UsageLimit? {
        switch settings.claudeMetric {
        case .session:
            return claudeLimits.first { $0.kind == "session" }
        case .weeklyMax:
            return highest(in: claudeLimits.filter { $0.group == "weekly" || $0.kind.hasPrefix("weekly") })
        case .max:
            return highest(in: claudeLimits)
        }
    }

    // クレジット行 (percent を持つものを優先)
    var codexCreditsLimit: UsageLimit? {
        codexLimits.first { $0.group == "credits" && $0.percent != nil }
            ?? codexLimits.first { $0.group == "credits" }
    }

    var codexMenuBarPercent: Double? {
        switch settings.codexMetric {
        case .credits:
            return codexCreditsLimit?.percent
        case .creditTier:
            return codexCreditsLimit?.creditTier?.percent
        case .max:
            return highest(in: codexLimits)?.percent
        }
    }

    private func highest(in limits: [UsageLimit]) -> UsageLimit? {
        limits.filter { $0.percent != nil }.max { ($0.percent ?? -1) < ($1.percent ?? -1) }
    }
}
