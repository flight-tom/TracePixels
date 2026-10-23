import AppKit

/// 建立主選單。有編輯器視窗開啟時（Dock 圖示出現）才看得到；
/// 動作沿 responder chain 送到目前的編輯器視窗。所有工具與動作都有選單項目（FR-028）。
@MainActor
enum MainMenuBuilder {
    static func build(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(appMenu(settingsTarget: settingsTarget, settingsAction: settingsAction)))
        main.addItem(submenuItem(fileMenu()))
        main.addItem(submenuItem(editMenu()))
        main.addItem(submenuItem(toolsMenu()))
        main.addItem(submenuItem(viewMenu()))
        main.addItem(submenuItem(windowMenu()))
        return main
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String, _ action: Selector?, _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }

    private static func appMenu(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "SnagItForever")
        menu.addItem(item(String(localized: "偏好設定…"), settingsAction, ",", target: settingsTarget))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "隱藏 SnagItForever"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(String(localized: "隱藏其他"), #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "結束 SnagItForever"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "檔案"))
        menu.addItem(item(String(localized: "關閉視窗"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "編輯"))
        menu.addItem(item(String(localized: "復原"), Selector(("undo:")), "z"))
        menu.addItem(item(String(localized: "重做"), Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "刪除所選標註"), Selector(("deleteSelection:"))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "移到最上層"), Selector(("bringToFront:")), "]", modifiers: [.command, .option]))
        menu.addItem(item(String(localized: "上移一層"), Selector(("bringForward:")), "]"))
        menu.addItem(item(String(localized: "下移一層"), Selector(("sendBackward:")), "["))
        menu.addItem(item(String(localized: "移到最下層"), Selector(("sendToBack:")), "[", modifiers: [.command, .option]))
        return menu
    }

    private static func toolsMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "工具"))
        for tool in EditorTool.allCases {
            // 單鍵工具快速鍵在畫布處理（避免在文字輸入時被選單攔截），選單項目顯示對應的鍵。
            let entry = item("\(tool.title)  (\(tool.key.uppercased()))", Selector(("selectTool:")))
            entry.representedObject = tool.rawValue
            menu.addItem(entry)
        }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "檢視"))
        menu.addItem(item(String(localized: "放大"), Selector(("zoomIn:")), "+"))
        menu.addItem(item(String(localized: "縮小"), Selector(("zoomOut:")), "-"))
        menu.addItem(item(String(localized: "符合視窗"), Selector(("zoomToFit:")), "0"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "視窗"))
        menu.addItem(item(String(localized: "最小化"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        NSApp.windowsMenu = menu
        return menu
    }
}
