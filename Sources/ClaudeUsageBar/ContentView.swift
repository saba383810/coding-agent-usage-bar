import SwiftUI

struct ContentView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Code Usage")
                    .font(.headline)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("今すぐ更新")
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if model.limits.isEmpty && model.errorMessage == nil {
                Text("読み込み中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.limits) { limit in
                LimitRow(limit: limit)
            }

            Divider()

            Picker("メニューバー表示", selection: $model.menuBarMetric) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)

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
        .frame(width: 300)
        .onAppear { model.refreshIfStale() }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit

    var body: some View {
        HStack(spacing: 12) {
            gauge
            VStack(alignment: .leading, spacing: 2) {
                Text(limit.title)
                    .font(.callout)
                if let resetsAt = limit.resetsAt {
                    Text(resetText(resetsAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
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
