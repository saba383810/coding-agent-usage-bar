import AppKit
import SwiftUI

// 設定ウィンドウのタブ。ツールバーに並べて切り替える
enum SettingsTab: CaseIterable {
    case claude
    case codex
    case general

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .general: return "全体"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: return UsageProvider.claude.symbolName
        case .codex: return UsageProvider.codex.symbolName
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    let tab: SettingsTab
    @ObservedObject var settings: UsageSettings
    @ObservedObject var model: UsageModel

    var body: some View {
        Form {
            switch tab {
            case .claude: claude
            case .codex: codex
            case .general: general
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        // 高さは中身に合わせ、画面に収まらない分はスクロールで見せる
        .frame(maxHeight: Self.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    // タイトルバーとツールバーの分を残す
    private static var maxHeight: CGFloat {
        min((NSScreen.main?.visibleFrame.height ?? 800) - 140, 760)
    }

    // MARK: - Claude

    @ViewBuilder private var claude: some View {
        Section {
            Toggle("使用量を表示する", isOn: $settings.claudeEnabled)
        } footer: {
            Footnote("オフにすると Claude の使用量を取得しません。")
        }

        Group {
            menuBarSection(isOn: $settings.claudeInMenuBar) {
                Picker("表示する指標", selection: $settings.claudeMetric) {
                    ForEach(ClaudeMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
            }

            PaceSection(pace: $settings.claudePace)

            Section {
                Toggle("月の上限を上書きする", isOn: claudeOverridesLimit)
                if settings.claudeOverridesLimit {
                    LabeledContent("上限 (USD)") {
                        TextField(
                            "上限 (USD)",
                            value: $settings.claudeLimitOverride,
                            format: .number,
                            prompt: Text(claudeAPILimit ?? "金額")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                    }
                }
            } header: {
                Text("月の上限")
            } footer: {
                Footnote(claudeLimitFootnote)
            }
        }
        .disabled(!settings.claudeEnabled)
    }

    private var claudeAPILimit: String? {
        model.claudeSpend?.limit?.formatted
    }

    private var claudeLimitFootnote: String {
        let apiLimit = claudeAPILimit.map { " (\($0))" } ?? ""
        guard settings.claudeOverridesLimit else {
            return "API が返す上限\(apiLimit)で Credits の % と目安を計算します。"
        }
        guard (settings.claudeLimitOverride ?? 0) > 0 else {
            return "額が空のあいだは、API が返す上限\(apiLimit)を使います。"
        }
        return "Credits の % と目安を、この額で計算します。API の上限\(apiLimit)は使いません。"
    }

    // 初めて上書きする時は、API の上限から書き換えられるようにしておく
    private var claudeOverridesLimit: Binding<Bool> {
        Binding(
            get: { settings.claudeOverridesLimit },
            set: { isOn in
                if isOn, settings.claudeLimitOverride == nil {
                    settings.claudeLimitOverride = model.claudeSpend?.limit?.amount
                }
                settings.claudeOverridesLimit = isOn
            }
        )
    }

    // MARK: - Codex

    @ViewBuilder private var codex: some View {
        Section {
            Toggle("使用量を表示する", isOn: $settings.codexEnabled)
                .disabled(!model.codexAvailable)
        } footer: {
            Footnote(
                model.codexAvailable
                    ? "オフにすると Codex の使用量を取得しません。"
                    : "~/.codex/auth.json が見つからないため表示できません。Codex CLI でログインすると使えます。"
            )
        }

        Group {
            menuBarSection(isOn: $settings.codexInMenuBar) {
                Picker("表示する指標", selection: $settings.codexMetric) {
                    ForEach(CodexMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
            }

            PaceSection(pace: $settings.codexPace)

            Section {
                Toggle("請求段階を表示する", isOn: $settings.showCreditCharge)
            } header: {
                Text("クレジット")
            } footer: {
                Footnote("""
                    請求段階は 0 なら請求なし、上限の 1/20 までで 40 ドル、上限までで 200 ドル、\
                    超過すると翌月まで利用不可 (上限緩和申請で継続可)。\
                    境界は API が返す上限に対する比率で判定するため、3 倍キャンペーン中も追従します。
                    """)
            }
        }
        .disabled(!model.codexActive)
    }

    // MARK: - 全体

    @ViewBuilder private var general: some View {
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

        Section {
            Picker("Claude と Codex の見分け方", selection: $settings.useMenuBarIcons) {
                Text("文字").tag(false)
                Text("アイコン").tag(true)
            }
            LabeledContent("表示") {
                HStack(spacing: 12) {
                    if settings.useMenuBarIcons {
                        Label("Claude", systemImage: UsageProvider.claude.symbolName)
                        Label("Codex", systemImage: UsageProvider.codex.symbolName)
                    } else {
                        Text("Cl = Claude")
                        Text("Cx = Codex")
                    }
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("メニューバーの見た目")
        } footer: {
            Footnote(
                settings.useMenuBarIcons
                    ? "アイコンは、片方だけをメニューバーに出す時も付きます。"
                    : "文字は、両方をメニューバーに出す時だけ付きます。"
            )
        }

        Section {
            DatePicker("1 日の区切り", selection: dayStart, displayedComponents: .hourAndMinute)
        } header: {
            Text("目安の 1 日")
        } footer: {
            Footnote(dayStartFootnote)
        }
    }

    private var dayStartFootnote: String {
        let minutes = settings.dayStartMinutes
        guard minutes > 0 else {
            return "Today は 0:00、Week は月曜 0:00 に切り替わります。Claude と Codex で共通です。"
        }
        let time = String(format: "%d:%02d", minutes / 60, minutes % 60)
        return "Today は \(time)、Week は月曜 \(time) に切り替わり、0:00〜\(time) の使用は前日の分になります。Claude と Codex で共通です。"
    }

    // 1 日の区切りは 0 時からの分で持つので、DatePicker 用に今日のその時刻に直す
    private var dayStart: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.dayStartMinutes / 60,
                    minute: settings.dayStartMinutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.dayStartMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    // MARK: - 共通

    // メニューバーに出す時だけ、出す指標を選ばせる
    private func menuBarSection<Metric: View>(isOn: Binding<Bool>, @ViewBuilder metric: () -> Metric) -> some View {
        Section("メニューバー") {
            Toggle("メニューバーに出す", isOn: isOn)
            if isOn.wrappedValue {
                metric()
            }
        }
    }
}

// 日・週の目安の設定。Claude と Codex で同じ並びにする
private struct PaceSection: View {
    @Binding var pace: PaceSettings

    var body: some View {
        Section {
            Toggle("Today / Week (目安) を表示する", isOn: $pace.shows)
            if pace.shows {
                Picker("Today の数え方", selection: $pace.daily) {
                    ForEach(PaceUsageMode.allCases) { mode in
                        Text(mode.title(week: false)).tag(mode)
                    }
                }
                Picker("Week の数え方", selection: $pace.weekly) {
                    ForEach(PaceUsageMode.allCases) { mode in
                        Text(mode.title(week: true)).tag(mode)
                    }
                }
                Toggle("土日祝を除いて日割りする", isOn: $pace.excludesHolidays)
            }
        } header: {
            Text("日・週の目安")
        } footer: {
            Footnote(footnote)
        }
    }

    private var footnote: String {
        guard pace.shows else {
            return "月の上限を日割りした目安を、Today / Week として出します。"
        }
        var lines = [
            "Today: \(pace.daily.explanation(week: false))",
            "Week: \(pace.weekly.explanation(week: true))",
        ]
        if pace.excludesHolidays {
            lines.append("目安は平日だけに割り振り、休日の Today は「目安なし」になります。年末年始などの会社の休みは含みません。")
        }
        return lines.joined(separator: "\n")
    }
}

private extension PaceUsageMode {
    func title(week: Bool) -> String {
        let span = week ? "今週" : "今日"
        switch self {
        case .cumulative: return "今日までの累計"
        case .period: return "\(span)使った分"
        case .remaining: return "\(span)使った分 (残りを日割り)"
        }
    }

    func explanation(week: Bool) -> String {
        let span = week ? "今週" : "今日"
        switch self {
        case .cumulative:
            return "月の初めからの累計を、\(span)の終わりまでの目安の累計と比べます。使いすぎた分は持ち越します。"
        case .period:
            return "\(span)使った分を、\(week ? "1 週" : "1 日")分の目安と比べます。"
        case .remaining:
            return "\(span)使った分を、\(span)の初めに残っていた額を月末までの日数で割り直した目安と比べます。"
        }
    }
}

private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// LSUIElement なアプリなので Settings シーンを使わず、自前のウィンドウで出す。
// タブは環境設定と同じく、ツールバーに並べる
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(model: UsageModel) {
        if window == nil {
            let tabs = SettingsTabViewController()
            tabs.tabStyle = .toolbar
            for tab in SettingsTab.allCases {
                let controller = NSHostingController(
                    rootView: SettingsView(tab: tab, settings: model.settings, model: model)
                )
                // ウィンドウの大きさは SettingsTabViewController がタブの中身に合わせる
                controller.sizingOptions = [.preferredContentSize]
                controller.title = tab.title
                let item = NSTabViewItem(viewController: controller)
                item.label = tab.title
                item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// タブを切り替えた時や、項目を開いて中身の高さが変わった時に、ウィンドウを中身に合わせる。
// 上端は動かさない
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        fitWindow()
    }

    private func fitWindow() {
        guard
            let window = view.window,
            let size = tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize,
            size.width > 0, size.height > 0
        else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        // 伸ばした分で画面の下にはみ出すなら、上へずらす
        if let visible = window.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = min(visible.minY, visible.maxY - frame.height)
        }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
