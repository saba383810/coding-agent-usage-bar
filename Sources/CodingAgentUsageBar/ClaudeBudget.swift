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
        showsPace: Bool,
        now: Date = Date()
    ) -> [UsageLimit] {
        let calendar = Calendar(identifier: .gregorian)
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        // 設定で上限を上書きしていれば、% と目安はその額で計算する
        let limit = limitOverride.map { spend.used.with(amount: $0) } ?? spend.limit
        var rows: [UsageLimit] = []
        if showsPace, let limit, limit.amount > 0 {
            rows += paceLimits(used: spend.used, limit: limit, month: month, calendar: calendar, now: now)
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

    // 月の上限を日割りした目安。
    // 使用量は月初からの累計しか取れないので、期間の開始時点までに使ってよかった額を超えた分を
    // その期間の消費とみなす。前日 (前週) までに使いすぎていれば、期間の始めから 100% になりうる。
    private static func paceLimits(
        used: Money,
        limit: Money,
        month: DateInterval,
        calendar: Calendar,
        now: Date
    ) -> [UsageLimit] {
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daily = limit.amount / Double(daysInMonth)

        func days(from start: Date, to end: Date) -> Double {
            Double(calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        }

        func row(kind: String, title: String, period: DateInterval) -> UsageLimit {
            let base = daily * days(from: month.start, to: period.start)
            let budget = daily * days(from: period.start, to: period.end)
            let spent = max(used.amount - base, 0)
            return UsageLimit(
                provider: .claude,
                kind: kind,
                group: "pace",
                percent: budget > 0 ? spent / budget * 100 : nil,
                resetsAt: period.end,
                details: ["使用 \(limit.with(amount: spent).formatted) / 目安 \(limit.with(amount: budget).formatted)"],
                customTitle: title
            )
        }

        var rows: [UsageLimit] = []
        if let today = calendar.dateInterval(of: .day, for: now) {
            rows.append(row(kind: "pace_daily", title: "Today (目安)", period: today))
        }
        // 週は月曜始まり。月をまたぐ週は月の境界で区切り、その日数分を目安にする
        if let week = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: now) {
            let period = DateInterval(start: max(week.start, month.start), end: min(week.end, month.end))
            rows.append(row(kind: "pace_weekly", title: "Week (目安)", period: period))
        }
        return rows
    }
}
