import Foundation

struct Money {
    let amount: Double
    let currency: String?

    func with(amount: Double) -> Money {
        Money(amount: amount, currency: currency)
    }

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

// Claude の月間クレジット消費 (usage API の spend)
struct ClaudeSpend {
    let used: Money
    let limit: Money?
    let severity: String?
    // limit が無い時の消費率。API の値は整数丸め
    let percent: Double?
}

// 月間のクレジット消費から、表示用の行 (日・週の目安と Credits) を組み立てる
enum ClaudeBudget {
    static func limits(
        spend: ClaudeSpend,
        limitOverride: Double?,
        pace: PaceOptions?,
        history: UsageHistory,
        now: Date = Date()
    ) -> [UsageLimit] {
        let calendar = Calendar(identifier: .gregorian)
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        // 設定で上限を上書きしていれば、% と目安はその額で計算する
        let limit = limitOverride.map { spend.used.with(amount: $0) } ?? spend.limit
        var rows: [UsageLimit] = []
        if let pace, let limit {
            rows += SpendPace.limits(
                provider: .claude,
                used: spend.used.amount,
                limit: limit.amount,
                period: month,
                options: pace,
                history: history,
                format: { limit.with(amount: $0).formatted },
                now: now
            )
        }
        rows.append(creditsLimit(spend: spend, limit: limit, isOverridden: limitOverride != nil, month: month))
        return rows
    }

    private static func creditsLimit(
        spend: ClaudeSpend,
        limit: Money?,
        isOverridden: Bool,
        month: DateInterval
    ) -> UsageLimit {
        let used = spend.used
        // API の percent は整数丸めなので、生の値から計算できるならそちらを使う
        let percent: Double? = {
            if let limit, limit.amount > 0 { return used.amount / limit.amount * 100 }
            return spend.percent
        }()
        var details = ["使用 \(used.formatted)"]
        if let limit {
            let remaining = limit.amount - used.amount
            let label = remaining < 0 ? "超過" : "残り"
            details[0] += " / \(limit.formatted) (\(label) \(used.with(amount: abs(remaining)).formatted))"
        }
        if isOverridden, let apiLimit = spend.limit {
            details.append("上限は設定で上書き中 (API: \(apiLimit.formatted))")
        }
        return UsageLimit(
            provider: .claude,
            kind: "credits",
            group: "credits",
            percent: percent,
            severity: spend.severity,
            // API はリセット日時を返さないので、Claude Code の /usage と同じく
            // 翌月 1 日 0:00 (ローカル時刻) とみなす
            resetsAt: month.end,
            details: details,
            customTitle: "Credits (monthly)"
        )
    }
}
