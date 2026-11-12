import Foundation

// プラン名で決め打ちせず、実際に取得できた利用枠から表示と選択肢を決める。
struct CodexDisplay {
    let limits: [UsageLimit]

    var availableMetrics: [CodexMetric] {
        CodexMetric.allCases.filter { metric in
            metric == .automatic || selectedPercent(for: metric) != nil
        }
    }

    var supportsCreditTier: Bool {
        limits.contains { $0.creditTier != nil }
    }

    // 以前のプランや、目安を表示しない設定で使えなくなった指標は自動表示に戻す。
    // 保存した設定は残し、その指標が再び取得できた時は元の表示に戻せるようにする。
    func effectiveMetric(_ metric: CodexMetric) -> CodexMetric {
        availableMetrics.contains(metric) ? metric : .automatic
    }

    func percent(for metric: CodexMetric) -> Double? {
        selectedPercent(for: metric) ?? automaticLimit?.percent
    }

    var automaticLimit: UsageLimit? {
        // 支出上限がある場合はその消費率。それ以外は最も消費している利用枠。
        credits ?? highest(in: limits)
    }

    private var credits: UsageLimit? {
        limits.first { $0.group == "credits" && $0.percent != nil }
    }

    private func selectedPercent(for metric: CodexMetric) -> Double? {
        switch metric {
        case .automatic: return automaticLimit?.percent
        case .session: return highest(in: limits.filter { $0.group == "session" })?.percent
        case .weekly: return highest(in: limits.filter { $0.group == "weekly" })?.percent
        case .dailyPace: return limits.first { $0.kind == "pace_daily" }?.percent
        case .weeklyPace: return limits.first { $0.kind == "pace_weekly" }?.percent
        case .credits: return credits?.percent
        case .creditTier: return limits.compactMap { $0.creditTier?.percent }.first
        case .max: return highest(in: limits)?.percent
        }
    }

    private func highest(in limits: [UsageLimit]) -> UsageLimit? {
        limits.filter { $0.percent != nil }.max { ($0.percent ?? -1) < ($1.percent ?? -1) }
    }
}
