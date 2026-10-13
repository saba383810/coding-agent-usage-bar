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

// API は請求期間の累計しか返さないので、取れた累計を日ごとに最初と最後の 1 件ずつ残しておき、
// 今日・今週に使った分をその差分で出す
struct UsageHistory {
    struct Sample {
        let at: Date
        let used: Double
    }

    private struct Day {
        var first: Sample
        var last: Sample

        init(first: Sample, last: Sample) {
            self.first = first
            self.last = last
        }

        init?(plist: [String: Double]) {
            guard
                let firstAt = plist["firstAt"], let first = plist["first"],
                let lastAt = plist["lastAt"], let last = plist["last"]
            else { return nil }
            self.first = Sample(at: Date(timeIntervalSince1970: firstAt), used: first)
            self.last = Sample(at: Date(timeIntervalSince1970: lastAt), used: last)
        }

        var plist: [String: Double] {
            [
                "firstAt": first.at.timeIntervalSince1970, "first": first.used,
                "lastAt": last.at.timeIntervalSince1970, "last": last.used,
            ]
        }
    }

    private let key: String
    private let defaults: UserDefaults
    // "yyyy-MM-dd" (ローカル日付) -> その日に最初と最後に取れた累計
    private var days: [String: Day] = [:]

    init(key: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        self.key = key
        self.defaults = defaults
        for (day, value) in defaults.dictionary(forKey: key) ?? [:] {
            if let plist = value as? [String: Double] {
                days[day] = Day(plist: plist)
            } else if let used = value as? Double, day == Self.dayKey(now) {
                // v1.4.0 までは日ごとに最初に取れた累計だけを残していて、取れた時刻が分からない。
                // 前日の最後の値としては使えないので、今日の分だけを読み込んだ時刻に取れたものとして引き継ぐ
                let sample = Sample(at: now, used: used)
                days[day] = Day(first: sample, last: sample)
            }
        }
    }

    mutating func record(_ used: Double, at date: Date = Date()) {
        let sample = Sample(at: date, used: used)
        let day = Self.dayKey(date)
        if days[day] == nil {
            days[day] = Day(first: sample, last: sample)
            // 使うのは今週の初めの前日までなので、古い記録は 2 か月分だけ残す
            if let cutoff = Calendar.current.date(byAdding: .day, value: -62, to: date) {
                let cutoffKey = Self.dayKey(cutoff)
                days = days.filter { $0.key >= cutoffKey }
            }
        } else {
            days[day]?.last = sample
        }
        defaults.set(days.mapValues(\.plist), forKey: key)
    }

    // date より前で最後に取れた累計
    func lastSample(before date: Date) -> Sample? {
        samples.filter { $0.at < date }.max { $0.at < $1.at }
    }

    // date 以降で最初に取れた累計
    func firstSample(onOrAfter date: Date) -> Sample? {
        samples.filter { $0.at >= date }.min { $0.at < $1.at }
    }

    private var samples: [Sample] {
        days.values.flatMap { [$0.first, $0.last] }
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
                } else if let prior = history.lastSample(before: span.start),
                          prior.at >= period.start,
                          span.start.timeIntervalSince(prior.at) <= 86_400 {
                    // 前日 (前週の最終日) の最後の記録から数える。
                    // Mac がスリープしていた間の使用もこちらに入るので、日ごとの分を足すと累計に一致する
                    spent = max(used - prior.used, 0)
                } else if let first = history.firstSample(onOrAfter: span.start) {
                    // 直前の記録が無い (アプリを入れた日や、Mac を 1 日以上止めていた後) ので、
                    // 期間内で最初に取れた時から数える。それより前の使用は数えられない
                    spent = max(used - first.used, 0)
                    details.append("記録は \(isWeek ? dayText(first.at) + " " : "")\(timeText(first.at)) から")
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

    private static func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
