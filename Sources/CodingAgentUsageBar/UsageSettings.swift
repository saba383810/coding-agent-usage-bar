import Foundation

enum ClaudeMetric: String, CaseIterable, Identifiable {
    case dailyPace
    case weeklyPace
    case credits

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyPace: return "Today (目安)"
        case .weeklyPace: return "Week (目安)"
        case .credits: return "Credits (月間の消費)"
        }
    }

    // 消した指標 (5h / 週の枠、全体の最大) は、近い目安に読み替える
    init(stored: String?) {
        switch stored {
        case "session": self = .dailyPace
        case "weeklyMax": self = .weeklyPace
        default: self = stored.flatMap(ClaudeMetric.init(rawValue:)) ?? .dailyPace
        }
    }
}

enum CodexMetric: String, CaseIterable, Identifiable {
    case dailyPace
    case weeklyPace
    case credits
    case creditTier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyPace: return "Today (目安)"
        case .weeklyPace: return "Week (目安)"
        case .credits: return "Credits (上限に対する消費)"
        case .creditTier: return "次の請求段階まで"
        }
    }
}

// 日・週の目安の設定。Claude と Codex で別々に持つ
struct PaceSettings: Equatable {
    var shows: Bool
    // 目安の「使用」を累計で数えるか、今日 (今週) に使った分で数えるか
    var daily: PaceUsageMode
    var weekly: PaceUsageMode
    var excludesHolidays: Bool
}

@MainActor
final class UsageSettings: ObservableObject {
    @Published var claudeEnabled: Bool { didSet { store(claudeEnabled, Key.claudeEnabled) } }
    @Published var codexEnabled: Bool { didSet { store(codexEnabled, Key.codexEnabled) } }
    @Published var claudeInMenuBar: Bool { didSet { store(claudeInMenuBar, Key.claudeInMenuBar) } }
    @Published var codexInMenuBar: Bool { didSet { store(codexInMenuBar, Key.codexInMenuBar) } }
    @Published var claudeMetric: ClaudeMetric { didSet { store(claudeMetric.rawValue, Key.claudeMetric) } }
    @Published var codexMetric: CodexMetric { didSet { store(codexMetric.rawValue, Key.codexMetric) } }
    @Published var showCreditCharge: Bool { didSet { store(showCreditCharge, Key.showCreditCharge) } }
    @Published var useMenuBarIcons: Bool { didSet { store(useMenuBarIcons, Key.useMenuBarIcons) } }
    @Published var claudePace: PaceSettings { didSet { store(claudePace, PaceKey.claude) } }
    @Published var codexPace: PaceSettings { didSet { store(codexPace, PaceKey.codex) } }
    // 目安の 1 日の区切り (0 時からの分)。Claude と Codex で共通
    @Published var dayStartMinutes: Int { didSet { store(dayStartMinutes, Key.dayStartMinutes) } }
    // Claude の月間上限を自分で決めた額に置き換える
    @Published var claudeOverridesLimit: Bool { didSet { store(claudeOverridesLimit, Key.claudeOverridesLimit) } }
    // 上書きする額。上書きを切っても残しておき、入れ直した時に使う
    @Published var claudeLimitOverride: Double? {
        didSet {
            if let claudeLimitOverride {
                store(claudeLimitOverride, Key.claudeLimitOverride)
            } else {
                defaults.removeObject(forKey: Key.claudeLimitOverride)
            }
        }
    }

    private enum Key {
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
        static let claudeInMenuBar = "claudeInMenuBar"
        static let codexInMenuBar = "codexInMenuBar"
        static let claudeMetric = "claudeMetric"
        static let codexMetric = "codexMetric"
        static let showCreditCharge = "showCreditCharge"
        static let useMenuBarIcons = "useMenuBarIcons"
        static let dayStartMinutes = "dayStartMinutes"
        static let claudeOverridesLimit = "claudeOverridesLimit"
        static let claudeLimitOverride = "claudeLimitOverride"
        // Claude と Codex で共通だった目安の数え方。どちらかを未設定のうちはこれを引き継ぐ
        static let legacyDailyPaceMode = "dailyPaceMode"
        static let legacyWeeklyPaceMode = "weeklyPaceMode"
        // v1 の「メニューバー表示」設定。claudeMetric に引き継いで削除する
        static let legacyMenuBarMetric = "menuBarMetric"
    }

    private struct PaceKey {
        let shows: String
        let daily: String
        let weekly: String
        let excludesHolidays: String

        static let claude = PaceKey(provider: "claude")
        static let codex = PaceKey(provider: "codex")

        private init(provider: String) {
            shows = "\(provider)ShowsPace"
            daily = "\(provider)DailyPaceMode"
            weekly = "\(provider)WeeklyPaceMode"
            excludesHolidays = "\(provider)PaceExcludesHolidays"
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyMetric(in: defaults)
        claudeEnabled = Self.bool(defaults, Key.claudeEnabled, default: true)
        codexEnabled = Self.bool(defaults, Key.codexEnabled, default: true)
        claudeInMenuBar = Self.bool(defaults, Key.claudeInMenuBar, default: true)
        codexInMenuBar = Self.bool(defaults, Key.codexInMenuBar, default: true)
        claudeMetric = ClaudeMetric(stored: defaults.string(forKey: Key.claudeMetric))
        codexMetric = CodexMetric(rawValue: defaults.string(forKey: Key.codexMetric) ?? "") ?? .credits
        showCreditCharge = Self.bool(defaults, Key.showCreditCharge, default: true)
        useMenuBarIcons = Self.bool(defaults, Key.useMenuBarIcons, default: false)
        claudePace = Self.pace(defaults, PaceKey.claude)
        codexPace = Self.pace(defaults, PaceKey.codex)
        dayStartMinutes = min(max(defaults.integer(forKey: Key.dayStartMinutes), 0), 24 * 60 - 1)
        let limitOverride = defaults.object(forKey: Key.claudeLimitOverride) as? Double
        claudeLimitOverride = limitOverride
        // 上書きのスイッチが無かった頃は、額が入っていれば上書きしていた
        claudeOverridesLimit = Self.bool(defaults, Key.claudeOverridesLimit, default: (limitOverride ?? 0) > 0)
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func store(_ pace: PaceSettings, _ key: PaceKey) {
        defaults.set(pace.shows, forKey: key.shows)
        defaults.set(pace.daily.rawValue, forKey: key.daily)
        defaults.set(pace.weekly.rawValue, forKey: key.weekly)
        defaults.set(pace.excludesHolidays, forKey: key.excludesHolidays)
    }

    private static func pace(_ defaults: UserDefaults, _ key: PaceKey) -> PaceSettings {
        func mode(_ key: String, legacy: String) -> PaceUsageMode {
            PaceUsageMode(rawValue: defaults.string(forKey: key) ?? defaults.string(forKey: legacy) ?? "") ?? .cumulative
        }
        return PaceSettings(
            shows: bool(defaults, key.shows, default: true),
            daily: mode(key.daily, legacy: Key.legacyDailyPaceMode),
            weekly: mode(key.weekly, legacy: Key.legacyWeeklyPaceMode),
            excludesHolidays: bool(defaults, key.excludesHolidays, default: false)
        )
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func migrateLegacyMetric(in defaults: UserDefaults) {
        guard let legacy = defaults.string(forKey: Key.legacyMenuBarMetric) else { return }
        switch legacy {
        case "session": defaults.set(ClaudeMetric.dailyPace.rawValue, forKey: Key.claudeMetric)
        case "weekly": defaults.set(ClaudeMetric.weeklyPace.rawValue, forKey: Key.claudeMetric)
        default: break
        }
        defaults.removeObject(forKey: Key.legacyMenuBarMetric)
    }
}
