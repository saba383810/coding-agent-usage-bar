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
        var limits = rateLimits(from: json)
        if let credits = creditsLimit(from: json) {
            limits.append(credits)
        }
        // 空のまま返すと「読み込み中…」から進まないので、形式変更として明示する
        guard !limits.isEmpty else { throw UsageError.noUsageData }
        return limits
    }

    // 5h / 週のレート制限。クレジット制のプランでは limits が空で five_hour なども null になる
    private static func rateLimits(from json: [String: Any]) -> [UsageLimit] {
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

    // 月間のクレジット消費。
    // 例: "spend": {"used": {"amount_minor": 1250, "currency": "USD", "exponent": 2},
    //              "limit": {"amount_minor": 10000, ...}, "percent": 12, "enabled": true}
    private static func creditsLimit(from json: [String: Any]) -> UsageLimit? {
        guard let spend = json["spend"] as? [String: Any],
              spend["enabled"] as? Bool ?? false,
              let used = money(spend["used"])
        else { return nil }
        let limit = money(spend["limit"])
        // API の percent は整数丸めなので、生の値から計算できるならそちらを使う
        let percent: Double? = {
            if let limit, limit.amount > 0 { return used.amount / limit.amount * 100 }
            return UsageParse.double(spend["percent"])
        }()
        var detail = "使用 \(used.formatted)"
        if let limit {
            let remaining = limit.amount - used.amount
            let label = remaining < 0 ? "超過" : "残り"
            let amount = Money(amount: abs(remaining), currency: limit.currency)
            detail += " / \(limit.formatted) (\(label) \(amount.formatted))"
        }
        return UsageLimit(
            provider: .claude,
            kind: "credits",
            group: "credits",
            percent: percent,
            severity: spend["severity"] as? String,
            resetsAt: startOfNextMonth(),
            details: [detail],
            customTitle: "Credits (monthly)"
        )
    }

    // API はリセット日時を返さないので、Claude Code の /usage と同じく
    // 翌月 1 日 0:00 (ローカル時刻) とみなす
    private static func startOfNextMonth() -> Date? {
        Calendar(identifier: .gregorian).dateInterval(of: .month, for: Date())?.end
    }

    private struct Money {
        let amount: Double
        let currency: String?

        var formatted: String {
            let formatter = NumberFormatter()
            if let currency {
                formatter.numberStyle = .currency
                formatter.currencyCode = currency
            } else {
                formatter.numberStyle = .decimal
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
            }
            return formatter.string(from: amount as NSNumber) ?? String(amount)
        }
    }

    // {"amount_minor": 1250, "currency": "USD", "exponent": 2} → 12.50 USD
    private static func money(_ value: Any?) -> Money? {
        guard let raw = value as? [String: Any],
              let minor = UsageParse.double(raw["amount_minor"])
        else { return nil }
        let exponent = UsageParse.double(raw["exponent"]) ?? 2
        return Money(amount: minor / pow(10, exponent), currency: raw["currency"] as? String)
    }
}
