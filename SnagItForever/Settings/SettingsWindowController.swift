import AppKit
import SnagItCore
import SwiftUI

/// 偏好設定視窗。各分頁見 `*SettingsView`。
final class SettingsWindowController: NSWindowController {
    init(environment: AppEnvironment, hotKeyController: HotKeyController) {
        let root = SettingsRootView(preferences: environment.preferences, hotKeyController: hotKeyController, library: environment.library)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "偏好設定")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    /// 偏好設定視窗不觸發 Dock 圖示（FR-029：只有編輯器與資料庫視窗才會）。
    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsRootView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var hotKeyController: HotKeyController
    let library: LibraryStore

    var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label("一般", systemImage: "gearshape") }
            CaptureSettingsView(preferences: preferences, hotKeyController: hotKeyController)
                .tabItem { Label("擷取", systemImage: "camera.viewfinder") }
            ExportSettingsView(preferences: preferences)
                .tabItem { Label("輸出", systemImage: "square.and.arrow.up") }
            LibrarySettingsView(library: library)
                .tabItem { Label("資料庫", systemImage: "photo.on.rectangle") }
        }
        .frame(width: 520)
        .padding(20)
    }
}
