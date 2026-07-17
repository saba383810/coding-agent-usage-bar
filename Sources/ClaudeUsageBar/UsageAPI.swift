import Foundation

struct UsageLimit: Identifiable {
    let kind: String
    let group: String?
    let percent: Double?
    let severity: String?
    let resetsAt: Date?
    let isActive: Bool?
    let modelName: String?

    var id: String { kind + (modelName ?? "") }

    var title: String {
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
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed:
            return "Keychain からトークンを取得できませんでした"
        case .credentialFormat:
            return "認証情報の形式が想定と異なります"
        case .httpStatus(let code):
            if code == 401 {
                return "トークン期限切れの可能性 (Claude Code を起動すると更新されます)"
            }
            return "API エラー (HTTP \(code))"
        }
    }
}

enum UsageAPI {
    private static let keychainService = "Claude Code-credentials"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async throws -> [UsageLimit] {
        let token = try readAccessToken()
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UsageError.httpStatus(http.statusCode)
        }
        return try parse(data)
    }

    // Claude Code が Keychain に保存している OAuth 認証情報を読む。
    // SecItemCopyMatching だとアプリ署名ごとに ACL 許可が必要になるため、
    // ACL 許可済みの /usr/bin/security を経由する。
    private static func readAccessToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw UsageError.keychainReadFailed
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageError.keychainReadFailed
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            throw UsageError.credentialFormat
        }
        return token
    }

    private static func parse(_ data: Data) throws -> [UsageLimit] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.credentialFormat
        }
        if let rawLimits = json["limits"] as? [[String: Any]], !rawLimits.isEmpty {
            return rawLimits.map { raw in
                let scope = raw["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                return UsageLimit(
                    kind: raw["kind"] as? String ?? "unknown",
                    group: raw["group"] as? String,
                    percent: doubleValue(raw["percent"]),
                    severity: raw["severity"] as? String,
                    resetsAt: parseDate(raw["resets_at"] as? String),
                    isActive: raw["is_active"] as? Bool,
                    modelName: model?["display_name"] as? String
                )
            }
        }
        // limits が空の場合のフォールバック
        var limits: [UsageLimit] = []
        if let fiveHour = json["five_hour"] as? [String: Any] {
            limits.append(UsageLimit(
                kind: "session", group: "session",
                percent: doubleValue(fiveHour["utilization"]),
                severity: nil,
                resetsAt: parseDate(fiveHour["resets_at"] as? String),
                isActive: nil, modelName: nil
            ))
        }
        if let sevenDay = json["seven_day"] as? [String: Any] {
            limits.append(UsageLimit(
                kind: "weekly_all", group: "weekly",
                percent: doubleValue(sevenDay["utilization"]),
                severity: nil,
                resetsAt: parseDate(sevenDay["resets_at"] as? String),
                isActive: nil, modelName: nil
            ))
        }
        return limits
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        // 例: 2026-07-17T13:50:00.408818+00:00 (マイクロ秒つき ISO8601)
        let withFraction = DateFormatter()
        withFraction.locale = Locale(identifier: "en_US_POSIX")
        withFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = withFraction.date(from: string) { return date }
        let iso = ISO8601DateFormatter()
        return iso.date(from: string)
    }
}
