import AppKit

/// 主選單的 App 層動作。以協定宣告，選單項目才能用有編譯期檢查的 `#selector`。
@objc protocol AppMenuActions {
    func openSettings(_ sender: Any?)
    func openLibrary(_ sender: Any?)
    func captureRegion(_ sender: Any?)
    func captureWindow(_ sender: Any?)
    func captureFullScreen(_ sender: Any?)
}

/// 建立主選單。有編輯器視窗開啟時（Dock 圖示出現）才看得到；
/// 動作沿 responder chain 送到目前的編輯器視窗。所有工具與動作都有選單項目（FR-028）。
@MainActor
enum MainMenuBuilder {
    /// `appTarget` 負責 App 層動作：擷取三種模式、開啟資料庫、偏好設定。
    static func build(appTarget: AppMenuActions) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(appMenu(appTarget: appTarget)))
        main.addItem(submenuItem(fileMenu(appTarget: appTarget)))
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

    private static func appMenu(appTarget: AppMenuActions) -> NSMenu {
        let menu = NSMenu(title: "TracePixels")
        menu.addItem(item(String(localized: "偏好設定…"), #selector(AppMenuActions.openSettings(_:)), ",", target: appTarget))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "隱藏 TracePixels"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(String(localized: "隱藏其他"), #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "結束 TracePixels"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(appTarget: AppMenuActions) -> NSMenu {
        let menu = NSMenu(title: String(localized: "檔案"))
        // 與選單列圖示相同的擷取動作。全域快速鍵可在偏好設定變更；這裡的固定組合只在 App 啟用時有效。
        let capture: NSEvent.ModifierFlags = [.control, .option, .command]
        menu.addItem(item(String(localized: "擷取區域"), #selector(AppMenuActions.captureRegion(_:)), "r", modifiers: capture, target: appTarget))
        menu.addItem(item(String(localized: "擷取視窗"), #selector(AppMenuActions.captureWindow(_:)), "w", modifiers: capture, target: appTarget))
        menu.addItem(item(String(localized: "擷取全螢幕"), #selector(AppMenuActions.captureFullScreen(_:)), "f", modifiers: capture, target: appTarget))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "開啟資料庫…"), #selector(AppMenuActions.openLibrary(_:)), "l", modifiers: [.command, .shift], target: appTarget))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "另存新檔…"), Selector(("saveAs:")), "s", modifiers: [.command, .shift]))
        menu.addItem(item(String(localized: "分享…"), Selector(("shareImage:"))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "關閉視窗"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "編輯"))
        menu.addItem(item(String(localized: "復原"), Selector(("undo:")), "z"))
        menu.addItem(item(String(localized: "重做"), Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "複製影像"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(String(localized: "刪除所選標註"), Selector(("deleteSelection:"))))
        menu.addItem(item(String(localized: "清除裁切"), Selector(("clearCrop:"))))
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
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "調整輸出大小…"), Selector(("resizeOutput:")), "i", modifiers: [.command, .option]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "視窗"))
        menu.addItem(item(String(localized: "最小化"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        NSApp.windowsMenu = menu
        return menu
    }
}
