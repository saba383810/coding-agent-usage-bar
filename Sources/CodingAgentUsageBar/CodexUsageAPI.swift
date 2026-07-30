import Foundation

enum CodexUsageAPI {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
    private static var authURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
    }

    // Codex を使っていない環境では Codex セクションを出さないための判定
    static var isConfigured: Bool {
        (try? readAuth()) != nil
    }

    static func fetch() async throws -> [UsageLimit] {
        let auth = try readAuth()
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        // ChatGPT backend は User-Agent なしのリクエストを 403 で弾くため必須
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UsageError.httpStatus(http.statusCode, UsageParse.errorDetail(from: data), .codex)
        }
        return try parse(data)
    }

    private static var userAgent: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return "codex_cli_rs/0.0.0 (Mac OS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion); \(arch))"
    }

    private struct CodexAuth {
        let accessToken: String
        let accountID: String?
    }

    // Codex CLI が ~/.codex/auth.json に保存している OAuth 認証情報を読む。
    // トークンの更新は Codex CLI 側に任せる (期限切れは 401 として表示するだけ)。
    private static func readAuth() throws -> CodexAuth {
        guard let data = try? Data(contentsOf: authURL) else {
            throw UsageError.codexAuthMissing
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String, !token.isEmpty
        else {
            throw UsageError.codexAuthFormat
        }
        return CodexAuth(accessToken: token, accountID: tokens["account_id"] as? String)
    }

    static func parse(_ data: Data) throws -> [UsageLimit] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.codexAuthFormat
        }
        var limits: [UsageLimit] = []

        // プラン共通のレート制限 (business など制限のないプランでは null)
        if let rateLimit = json["rate_limit"] as? [String: Any] {
            limits += windowLimits(from: rateLimit, name: nil, keySuffix: "")
        }

        // モデル別・機能別の制限 (GPT-5.3-Codex-Spark-Preview など)。
        // クレジット制のプランでは使っていないモデルの枠が 0% で並ぶだけなので、
        // 実際に消費がある枠に限って出す。
        if let additional = json["additional_rate_limits"] as? [[String: Any]] {
            for (index, entry) in additional.enumerated() {
                guard let rateLimit = entry["rate_limit"] as? [String: Any] else { continue }
                let name = entry["limit_name"] as? String
                // kind が衝突すると ForEach の id が重複するため、識別子が無ければ index で補う
                let suffix = (entry["metered_feature"] as? String) ?? name ?? String(index)
                limits += windowLimits(from: rateLimit, name: name, keySuffix: "_" + suffix)
                    .filter { ($0.percent ?? 0) > 0 }
            }
        }

        // ワークスペースの支出上限 = 残りクレジット相当
        if let spend = json["spend_control"] as? [String: Any],
           let individual = spend["individual_limit"] as? [String: Any] {
            let limit = UsageParse.double(individual["limit"])
            let used = UsageParse.double(individual["used"])
            let remaining = UsageParse.double(individual["remaining"])
            // API の used_percent は整数丸めなので、生の値から計算できるならそちらを使う
            let percent: Double? = {
                if let limit, limit > 0, let used { return used / limit * 100 }
                return UsageParse.double(individual["used_percent"])
            }()
            limits.append(UsageLimit(
                provider: .codex,
                kind: "credits",
                group: "credits",
                percent: percent,
                resetsAt: resetDate(individual),
                details: creditDetails(used: used, limit: limit, remaining: remaining),
                creditTier: creditTier(used: used, limit: limit),
                customTitle: "Credits"
            ))
        }

        // クレジット残高 (spend control ではなく残高で管理されるプラン)
        if let credits = json["credits"] as? [String: Any] {
            let unlimited = credits["unlimited"] as? Bool ?? false
            let balance = UsageParse.double(credits["balance"])
            if unlimited || balance != nil {
                let detail: String = {
                    if unlimited { return "無制限" }
                    guard let balance else { return "–" }
                    return "残高 \(formatted(balance))"
                }()
                limits.append(UsageLimit(
                    provider: .codex,
                    kind: "credit_balance",
                    group: "credits",
                    percent: nil,
                    details: [detail],
                    customTitle: "Credit balance"
                ))
            }
        }

        return limits
    }

    // rate_limit の primary_window / secondary_window を UsageLimit に変換する
    private static func windowLimits(
        from rateLimit: [String: Any],
        name: String?,
        keySuffix: String
    ) -> [UsageLimit] {
        var result: [UsageLimit] = []
        let windows: [(key: String, kind: String, group: String)] = [
            ("primary_window", "session", "session"),
            ("secondary_window", "weekly_all", "weekly"),
        ]
        for window in windows {
            guard let raw = rateLimit[window.key] as? [String: Any] else { continue }
            let label = windowLabel(UsageParse.double(raw["limit_window_seconds"]))
            result.append(UsageLimit(
                provider: .codex,
                kind: window.kind + keySuffix,
                group: window.group,
                percent: UsageParse.double(raw["used_percent"]),
                resetsAt: resetDate(raw),
                modelName: name,
                customTitle: windowTitle(group: window.group, label: label, name: name)
            ))
        }
        return result
    }

    // "GPT-5.3-Codex-Spark-Preview (5h)" / "Session (5h)" / "Week"
    private static func windowTitle(group: String, label: String, name: String?) -> String {
        if let name {
            return label.isEmpty ? name : "\(name) (\(label))"
        }
        if group == "session" {
            return label.isEmpty ? "Session" : "Session (\(label))"
        }
        return (label.isEmpty || label == "Week") ? "Week" : "Week (\(label))"
    }

    // reset_at (epoch 秒) を優先し、無ければ reset_after_seconds から算出する
    private static func resetDate(_ raw: [String: Any]) -> Date? {
        if let date = UsageParse.epochDate(raw["reset_at"]) { return date }
        if let after = UsageParse.double(raw["reset_after_seconds"]), after > 0 {
            return Date().addingTimeInterval(after)
        }
        return nil
    }

    // 18000 -> "5h", 604800 -> "Week"
    private static func windowLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let total = Int(seconds)
        if total % 604_800 == 0 {
            let weeks = total / 604_800
            return weeks == 1 ? "Week" : "\(weeks) weeks"
        }
        if total % 86_400 == 0 { return "\(total / 86_400)d" }
        if total % 3_600 == 0 { return "\(total / 3_600)h" }
        return "\(total / 60)m"
    }

    private static func creditDetails(used: Double?, limit: Double?, remaining: Double?) -> [String] {
        if let used, let limit {
            var line = "使用 \(formatted(used)) / \(formatted(limit))"
            if let remaining {
                line += remaining < 0
                    ? " (超過 \(formatted(-remaining)))"
                    : " (残り \(formatted(remaining)))"
            }
            return [line]
        }
        if let remaining, let limit {
            return ["残り \(formatted(remaining)) / \(formatted(limit))"]
        }
        if let remaining { return ["残り \(formatted(remaining))"] }
        return []
    }

    // ChatGPT Business / Enterprise シートのクレジット請求段階。
    //   0 クレジット       -> 請求なし
    //   ~1,000 クレジット  -> 40 ドル
    //   ~20,000 クレジット -> 200 ドル
    //   20,000 超          -> 翌月まで利用不可 (上限緩和申請で継続可)
    // 2026/7-8 の 3 倍キャンペーン中は上限が 3 倍になり、API の limit は 60,000 を返す。
    // 段階の境界も同じ倍率で動くため、固定値ではなく limit に対する比率で判定する。
    private static let firstTierRatio = 1.0 / 20.0 // 1,000 / 20,000

    private static func creditTier(used: Double?, limit: Double?) -> CreditTier? {
        guard let used, let limit, limit > 0 else { return nil }
        let firstTier = limit * firstTierRatio
        guard used > 0 else {
            return CreditTier(
                percent: 0,
                summary: "請求なし → 使い始めると 40 ドル",
                remainingText: nil
            )
        }
        if used <= firstTier {
            return CreditTier(
                percent: used / firstTier * 100,
                summary: "請求 40 ドル → 次は 200 ドル",
                remainingText: "次の段階まで \(formatted(firstTier - used))"
            )
        }
        if used <= limit {
            return CreditTier(
                percent: (used - firstTier) / (limit - firstTier) * 100,
                summary: "請求 200 ドル → 超えると翌月まで利用不可",
                remainingText: "上限まで \(formatted(limit - used))"
            )
        }
        return CreditTier(
            percent: 100,
            summary: "上限超過 — 翌月まで利用不可 (上限緩和申請で継続可)",
            remainingText: nil
        )
    }

    // 小さい値は小数を残し、大きい値は整数で丸める
    private static func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = abs(value) < 100 ? 2 : 0
        return formatter.string(from: value as NSNumber) ?? String(value)
    }
}
