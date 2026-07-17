import Foundation
import SwiftUI

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case session
    case weekly
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: return "Session (5h)"
        case .weekly: return "Week (最大)"
        case .max: return "全体の最大"
        }
    }
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var limits: [UsageLimit] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var menuBarMetric: MenuBarMetric {
        didSet { UserDefaults.standard.set(menuBarMetric.rawValue, forKey: Self.metricKey) }
    }

    private static let metricKey = "menuBarMetric"
    private static let baseInterval: TimeInterval = 180
    private static let maxInterval: TimeInterval = 1800
    private var currentInterval: TimeInterval = UsageModel.baseInterval
    private var timer: Timer?
    private var lastAttempt: Date?
    private var started = false
    private var isFetching = false

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.metricKey)
        menuBarMetric = MenuBarMetric(rawValue: saved ?? "") ?? .session
    }

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
            do {
                let fetched = try await UsageAPI.fetch()
                limits = fetched
                lastUpdated = Date()
                errorMessage = nil
                currentInterval = Self.baseInterval
            } catch {
                // 429 は叩き続けると回復しないため、間隔を倍々で広げる
                if case UsageError.httpStatus(429, _) = error {
                    currentInterval = min(currentInterval * 2, Self.maxInterval)
                    errorMessage = error.localizedDescription
                        + "\n次の再試行まで \(Int(currentInterval)) 秒空けます"
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    // メニューバーのゲージに使う limit
    var menuBarLimit: UsageLimit? {
        switch menuBarMetric {
        case .session:
            return limits.first { $0.kind == "session" }
        case .weekly:
            return limits
                .filter { $0.group == "weekly" || $0.kind.hasPrefix("weekly") }
                .max { ($0.percent ?? -1) < ($1.percent ?? -1) }
        case .max:
            return limits.max { ($0.percent ?? -1) < ($1.percent ?? -1) }
        }
    }
}
