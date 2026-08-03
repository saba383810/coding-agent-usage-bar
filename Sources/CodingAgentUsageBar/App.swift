import SwiftUI

@main
struct CodingAgentUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: UsageModel

    init() {
        _model = StateObject(wrappedValue: UsageModel(settings: UsageSettings()))
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを出さない (Info.plist の LSUIElement と二重の保険)
        NSApp.setActivationPolicy(.accessory)
        handleLoginItemArguments()
    }

    // ログイン項目の登録解除はアプリ自身しかできないため、
    // uninstall.sh から引数付きで起動して解除だけ行って終了する
    private func handleLoginItemArguments() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--register-login-item")
            || arguments.contains("--unregister-login-item")
        else { return }
        let enable = arguments.contains("--register-login-item")
        try? LoginItem.setEnabled(enable)
        print("login item: \(LoginItem.statusDescription)")
        NSApp.terminate(nil)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        let gauges = model.menuBarGauges
        // MenuBarExtra の label は Image 1 枚 + Text 1 個しか反映されないため、
        // ゲージが複数だったり識別子が付く場合は 1 枚の画像に合成する
        let single = gauges.count == 1 && !gauges[0].hasLabel
        return Group {
            if single {
                HStack(spacing: 3) {
                    Image(nsImage: GaugeStyle.menuBarImage(percent: gauges[0].percent))
                    Text(gauges[0].percent.map { "\(Int($0))%" } ?? "–")
                        .font(.system(size: 12).monospacedDigit())
                }
            } else {
                Image(nsImage: GaugeStyle.menuBarImage(gauges: gauges))
            }
        }
        .onAppear { model.start() }
    }
}
