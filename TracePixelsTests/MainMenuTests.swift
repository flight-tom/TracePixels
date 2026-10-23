import AppKit
import XCTest
@testable import TracePixels

/// FR-028：所有工具與動作都有選單項目；快速鍵不可重複。
@MainActor
final class MainMenuTests: XCTestCase {
    private final class Target: NSObject, AppMenuActions {
        func openSettings(_ sender: Any?) {}
        func openLibrary(_ sender: Any?) {}
        func captureRegion(_ sender: Any?) {}
        func captureWindow(_ sender: Any?) {}
        func captureFullScreen(_ sender: Any?) {}
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
    }

    private var items: [NSMenuItem] { allItems(MainMenuBuilder.build(appTarget: Target())) }
    private var titles: Set<String> { Set(items.map(\.title)) }

    func testEveryActionInThePlanHasAMenuItem() {
        let required = [
            "擷取區域", "擷取視窗", "擷取全螢幕", "開啟資料庫…", "偏好設定…",
            "另存新檔…", "分享…", "復原", "重做", "複製影像", "刪除所選標註", "清除裁切",
            "移到最上層", "上移一層", "下移一層", "移到最下層",
            "放大", "縮小", "符合視窗", "調整輸出大小…",
        ]
        for title in required {
            XCTAssertTrue(titles.contains(title), "主選單缺少「\(title)」")
        }
    }

    func testEveryToolHasAMenuItemShowingItsKey() {
        for tool in EditorTool.allCases {
            XCTAssertTrue(
                items.contains { $0.title == "\(tool.title)  (\(tool.key.uppercased()))" && $0.representedObject as? String == tool.rawValue },
                "工具選單缺少 \(tool.title)")
        }
    }

    func testKeyEquivalentsAreUnique() {
        var seen: [String: String] = [:]
        for item in items where !item.keyEquivalent.isEmpty {
            let id = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent)"
            if let other = seen[id] { XCTFail("快速鍵重複：「\(other)」與「\(item.title)」") }
            seen[id] = item.title
        }
    }

    func testEveryItemWithATitleHasAnActionOrIsASubmenu() {
        for item in items where !item.isSeparatorItem && item.submenu == nil {
            XCTAssertNotNil(item.action, "「\(item.title)」沒有動作")
        }
    }

    func testCaptureItemsDoNotCollideWithEditorShortcuts() {
        let capture = items.filter { ["擷取區域", "擷取視窗", "擷取全螢幕"].contains($0.title) }
        XCTAssertEqual(capture.count, 3)
        for item in capture {
            XCTAssertTrue(item.keyEquivalentModifierMask.isSuperset(of: [.control, .option, .command]), "\(item.title) 使用三個修飾鍵，避免與系統及編輯器衝突")
        }
    }
}
