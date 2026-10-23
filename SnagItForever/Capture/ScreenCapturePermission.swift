import AppKit
import SwiftUI

/// 螢幕擷取權限（macOS「螢幕與系統音訊錄製」）。
enum ScreenCapturePermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 觸發系統的授權提示；首次呼叫時系統會彈出對話框。
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

/// 缺少權限時的說明視窗（FR-005）：說明缺少什麼，並提供前往系統設定的按鈕，而不是產出空白影像。
final class PermissionGuideWindowController: NSWindowController {
    private var environment: AppEnvironment?

    convenience init(environment: AppEnvironment) {
        let hosting = NSHostingController(rootView: PermissionGuideView(onClose: {}))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "需要螢幕擷取權限")
        window.styleMask = [.titled, .closable]
        self.init(window: window)
        hosting.rootView = PermissionGuideView(onClose: { [weak window] in window?.close() })
        self.environment = environment
    }

    func show() {
        if let window { environment?.activationPolicy.track(window) }
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PermissionGuideView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SnagItForever 需要「螢幕與系統音訊錄製」權限才能擷取畫面。")
                .font(.headline)
            Text("請到「系統設定 › 隱私權與安全性 › 螢幕與系統音訊錄製」開啟 SnagItForever，然後重新啟動應用程式並再擷取一次。")
                .fixedSize(horizontal: false, vertical: true)
            Text("在授權之前，應用程式不會產生任何擷取影像。")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("稍後", action: onClose)
                Button("開啟系統設定") {
                    ScreenCapturePermission.openSystemSettings()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
