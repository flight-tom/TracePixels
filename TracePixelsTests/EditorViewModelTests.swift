import XCTest
import TracePixelsCore
@testable import TracePixels

/// `EditorViewModel` 的狀態邏輯（不需要螢幕）：文字結束編輯、工具預設樣式、套用樣式、
/// 選取、微調、順序、復原與匯出尺寸。對應憲章原則 IV。
@MainActor
final class EditorViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var preferences: Preferences!

    override func setUp() {
        suite = "TracePixelsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        preferences = Preferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeImage(width: Int = 400, height: Int = 300) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func makeViewModel() -> EditorViewModel {
        let capture = Capture(
            createdAt: Date(timeIntervalSince1970: 0), source: .region,
            pixelSize: PixelSize(width: 400, height: 300), scale: 2)
        return EditorViewModel(capture: capture, original: makeImage(), preferences: preferences)
    }

    private func rect(_ x: Double = 10, _ y: Double = 10) -> Annotation.Kind {
        .rectangle(rect: PixelRect(x: x, y: y, width: 50, height: 30), filled: false)
    }

    private func texts(_ vm: EditorViewModel) -> [String] {
        vm.capture.annotations.compactMap { if case let .text(_, s) = $0.kind { s } else { nil } }
    }

    /// 與 ToolController 建立文字相同的流程：手勢內加入空白文字，然後開始編輯。
    private func beginNewText(_ vm: EditorViewModel, height: Double = 30) -> Annotation.ID {
        vm.beginGesture()
        let id = vm.add(.text(rect: PixelRect(x: 20, y: 20, width: 200, height: height), string: ""))
        vm.startTextEditing(id, isNew: true)
        return id
    }

    // MARK: 文字結束編輯

    func testNewTextCommitKeepsTheStringAsASingleUndoStep() {
        let vm = makeViewModel()
        _ = beginNewText(vm)
        vm.finishTextEditing(string: "你好", fittedHeight: 20)
        XCTAssertEqual(texts(vm), ["你好"])
        XCTAssertNil(vm.editingTextID)

        vm.undo()  // 建立與輸入是同一次手勢，一次復原就全部消失
        XCTAssertTrue(vm.capture.annotations.isEmpty)
        XCTAssertFalse(vm.canUndo)
    }

    func testNewTextLeftEmptyLeavesNoTraceInHistory() {
        let vm = makeViewModel()
        _ = beginNewText(vm)
        vm.finishTextEditing(string: "  \n ", fittedHeight: 20)
        XCTAssertTrue(vm.capture.annotations.isEmpty)
        XCTAssertFalse(vm.canUndo, "空白文字取消後不該留下可復原的步驟")
        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testClearingExistingTextDeletesItAndUndoRestoresTheOldText() {
        let vm = makeViewModel()
        let id = vm.add(.text(rect: PixelRect(x: 5, y: 5, width: 100, height: 30), string: "abc"))
        vm.startTextEditing(id, isNew: false)
        vm.finishTextEditing(string: "", fittedHeight: 10)
        XCTAssertTrue(vm.capture.annotations.isEmpty)

        vm.undo()
        XCTAssertEqual(texts(vm), ["abc"])
    }

    func testEditingExistingTextIsOneUndoStep() {
        let vm = makeViewModel()
        let id = vm.add(.text(rect: PixelRect(x: 5, y: 5, width: 100, height: 30), string: "old"))
        vm.startTextEditing(id, isNew: false)
        vm.finishTextEditing(string: "new", fittedHeight: 10)
        XCTAssertEqual(texts(vm), ["new"])
        vm.undo()
        XCTAssertEqual(texts(vm), ["old"])
    }

    func testTextBoxGrowsToFitContentButNeverShrinks() {
        let vm = makeViewModel()
        _ = beginNewText(vm, height: 30)
        vm.finishTextEditing(string: "很長的文字", fittedHeight: 90)
        guard case let .text(grown, _) = vm.capture.annotations[0].kind else { return XCTFail("應該是文字") }
        XCTAssertEqual(grown.height, 90)

        let id = vm.capture.annotations[0].id
        vm.startTextEditing(id, isNew: false)
        vm.finishTextEditing(string: "短", fittedHeight: 10)
        guard case let .text(kept, _) = vm.capture.annotations[0].kind else { return XCTFail("應該是文字") }
        XCTAssertEqual(kept.height, 90, "較矮的內容不會把框縮小")
    }

    func testUndoAndRedoAreBlockedWhileEditingText() {
        let vm = makeViewModel()
        vm.add(rect())
        _ = beginNewText(vm)
        vm.undo()
        XCTAssertEqual(vm.capture.annotations.count, 2, "編輯文字期間，復原由文字框自己處理")
    }

    // MARK: 工具與樣式

    func testSettingAToolLoadsItsRememberedStyleOrFactoryDefault() {
        preferences.defaultStyles["arrow"] = Style(color: .black, lineWidth: 9)
        let vm = makeViewModel()

        vm.setTool(.arrow)
        XCTAssertEqual(vm.style.lineWidth, 9)
        XCTAssertEqual(vm.style.color, .black)

        vm.setTool(.highlighter)
        XCTAssertEqual(vm.style.color, .yellow)
        XCTAssertEqual(vm.style.lineWidth, 8)

        vm.setTool(.rectangle)
        XCTAssertEqual(vm.style, Style())
    }

    func testApplyStyleUpdatesTheSelectionAndRemembersItForTheTool() {
        let vm = makeViewModel()
        vm.setTool(.rectangle)
        let id = vm.add(rect())
        vm.selection = [id]

        vm.applyStyle { $0.color = .black; $0.lineWidth = 12 }

        XCTAssertEqual(vm.capture.annotations[0].style.color, .black)
        XCTAssertEqual(vm.capture.annotations[0].style.lineWidth, 12)
        XCTAssertEqual(vm.style.lineWidth, 12)
        XCTAssertEqual(preferences.defaultStyles["rectangle"]?.lineWidth, 12)
    }

    func testApplyStyleWithNothingSelectedOnlyChangesTheNextAnnotation() {
        let vm = makeViewModel()
        let id = vm.add(rect())
        vm.setTool(.ellipse)
        vm.applyStyle { $0.color = .black }
        XCTAssertEqual(vm.capture.annotations.first { $0.id == id }?.style.color, .red, "既有標註不受影響")
        XCTAssertEqual(vm.add(.ellipse(rect: PixelRect(x: 0, y: 0, width: 10, height: 10), filled: false)) == id, false)
        XCTAssertEqual(vm.capture.annotations.last?.style.color, .black)
    }

    func testSelectToolKeepsSelectionButOtherToolsClearIt() {
        let vm = makeViewModel()
        let id = vm.add(rect())
        vm.selection = [id]
        vm.setTool(.select)
        XCTAssertEqual(vm.selection, [id])
        vm.setTool(.pen)
        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testInspectorStyleShowsTheSelectionElseTheNextStyle() {
        let vm = makeViewModel()
        let id = vm.add(rect())
        vm.applyStyle { _ in }   // 不改任何東西
        vm.selection = [id]
        vm.mutate { $0.update(id) { $0.style.lineWidth = 20 } }
        XCTAssertEqual(vm.inspectorStyle.lineWidth, 20)
        vm.selection = []
        XCTAssertNotEqual(vm.inspectorStyle.lineWidth, 20)
    }

    // MARK: 選取、微調、順序

    func testNudgeMovesTheSelectionAndEachNudgeIsOneUndoStep() {
        let vm = makeViewModel()
        let id = vm.add(rect(10, 10))
        vm.selection = [id]
        vm.nudgeSelection(dx: 1, dy: 0)
        vm.nudgeSelection(dx: 10, dy: -5)
        XCTAssertEqual(vm.capture.annotations[0].kind, rect(21, 5))
        vm.undo()
        XCTAssertEqual(vm.capture.annotations[0].kind, rect(11, 10))
    }

    func testDeleteSelectionRemovesOnlySelectedAndClearsSelection() {
        let vm = makeViewModel()
        let a = vm.add(rect(0, 0)), b = vm.add(rect(100, 100))
        vm.selection = [a]
        vm.deleteSelection()
        XCTAssertEqual(vm.capture.annotations.map(\.id), [b])
        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testSelectionIsPrunedWhenTheAnnotationDisappears() {
        let vm = makeViewModel()
        let id = vm.add(rect())
        vm.selection = [id]
        vm.undo()  // 復原新增 → 標註消失
        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testReorderSelectionBringsItToTheFront() {
        let vm = makeViewModel()
        let a = vm.add(rect(0, 0)), b = vm.add(rect(20, 20)), c = vm.add(rect(40, 40))
        vm.selection = [a]
        vm.reorderSelection(.front)
        XCTAssertEqual(vm.capture.annotations.sorted { $0.zIndex < $1.zIndex }.map(\.id), [b, c, a])
    }

    // MARK: 匯出尺寸

    func testOutputPixelSizeFollowsCropScaleAndFinish() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.outputPixelSize, PixelSize(width: 400, height: 300))

        vm.commitCrop(PixelRect(x: 100, y: 50, width: 200, height: 100))
        XCTAssertEqual(vm.outputPixelSize, PixelSize(width: 200, height: 100))

        vm.setOutputScale(0.5)
        XCTAssertEqual(vm.outputPixelSize, PixelSize(width: 100, height: 50))

        vm.setFinish { $0.border = Finish.Border(color: .black, width: 6) }
        XCTAssertEqual(vm.outputPixelSize, PixelSize(width: 112, height: 62))

        let flat = try? Renderer.flatten(vm.capture, original: vm.original)
        XCTAssertEqual(flat?.width, vm.outputPixelSize.width)
        XCTAssertEqual(flat?.height, vm.outputPixelSize.height)
    }

    func testCropClearAndUndo() {
        let vm = makeViewModel()
        vm.commitCrop(PixelRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNotNil(vm.capture.crop)
        vm.clearCrop()
        XCTAssertNil(vm.capture.crop)
        vm.undo()
        XCTAssertNotNil(vm.capture.crop)
        XCTAssertNil(vm.cropDraft)
    }

    func testExportPreviewIsOnlyProducedWhenSomethingChangesTheOutput() async throws {
        let vm = makeViewModel()
        XCTAssertNil(vm.exportPreview)
        vm.setOutputScale(0.5)
        for _ in 0..<40 where vm.exportPreview == nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(vm.exportPreview)
        vm.setOutputScale(1)
        for _ in 0..<40 where vm.exportPreview != nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(vm.exportPreview, "回到預設值就不需要預覽")
    }
}
