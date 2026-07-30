import Foundation

enum ClaudeUsageAPI {
    private static let keychainService = "Claude Code-credentials"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // Claude Code にログインしていなければ表示自体を省くための判定
    static var isConfigured: Bool {
        (try? readAccessToken()) != nil
    }

    static func fetch() async throws -> [UsageLimit] {
        let token = try readAccessToken()
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UsageError.httpStatus(http.statusCode, UsageParse.errorDetail(from: data), .claude)
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
                    provider: .claude,
                    kind: raw["kind"] as? String ?? "unknown",
                    group: raw["group"] as? String,
                    percent: UsageParse.double(raw["percent"]),
                    severity: raw["severity"] as? String,
                    resetsAt: UsageParse.date(raw["resets_at"] as? String),
                    isActive: raw["is_active"] as? Bool,
                    modelName: model?["display_name"] as? String
                )
            }
        }
        // limits が空の場合のフォールバック
        var limits: [UsageLimit] = []
        if let fiveHour = json["five_hour"] as? [String: Any] {
            limits.append(UsageLimit(
                provider: .claude,
                kind: "session",
                group: "session",
                percent: UsageParse.double(fiveHour["utilization"]),
                resetsAt: UsageParse.date(fiveHour["resets_at"] as? String)
            ))
        }
        if let sevenDay = json["seven_day"] as? [String: Any] {
            limits.append(UsageLimit(
                provider: .claude,
                kind: "weekly_all",
                group: "weekly",
                percent: UsageParse.double(sevenDay["utilization"]),
                resetsAt: UsageParse.date(sevenDay["resets_at"] as? String)
            ))
        }
        return limits
    }
}
