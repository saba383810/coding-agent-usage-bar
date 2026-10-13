import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: UsageSettings
    @ObservedObject var model: UsageModel

    var body: some View {
        Form {
            Section("Claude") {
                Toggle("使用量を表示する", isOn: $settings.claudeEnabled)
                Toggle("メニューバーに出す", isOn: $settings.claudeInMenuBar)
                    .disabled(!settings.claudeEnabled)
                Picker("メニューバーの指標", selection: $settings.claudeMetric) {
                    ForEach(ClaudeMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .disabled(!settings.claudeEnabled || !settings.claudeInMenuBar)
                Toggle("日・週の目安を表示", isOn: $settings.claudeShowsPace)
                    .disabled(!settings.claudeEnabled)
                LabeledContent("月の上限 (USD・上書き)") {
                    TextField(
                        "月の上限 (USD・上書き)",
                        value: $settings.claudeLimitOverride,
                        format: .number,
                        prompt: Text(model.claudeSpend?.limit?.formatted ?? "API の値")
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                }
                .disabled(!settings.claudeEnabled)
                Text("クレジット制のプランでは、月の上限を日割りした目安を Today / Week として出します。上限を空欄にすると API の値を使います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Codex") {
                Toggle("使用量を表示する", isOn: $settings.codexEnabled)
                    .disabled(!model.codexAvailable)
                if !model.codexAvailable {
                    Text("~/.codex/auth.json が見つからないため表示できません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("メニューバーに出す", isOn: $settings.codexInMenuBar)
                    .disabled(!model.codexActive)
                Picker("メニューバーの指標", selection: $settings.codexMetric) {
                    ForEach(CodexMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .disabled(!model.codexActive || !settings.codexInMenuBar)
                Toggle("クレジットの請求段階を表示", isOn: $settings.showCreditCharge)
                    .disabled(!model.codexActive)
                Text("""
                    請求段階は 0 なら請求なし、上限の 1/20 までで 40 ドル、上限までで 200 ドル、\
                    超過すると翌月まで利用不可 (上限緩和申請で継続可)。
                    境界は API が返す上限に対する比率で判定するため、3 倍キャンペーン中も追従します。
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("目安の数え方") {
                Picker("Today", selection: $settings.dailyPaceMode) {
                    Text("今日までの累計").tag(PaceUsageMode.cumulative)
                    Text("今日使った分").tag(PaceUsageMode.period)
                }
                Picker("Week", selection: $settings.weeklyPaceMode) {
                    Text("今日までの累計").tag(PaceUsageMode.cumulative)
                    Text("今週使った分").tag(PaceUsageMode.period)
                }
                Text("""
                    累計: 月の初めからの使用量を、今日 (今週) の終わりまでの目安の累計と比べます。\
                    使いすぎた分は持ち越すので、朝の時点で 100% を超えることもあります。
                    使った分: 今日 (今週) に使った分だけを、1 日 (1 週) 分の目安と比べます。\
                    API は月の累計しか返さないので、日ごとに最初に取れた累計との差で数えます。\
                    アプリが動いていなかった間の使用は数えられません。
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.claudeShowsPace)

            Section("起動") {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let message = model.loginItemMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("メニューバーの見た目") {
                Toggle("アイコンで表示する", isOn: $settings.useMenuBarIcons)
                HStack(spacing: 12) {
                    if settings.useMenuBarIcons {
                        Label("Claude", systemImage: UsageProvider.claude.symbolName)
                        Label("Codex", systemImage: UsageProvider.codex.symbolName)
                    } else {
                        Text("Cl = Claude")
                        Text("Cx = Codex")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("文字の場合は、両方をメニューバーに出す時だけ付きます。アイコンの場合は片方だけでも付きます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// LSUIElement なアプリなので Settings シーンを使わず、自前のウィンドウで出す
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(model: UsageModel) {
        if window == nil {
            let controller = NSHostingController(
                rootView: SettingsView(settings: model.settings, model: model)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Coding Agent Usage Bar の設定"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
