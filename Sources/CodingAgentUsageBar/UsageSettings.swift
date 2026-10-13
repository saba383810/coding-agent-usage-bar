import Foundation

enum ClaudeMetric: String, CaseIterable, Identifiable {
    case dailyPace
    case weeklyPace
    case credits
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyPace: return "Today (目安)"
        case .weeklyPace: return "Week (目安)"
        case .credits: return "Credits (月間の消費)"
        case .max: return "全体の最大"
        }
    }

    // 5h / 週の枠が無くなって消した指標は、近い目安に読み替える
    init(stored: String?) {
        switch stored {
        case "session": self = .dailyPace
        case "weeklyMax": self = .weeklyPace
        default: self = stored.flatMap(ClaudeMetric.init(rawValue:)) ?? .dailyPace
        }
    }
}

enum CodexMetric: String, CaseIterable, Identifiable {
    case credits
    case creditTier
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .credits: return "Credits (上限に対する消費)"
        case .creditTier: return "次の請求段階まで"
        case .max: return "全体の最大"
        }
    }
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
    @Published var claudeShowsPace: Bool { didSet { store(claudeShowsPace, Key.claudeShowsPace) } }
    // 目安の「使用」を累計で数えるか、今日 (今週) に使った分で数えるか
    @Published var dailyPaceMode: PaceUsageMode { didSet { store(dailyPaceMode.rawValue, Key.dailyPaceMode) } }
    @Published var weeklyPaceMode: PaceUsageMode { didSet { store(weeklyPaceMode.rawValue, Key.weeklyPaceMode) } }
    // Claude の月間上限を自分で決めた額に置き換える (nil なら API の上限)
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
        static let claudeShowsPace = "claudeShowsPace"
        static let dailyPaceMode = "dailyPaceMode"
        static let weeklyPaceMode = "weeklyPaceMode"
        static let claudeLimitOverride = "claudeLimitOverride"
        // v1 の「メニューバー表示」設定。claudeMetric に引き継いで削除する
        static let legacyMenuBarMetric = "menuBarMetric"
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
        claudeShowsPace = Self.bool(defaults, Key.claudeShowsPace, default: true)
        dailyPaceMode = PaceUsageMode(rawValue: defaults.string(forKey: Key.dailyPaceMode) ?? "") ?? .cumulative
        weeklyPaceMode = PaceUsageMode(rawValue: defaults.string(forKey: Key.weeklyPaceMode) ?? "") ?? .cumulative
        claudeLimitOverride = defaults.object(forKey: Key.claudeLimitOverride) as? Double
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func migrateLegacyMetric(in defaults: UserDefaults) {
        guard let legacy = defaults.string(forKey: Key.legacyMenuBarMetric) else { return }
        switch legacy {
        case "session": defaults.set(ClaudeMetric.dailyPace.rawValue, forKey: Key.claudeMetric)
        case "weekly": defaults.set(ClaudeMetric.weeklyPace.rawValue, forKey: Key.claudeMetric)
        case "max": defaults.set(ClaudeMetric.max.rawValue, forKey: Key.claudeMetric)
        default: break
        }
        defaults.removeObject(forKey: Key.legacyMenuBarMetric)
    }
}
