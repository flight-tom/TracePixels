import AppKit
import SwiftUI

/// 偏好設定視窗。各分頁見 `*SettingsView`。
final class SettingsWindowController: NSWindowController {
    private let environment: AppEnvironment

    init(environment: AppEnvironment, hotKeyController: HotKeyController) {
        self.environment = environment
        let root = SettingsRootView(preferences: environment.preferences, hotKeyController: hotKeyController)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "偏好設定")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    func show() {
        if let window { environment.activationPolicy.track(window) }
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsRootView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var hotKeyController: HotKeyController

    var body: some View {
        TabView {
            CaptureSettingsView(preferences: preferences, hotKeyController: hotKeyController)
                .tabItem { Label("擷取", systemImage: "camera.viewfinder") }
        }
        .frame(width: 520)
        .padding(20)
    }
}
