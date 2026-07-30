import SwiftUI

struct ContentView: View {
    @ObservedObject var model: UsageModel

    private var settings: UsageSettings { model.settings }

    private var title: String {
        switch (settings.claudeEnabled, model.codexActive) {
        case (true, true): return "Claude / Codex Usage"
        case (false, true): return "Codex Usage"
        default: return "Claude Code Usage"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("今すぐ更新")
                Button {
                    SettingsWindowController.shared.show(model: model)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("設定")
            }

            if !settings.claudeEnabled && !model.codexActive {
                Text("設定で Claude か Codex を表示に切り替えてください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.claudeEnabled {
                ProviderSection(
                    provider: .claude,
                    limits: model.claudeLimits,
                    errorMessage: model.claudeError,
                    showLabel: model.codexActive,
                    showChargeNote: settings.showCreditCharge
                )
            }

            if model.codexActive {
                if settings.claudeEnabled { Divider() }
                ProviderSection(
                    provider: .codex,
                    limits: model.codexLimits,
                    errorMessage: model.codexError,
                    showLabel: settings.claudeEnabled,
                    showChargeNote: settings.showCreditCharge
                )
            }

            Divider()

            HStack {
                if let updated = model.lastUpdated {
                    Text("更新: \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("終了") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(14)
        .frame(width: model.codexActive ? 340 : 300)
        .onAppear { model.refreshIfStale() }
    }
}

private struct ProviderSection: View {
    let provider: UsageProvider
    let limits: [UsageLimit]
    let errorMessage: String?
    let showLabel: Bool
    let showChargeNote: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLabel {
                Text(provider.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if limits.isEmpty && errorMessage == nil {
                Text("読み込み中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(limits) { limit in
                LimitRow(limit: limit, showChargeNote: showChargeNote)
            }
        }
    }
}

// 請求段階の中でどこまで進んだかを示す横バー
private struct TierBar: View {
    let percent: Double

    private let width: CGFloat = 130
    private let height: CGFloat = 5

    var body: some View {
        let progress = min(max(percent, 0), 100) / 100
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: width, height: height)
            if progress > 0 {
                Capsule()
                    .fill(Color(nsColor: GaugeStyle.color(forPercent: percent)))
                    .frame(width: max(width * progress, height), height: height)
            }
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit
    let showChargeNote: Bool

    var body: some View {
        HStack(spacing: 12) {
            gauge
            VStack(alignment: .leading, spacing: 2) {
                // Codex のモデル別制限は名前が長いので、収まらない時だけ少し縮める
                Text(limit.title)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ForEach(limit.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showChargeNote, let tier = limit.creditTier {
                    tierRow(tier)
                }
                if let resetsAt = limit.resetsAt {
                    Text(resetText(resetsAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 請求段階と、その段階内でどこまで進んだかのバー
    private func tierRow(_ tier: CreditTier) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tier.summary)
                .font(.caption)
                .foregroundStyle(tierColor(tier.percent))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TierBar(percent: tier.percent)
                Text(tierPercentText(tier.percent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let remaining = tier.remainingText {
                Text(remaining)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    // 次の段階が近い / 超えた場合は色で気づけるようにする
    private func tierColor(_ percent: Double) -> Color {
        if percent >= 100 { return .red }
        if percent >= 90 { return .orange }
        return .secondary
    }

    private func tierPercentText(_ percent: Double) -> String {
        percent < 10 ? String(format: "%.1f%%", percent) : "\(Int(percent))%"
    }

    private var gauge: some View {
        let percent = limit.percent
        let progress = min(max(percent ?? 0, 0), 100) / 100
        let color = Color(nsColor: GaugeStyle.color(forPercent: percent))
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percent.map { "\(Int($0))%" } ?? "–")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
        .frame(width: 40, height: 40)
    }

    private func resetText(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        let absolute: String
        if Calendar.current.isDateInToday(date) {
            absolute = date.formatted(date: .omitted, time: .shortened)
        } else {
            absolute = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        guard remaining > 0 else { return "リセット: \(absolute)" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let relative = hours > 0 ? "あと\(hours)時間\(minutes)分" : "あと\(minutes)分"
        return "リセット: \(absolute) (\(relative))"
    }
}
