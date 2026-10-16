import Foundation

// 目安を割り振る「1 日」の扱い。区切りの時刻を 0 時からずらせて、土日祝を外せる
struct PaceCalendar {
    // 1 日の区切り (0 時からの秒数)
    let dayStart: TimeInterval
    // 土日と祝日には目安を割り振らない
    let excludesHolidays: Bool
    private let calendar = Calendar.current

    init(dayStart: TimeInterval = 0, excludesHolidays: Bool = false) {
        self.dayStart = dayStart
        self.excludesHolidays = excludesHolidays
    }

    // date を含む 1 日 (区切りの時刻から翌日の区切りの時刻まで)
    func day(containing date: Date) -> DateInterval? {
        calendar.dateInterval(of: .day, for: date.addingTimeInterval(-dayStart)).map(shifted)
    }

    // date を含む週 (月曜の区切りの時刻から)
    func week(containing date: Date) -> DateInterval? {
        Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: date.addingTimeInterval(-dayStart)).map(shifted)
    }

    // 目安を割り振る長さ (秒)。休日を除く時は、休日に当たる部分を数えない
    func weight(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }
        guard excludesHolidays else { return end.timeIntervalSince(start) }
        var total: TimeInterval = 0
        var cursor = start
        while cursor < end, let day = day(containing: cursor), day.end > cursor {
            let segmentEnd = min(day.end, end)
            if isWorkday(day) { total += segmentEnd.timeIntervalSince(cursor) }
            cursor = segmentEnd
        }
        return total
    }

    // 区切りの時刻をずらした日付の範囲 ("10/12〜10/18")。終わりは含まないので 1 秒戻す
    func rangeText(_ start: Date, _ end: Date) -> String {
        "\(dateText(start))〜\(dateText(end.addingTimeInterval(-dayStart - 1)))"
    }

    func dateText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private func isWorkday(_ day: DateInterval) -> Bool {
        // 区切りをずらした 1 日は、始まった日の暦の日付で判定する
        let date = day.start.addingTimeInterval(-dayStart)
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7 && !JapaneseHolidays.contains(date, calendar: calendar)
    }

    private func shifted(_ interval: DateInterval) -> DateInterval {
        DateInterval(start: interval.start.addingTimeInterval(dayStart), end: interval.end.addingTimeInterval(dayStart))
    }
}

// 日本の祝日 (振替休日・国民の休日を含む)。
// 年末年始のような会社の休みは含まない。2020・2021 年のオリンピックによる移動も扱わない
enum JapaneseHolidays {
    private static var cache: [Int: Set<DateComponents>] = [:]

    static func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year else { return false }
        return holidays(in: year).contains(components)
    }

    private static func holidays(in year: Int) -> Set<DateComponents> {
        if let cached = cache[year] { return cached }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

        func date(_ month: Int, _ day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        // month 月の n 回目の月曜日
        func monday(_ month: Int, _ n: Int) -> Date? {
            guard let first = date(month, 1) else { return nil }
            let toMonday = (9 - calendar.component(.weekday, from: first)) % 7
            return date(month, 1 + toMonday + (n - 1) * 7)
        }
        func adding(_ days: Int, to date: Date) -> Date? {
            calendar.date(byAdding: .day, value: days, to: date)
        }

        // 春分・秋分の日は 1980〜2099 年の近似式
        let elapsed = Double(year - 1980)
        let leap = (elapsed / 4).rounded(.down)
        let spring = Int(20.8431 + 0.242194 * elapsed - leap)
        let autumn = Int(23.2488 + 0.242194 * elapsed - leap)
        let base = Set([
            date(1, 1), monday(1, 2), date(2, 11), date(2, 23), date(3, spring), date(4, 29),
            date(5, 3), date(5, 4), date(5, 5), monday(7, 3), date(8, 11), monday(9, 3),
            date(9, autumn), monday(10, 2), date(11, 3), date(11, 23),
        ].compactMap { $0 })

        var result = base
        for holiday in base {
            // 国民の休日: 前後を祝日に挟まれた日
            if let next = adding(1, to: holiday), let afterNext = adding(2, to: holiday),
               !base.contains(next), base.contains(afterNext), calendar.component(.weekday, from: next) != 1 {
                result.insert(next)
            }
        }
        for holiday in base where calendar.component(.weekday, from: holiday) == 1 {
            // 振替休日: 日曜の祝日の後で、最初の祝日でない日
            var substitute = adding(1, to: holiday)
            while let day = substitute, result.contains(day) {
                substitute = adding(1, to: day)
            }
            if let substitute { result.insert(substitute) }
        }

        let components = Set(result.map { calendar.dateComponents([.year, .month, .day], from: $0) })
        cache[year] = components
        return components
    }
}
