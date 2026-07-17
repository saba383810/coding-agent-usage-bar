import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = UsageModel()

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
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        let percent = model.menuBarLimit?.percent
        HStack(spacing: 3) {
            Image(nsImage: GaugeStyle.menuBarImage(percent: percent))
            Text(percent.map { "\(Int($0))%" } ?? "–")
                .font(.system(size: 12).monospacedDigit())
        }
        .onAppear { model.start() }
    }
}
