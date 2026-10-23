import AppKit

/// 選單列圖示與選單。項目與順序見 contracts/commands.md。
final class StatusItemController: NSObject {
    struct Actions {
        var captureRegion: () -> Void = {}
        var captureWindow: () -> Void = {}
        var captureFullScreen: () -> Void = {}
        var openLibrary: () -> Void = {}
        var openSettings: () -> Void = {}
    }

    private let statusItem: NSStatusItem
    var actions: Actions

    init(actions: Actions = Actions()) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: String(localized: "SnagItForever"))
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "擷取區域"), #selector(captureRegion)))
        menu.addItem(item(String(localized: "擷取視窗"), #selector(captureWindow)))
        menu.addItem(item(String(localized: "擷取全螢幕"), #selector(captureFullScreen)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "開啟資料庫…"), #selector(openLibrary)))
        menu.addItem(item(String(localized: "偏好設定…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "結束"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func captureRegion() { actions.captureRegion() }
    @objc private func captureWindow() { actions.captureWindow() }
    @objc private func captureFullScreen() { actions.captureFullScreen() }
    @objc private func openLibrary() { actions.openLibrary() }
    @objc private func openSettings() { actions.openSettings() }
}
