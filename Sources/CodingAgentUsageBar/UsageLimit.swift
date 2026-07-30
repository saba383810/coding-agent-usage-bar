import Foundation

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    // メニューバーでゲージを並べる時の識別子
    var shortLabel: String {
        switch self {
        case .claude: return "Cl"
        case .codex: return "Cx"
        }
    }

    // アイコン表示にした時の SF Symbol。商標ロゴは使わず近い形の汎用記号を当てる
    var symbolName: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "hexagon"
        }
    }

    // 401 のときに案内するアプリ名
    var refreshHint: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

// クレジットの請求段階と、その段階内での進捗
struct CreditTier {
    // 今いる段階の中でどこまで進んだか (0-100)
    let percent: Double
    let summary: String
    let remainingText: String?
}

struct UsageLimit: Identifiable {
    let provider: UsageProvider
    let kind: String
    let group: String?
    let percent: Double?
    let severity: String?
    let resetsAt: Date?
    let isActive: Bool?
    let modelName: String?
    // クレジット残高など、% だけでは足りない補足行
    let details: [String]
    // 請求段階。設定で表示を切り替えるため details とは分けて持つ
    let creditTier: CreditTier?
    // provider 固有の表示名 (nil なら kind から組み立てる)
    let customTitle: String?

    init(
        provider: UsageProvider,
        kind: String,
        group: String? = nil,
        percent: Double? = nil,
        severity: String? = nil,
        resetsAt: Date? = nil,
        isActive: Bool? = nil,
        modelName: String? = nil,
        details: [String] = [],
        creditTier: CreditTier? = nil,
        customTitle: String? = nil
    ) {
        self.provider = provider
        self.kind = kind
        self.group = group
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.modelName = modelName
        self.details = details
        self.creditTier = creditTier
        self.customTitle = customTitle
    }

    var id: String { provider.rawValue + kind + (modelName ?? "") }

    var title: String {
        if let customTitle { return customTitle }
        switch kind {
        case "session": return "Session (5h)"
        case "weekly_all": return "Week (all models)"
        case "weekly_scoped": return "Week (\(modelName ?? "scoped"))"
        default: return kind
        }
    }
}

enum UsageError: LocalizedError {
    case keychainReadFailed
    case credentialFormat
    case httpStatus(Int, String?, UsageProvider)
    case codexAuthMissing
    case codexAuthFormat

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed:
            return "Keychain からトークンを取得できませんでした"
        case .credentialFormat:
            return "認証情報の形式が想定と異なります"
        case .httpStatus(let code, let detail, let provider):
            var message = code == 401
                ? "トークン期限切れの可能性 (\(provider.refreshHint) を起動すると更新されます)"
                : "API エラー (HTTP \(code))"
            if let detail, !detail.isEmpty {
                message += "\n\(detail)"
            }
            return message
        case .codexAuthMissing:
            return "~/.codex/auth.json が見つかりません"
        case .codexAuthFormat:
            return "~/.codex/auth.json の形式が想定と異なります"
        }
    }
}

enum UsageParse {
    static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        // 例: 2026-07-17T13:50:00.408818+00:00 (マイクロ秒つき ISO8601)
        let withFraction = DateFormatter()
        withFraction.locale = Locale(identifier: "en_US_POSIX")
        withFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = withFraction.date(from: string) { return date }
        let iso = ISO8601DateFormatter()
        return iso.date(from: string)
    }

    // Codex の reset_at は Unix epoch 秒
    static func epochDate(_ value: Any?) -> Date? {
        guard let seconds = double(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // エラーレスポンスのボディから表示用の詳細を取り出す。
    // 標準形: {"error": {"type": "rate_limit_error", "message": "..."}}
    static func errorDetail(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                let parts = [error["type"] as? String, error["message"] as? String]
                    .compactMap { $0 }
                if !parts.isEmpty { return parts.joined(separator: ": ") }
            }
            if let message = json["message"] as? String { return message }
            if let detail = json["detail"] as? String { return detail }
        }
        guard let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty
        else { return nil }
        return String(body.prefix(200))
    }
}
