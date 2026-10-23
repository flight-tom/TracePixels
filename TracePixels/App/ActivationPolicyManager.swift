import AppKit

/// 管理 Dock 圖示：平常只有選單列圖示（`.accessory`），
/// 有編輯器、資料庫或偏好設定視窗開啟時才顯示 Dock 圖示（`.regular`）。
final class ActivationPolicyManager {
    private var trackedWindows = Set<ObjectIdentifier>()
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// 登記一個視窗；它關閉時自動取消登記。
    func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard closeObservers[id] == nil else { return }
        trackedWindows.insert(id)
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.untrack(id)
        }
        update()
    }

    private func untrack(_ id: ObjectIdentifier) {
        trackedWindows.remove(id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        update()
    }

    var hasVisibleWindows: Bool { !trackedWindows.isEmpty }

    private func update() {
        let desired: NSApplication.ActivationPolicy = trackedWindows.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != desired else { return }
        NSApp.setActivationPolicy(desired)
        if desired == .regular { NSApp.activate(ignoringOtherApps: true) }
    }
}
