import Foundation

// 目安の「使用」をどう数えるか
enum PaceUsageMode: String, CaseIterable, Identifiable {
    // 請求期間の初めからの累計を、今日 (今週) の終わりまでの目安の累計と比べる
    case cumulative
    // 今日 (今週) に使った分だけを、1 日 (1 週) 分の目安と比べる
    case period

    var id: String { rawValue }
}

struct PaceOptions {
    let daily: PaceUsageMode
    let weekly: PaceUsageMode
}

// API は請求期間の累計しか返さないので、日ごとに最初に取れた累計を残しておき、
// 今日・今週に使った分をその差分で出す
struct UsageHistory {
    private let key: String
    private let defaults: UserDefaults
    // "yyyy-MM-dd" (ローカル日付) -> その日に最初に取れた累計
    private var firstUsed: [String: Double]

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        firstUsed = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    mutating func record(_ used: Double, at date: Date = Date()) {
        let day = Self.dayKey(date)
        guard firstUsed[day] == nil else { return }
        firstUsed[day] = used
        // 使うのは今週の初めまでなので、古い記録は 2 か月分だけ残す
        if let cutoff = Calendar.current.date(byAdding: .day, value: -62, to: date) {
            let cutoffKey = Self.dayKey(cutoff)
            firstUsed = firstUsed.filter { $0.key >= cutoffKey }
        }
        defaults.set(firstUsed, forKey: key)
    }

    // date の日以降で最初に記録がある日と、その日に最初に取れた累計
    func firstRecord(onOrAfter date: Date) -> (day: Date, used: Double)? {
        let startKey = Self.dayKey(date)
        guard
            let entry = firstUsed.filter({ $0.key >= startKey }).min(by: { $0.key < $1.key }),
            let day = Self.formatter.date(from: entry.key)
        else { return nil }
        return (day, entry.value)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayKey(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

// 請求期間の上限を日割りした目安 (Today / Week)
enum SpendPace {
    static func limits(
        provider: UsageProvider,
        used: Double,
        limit: Double,
        period: DateInterval,
        options: PaceOptions,
        history: UsageHistory,
        format: (Double) -> String,
        now: Date = Date()
    ) -> [UsageLimit] {
        guard limit > 0, period.duration > 0 else { return [] }

        // 目安は期間の長さに比例させる。Codex のように 0 時以外に始まる請求期間でもそのまま使える
        func budget(from start: Date, to end: Date) -> Double {
            limit * end.timeIntervalSince(start) / period.duration
        }

        func row(kind: String, title: String, span: DateInterval, mode: PaceUsageMode, spanName: String) -> UsageLimit {
            let isWeek = kind == "pace_weekly"
            switch mode {
            case .cumulative:
                // 使いすぎた分はそのまま持ち越すので、朝の時点で 100% を超えることもある
                let target = budget(from: period.start, to: span.end)
                return UsageLimit(
                    provider: provider,
                    kind: kind,
                    group: "pace",
                    percent: target > 0 ? used / target * 100 : nil,
                    details: ["累計 \(format(used)) / 目安 \(format(target)) (\(dayRange(period.start, span.end)))"],
                    customTitle: title
                )
            case .period:
                let target = budget(from: span.start, to: span.end)
                var details: [String] = []
                let spent: Double?
                if span.start <= period.start {
                    // 請求期間の初めからの期間なら、累計がそのまま使った分
                    spent = used
                } else if let record = history.firstRecord(onOrAfter: span.start) {
                    spent = max(used - record.used, 0)
                    if record.day > span.start {
                        // それより前はアプリが動いておらず、その間の使用は数えられない
                        details.append("記録は \(dayText(record.day)) から")
                    }
                } else {
                    // 日付が変わってからまだ取得していない
                    spent = nil
                }
                var line = "\(spanName)の使用 \(spent.map(format) ?? "–") / 目安 \(format(target))"
                if isWeek { line += " (\(dayRange(span.start, span.end)))" }
                details.insert(line, at: 0)
                return UsageLimit(
                    provider: provider,
                    kind: kind,
                    group: "pace",
                    percent: spent.flatMap { target > 0 ? $0 / target * 100 : nil },
                    resetsAt: span.end,
                    details: details,
                    customTitle: title
                )
            }
        }

        var rows: [UsageLimit] = []
        if let today = Calendar.current.dateInterval(of: .day, for: now)?.intersection(with: period) {
            rows.append(row(kind: "pace_daily", title: "Today (目安)", span: today, mode: options.daily, spanName: "今日"))
        }
        // 週は月曜始まり。請求期間をまたぐ週は期間の境界で区切り、その長さ分を目安にする
        if let week = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: now)?.intersection(with: period) {
            rows.append(row(kind: "pace_weekly", title: "Week (目安)", span: week, mode: options.weekly, spanName: "今週"))
        }
        return rows
    }

    // 終わりは含まないので 1 秒戻した日を出す ("10/1〜10/13")
    private static func dayRange(_ start: Date, _ end: Date) -> String {
        "\(dayText(start))〜\(dayText(end.addingTimeInterval(-1)))"
    }

    private static func dayText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}
