import XCTest
@testable import SnagItCore

final class EditingDocumentTests: XCTestCase {
    private func makeDocument() -> EditingDocument {
        EditingDocument(capture: Capture(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), source: .region,
            pixelSize: PixelSize(width: 400, height: 300), scale: 1))
    }

    private func rect(_ x: Double, _ y: Double, _ w: Double = 40, _ h: Double = 30, filled: Bool = true) -> Annotation.Kind {
        .rectangle(rect: PixelRect(x: x, y: y, width: w, height: h), filled: filled)
    }

    private func step(_ n: Int) -> Annotation.Kind {
        .step(center: PixelPoint(x: Double(n) * 10, y: 10), number: n)
    }

    // MARK: 新增、更新、移除

    func testAddPlacesAnnotationOnTopWithIncreasingZIndex() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 99, kind: rect(0, 0))
        let b = Annotation(zIndex: 99, kind: rect(10, 10))
        doc.add(a); doc.add(b)
        XCTAssertEqual(doc.capture.annotations.map(\.id), [a.id, b.id])
        XCTAssertEqual(doc.capture.annotations.map(\.zIndex), [0, 1])
    }

    func testUpdateChangesOnlyTheTargetAnnotation() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 0, kind: rect(0, 0)), b = Annotation(zIndex: 0, kind: rect(50, 50))
        doc.add(a); doc.add(b)
        doc.update(a.id) { $0.style.color = .black }
        XCTAssertEqual(doc.capture.annotations.first { $0.id == a.id }?.style.color, .black)
        XCTAssertEqual(doc.capture.annotations.first { $0.id == b.id }?.style.color, .red)
    }

    func testUpdateOfUnknownIDIsNoOpAndRecordsNoHistory() {
        var doc = makeDocument()
        doc.update(UUID()) { $0.style.color = .black }
        XCTAssertFalse(doc.canUndo)
    }

    func testRemoveDeletesSelectedAndRenumbersZIndex() {
        var doc = makeDocument()
        let items = (0..<3).map { Annotation(zIndex: 0, kind: rect(Double($0) * 20, 0)) }
        items.forEach { doc.add($0) }
        doc.remove([items[1].id])
        XCTAssertEqual(doc.capture.annotations.map(\.id), [items[0].id, items[2].id])
        XCTAssertEqual(doc.capture.annotations.map(\.zIndex), [0, 1])
    }

    // MARK: 復原與重做

    func testUndoRedoWalkThroughHistoryInOrder() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 0, kind: rect(0, 0)), b = Annotation(zIndex: 0, kind: rect(10, 10))
        doc.add(a); doc.add(b)
        doc.update(a.id) { $0.style.lineWidth = 9 }

        doc.undo()
        XCTAssertEqual(doc.capture.annotations.first { $0.id == a.id }?.style.lineWidth, 4)
        doc.undo()
        XCTAssertEqual(doc.capture.annotations.map(\.id), [a.id])
        doc.undo()
        XCTAssertTrue(doc.capture.annotations.isEmpty)
        XCTAssertFalse(doc.canUndo)
        XCTAssertTrue(doc.canRedo)

        doc.redo(); doc.redo(); doc.redo()
        XCTAssertEqual(doc.capture.annotations.count, 2)
        XCTAssertEqual(doc.capture.annotations.first { $0.id == a.id }?.style.lineWidth, 9)
        XCTAssertFalse(doc.canRedo)
    }

    func testNewEditClearsRedoStack() {
        var doc = makeDocument()
        doc.add(Annotation(zIndex: 0, kind: rect(0, 0)))
        doc.undo()
        XCTAssertTrue(doc.canRedo)
        doc.add(Annotation(zIndex: 0, kind: rect(5, 5)))
        XCTAssertFalse(doc.canRedo)
    }

    func testUndoHasNoDepthLimit() {
        var doc = makeDocument()
        for i in 0..<500 { doc.add(Annotation(zIndex: 0, kind: step(i))) }
        for _ in 0..<500 { doc.undo() }
        XCTAssertTrue(doc.capture.annotations.isEmpty)
    }

    func testGestureCoalescesManyChangesIntoOneUndoStep() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 0, kind: rect(0, 0))
        doc.add(a)
        doc.beginGesture()
        for dx in stride(from: 1.0, through: 50.0, by: 1.0) {
            doc.update(a.id) { $0.kind = .rectangle(rect: PixelRect(x: dx, y: 0, width: 40, height: 30), filled: true) }
        }
        doc.endGesture()
        doc.undo()  // 一次復原整段拖曳
        XCTAssertEqual(doc.capture.annotations.first?.kind, rect(0, 0))
        doc.undo()  // 再一次才會移除新增
        XCTAssertTrue(doc.capture.annotations.isEmpty)
    }

    func testGestureWithNoNetChangeRecordsNothing() {
        var doc = makeDocument()
        doc.beginGesture(); doc.endGesture()
        XCTAssertFalse(doc.canUndo)
    }

    // MARK: 前後順序

    private func orderedIDs(_ doc: EditingDocument) -> [UUID] {
        doc.capture.annotations.sorted { $0.zIndex < $1.zIndex }.map(\.id)
    }

    func testReorderFrontBackForwardBackward() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 0, kind: rect(0, 0)), b = Annotation(zIndex: 0, kind: rect(1, 1))
        let c = Annotation(zIndex: 0, kind: rect(2, 2)), d = Annotation(zIndex: 0, kind: rect(3, 3))
        [a, b, c, d].forEach { doc.add($0) }

        doc.reorder([a.id], to: .front)
        XCTAssertEqual(orderedIDs(doc), [b.id, c.id, d.id, a.id])
        doc.reorder([a.id], to: .back)
        XCTAssertEqual(orderedIDs(doc), [a.id, b.id, c.id, d.id])
        doc.reorder([b.id], to: .forward)
        XCTAssertEqual(orderedIDs(doc), [a.id, c.id, b.id, d.id])
        doc.reorder([b.id], to: .backward)
        XCTAssertEqual(orderedIDs(doc), [a.id, b.id, c.id, d.id])
        doc.reorder([d.id], to: .forward)  // 已在最上層：不變
        XCTAssertEqual(orderedIDs(doc), [a.id, b.id, c.id, d.id])
        XCTAssertEqual(doc.capture.annotations.map(\.zIndex).sorted(), [0, 1, 2, 3])
    }

    // MARK: 命中測試

    func testHitTestReturnsTopmostOfOverlappingFilledShapes() {
        var doc = makeDocument()
        let low = Annotation(zIndex: 0, kind: rect(10, 10, 100, 100))
        let high = Annotation(zIndex: 0, kind: rect(50, 50, 100, 100))
        doc.add(low); doc.add(high)
        XCTAssertEqual(doc.hitTest(PixelPoint(x: 80, y: 80), tolerance: 2), high.id)
        XCTAssertEqual(doc.hitTest(PixelPoint(x: 20, y: 20), tolerance: 2), low.id)
        XCTAssertNil(doc.hitTest(PixelPoint(x: 300, y: 250), tolerance: 2))
    }

    func testHitTestUnfilledRectangleOnlyHitsNearItsEdge() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 0, kind: rect(10, 10, 100, 100, filled: false))
        doc.add(a)
        XCTAssertEqual(doc.hitTest(PixelPoint(x: 10, y: 60), tolerance: 3), a.id)
        XCTAssertNil(doc.hitTest(PixelPoint(x: 60, y: 60), tolerance: 3))
    }

    func testHitTestLineUsesDistanceToSegment() {
        var doc = makeDocument()
        let a = Annotation(zIndex: 0, kind: .line(start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 100, y: 0)))
        doc.add(a)
        XCTAssertEqual(doc.hitTest(PixelPoint(x: 50, y: 4), tolerance: 3), a.id)  // 4 ≤ 3 + 線寬 4 的一半
        XCTAssertNil(doc.hitTest(PixelPoint(x: 50, y: 12), tolerance: 3))
        XCTAssertNil(doc.hitTest(PixelPoint(x: 140, y: 0), tolerance: 3))
    }

    func testHitTestStepAndEllipse() {
        var doc = makeDocument()
        let s = Annotation(zIndex: 0, kind: .step(center: PixelPoint(x: 200, y: 200), number: 1))
        let e = Annotation(zIndex: 0, kind: .ellipse(rect: PixelRect(x: 0, y: 0, width: 100, height: 50), filled: true))
        doc.add(s); doc.add(e)
        XCTAssertEqual(doc.hitTest(PixelPoint(x: 205, y: 203), tolerance: 2), s.id)
        XCTAssertEqual(doc.hitTest(PixelPoint(x: 50, y: 25), tolerance: 2), e.id)
        XCTAssertNil(doc.hitTest(PixelPoint(x: 2, y: 2), tolerance: 1))  // 外接矩形角落不在橢圓內
    }

    // MARK: 步驟編號

    func testNextStepNumberIsMaxPlusOneAndNeverRenumbers() {
        var doc = makeDocument()
        XCTAssertEqual(doc.nextStepNumber(), 1)
        let s1 = Annotation(zIndex: 0, kind: step(1)), s2 = Annotation(zIndex: 0, kind: step(2)), s3 = Annotation(zIndex: 0, kind: step(3))
        [s1, s2, s3].forEach { doc.add($0) }
        XCTAssertEqual(doc.nextStepNumber(), 4)
        doc.remove([s2.id])  // 不自動重新編號
        XCTAssertEqual(doc.capture.annotations.map(\.kind), [step(1), step(3)])
        XCTAssertEqual(doc.nextStepNumber(), 4)
    }

    // MARK: 文件層級設定

    func testCropOutputScaleAndFinishAreUndoable() {
        var doc = makeDocument()
        doc.setCrop(PixelRect(x: 10, y: 10, width: 100, height: 100))
        doc.setOutputScale(2)
        doc.setFinish(Finish(cornerRadius: 12))
        XCTAssertEqual(doc.capture.crop, PixelRect(x: 10, y: 10, width: 100, height: 100))
        doc.undo(); doc.undo(); doc.undo()
        XCTAssertNil(doc.capture.crop)
        XCTAssertEqual(doc.capture.outputScale, 1)
        XCTAssertEqual(doc.capture.finish, .none)
    }
}
