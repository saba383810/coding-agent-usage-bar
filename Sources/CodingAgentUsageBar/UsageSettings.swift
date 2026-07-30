import Foundation

enum ClaudeMetric: String, CaseIterable, Identifiable {
    case session
    case weeklyMax
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: return "Session (5h)"
        case .weeklyMax: return "Week (最大)"
        case .max: return "全体の最大"
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

    private enum Key {
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
        static let claudeInMenuBar = "claudeInMenuBar"
        static let codexInMenuBar = "codexInMenuBar"
        static let claudeMetric = "claudeMetric"
        static let codexMetric = "codexMetric"
        static let showCreditCharge = "showCreditCharge"
        static let useMenuBarIcons = "useMenuBarIcons"
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
        claudeMetric = ClaudeMetric(rawValue: defaults.string(forKey: Key.claudeMetric) ?? "") ?? .session
        codexMetric = CodexMetric(rawValue: defaults.string(forKey: Key.codexMetric) ?? "") ?? .credits
        showCreditCharge = Self.bool(defaults, Key.showCreditCharge, default: true)
        useMenuBarIcons = Self.bool(defaults, Key.useMenuBarIcons, default: false)
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
        case "session": defaults.set(ClaudeMetric.session.rawValue, forKey: Key.claudeMetric)
        case "weekly": defaults.set(ClaudeMetric.weeklyMax.rawValue, forKey: Key.claudeMetric)
        case "max": defaults.set(ClaudeMetric.max.rawValue, forKey: Key.claudeMetric)
        default: break
        }
        defaults.removeObject(forKey: Key.legacyMenuBarMetric)
    }
}
