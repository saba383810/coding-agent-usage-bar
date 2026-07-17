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
    private static let refreshInterval: TimeInterval = 60
    private var timer: Timer?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.metricKey)
        menuBarMetric = MenuBarMetric(rawValue: saved ?? "") ?? .session
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        Task {
            do {
                let fetched = try await UsageAPI.fetch()
                limits = fetched
                lastUpdated = Date()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
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
