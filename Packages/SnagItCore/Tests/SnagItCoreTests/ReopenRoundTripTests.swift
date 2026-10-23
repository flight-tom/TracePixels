import XCTest
@testable import SnagItCore

final class ReopenRoundTripTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReopenRoundTrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let kinds: [Annotation.Kind] = [
        .arrow(start: PixelPoint(x: 1, y: 1), end: PixelPoint(x: 30, y: 30)),
        .line(start: PixelPoint(x: 2, y: 2), end: PixelPoint(x: 40, y: 10)),
        .rectangle(rect: PixelRect(x: 5, y: 5, width: 20, height: 10), filled: true),
        .ellipse(rect: PixelRect(x: 6, y: 6, width: 20, height: 10), filled: false),
        .pen(points: [PixelPoint(x: 0, y: 0), PixelPoint(x: 5, y: 9)]),
        .highlighter(points: [PixelPoint(x: 0, y: 4), PixelPoint(x: 30, y: 4)]),
        .text(rect: PixelRect(x: 10, y: 10, width: 80, height: 24), string: "重新開啟後仍可編輯"),
        .step(center: PixelPoint(x: 50, y: 50), number: 7),
        .blur(rect: PixelRect(x: 0, y: 0, width: 32, height: 32), strength: 16),
        .pixelate(rect: PixelRect(x: 8, y: 8, width: 32, height: 32), strength: 12),
    ]

    /// 編輯、儲存，再像重新啟動 App 那樣用全新的 LibraryStore 載入。
    private func saveAndReopen() async throws -> (original: Capture, reopened: Capture) {
        let store = LibraryStore(directory: directory)
        let created = try await store.create(image: SendableImage(TestImages.gradient(width: 128, height: 96)), source: .region, scale: 2)
        var doc = EditingDocument(capture: created)
        for kind in kinds { doc.add(Annotation(zIndex: 0, kind: kind, style: Style(color: .black, lineWidth: 6))) }
        doc.setCrop(PixelRect(x: 4, y: 4, width: 100, height: 80))
        doc.setFinish(Finish(cornerRadius: 8))
        let saved = try await store.save(doc.capture)

        let relaunched = LibraryStore(directory: directory)
        let (loaded, _) = try await relaunched.load(created.id)
        return (saved, loaded)
    }

    func testEveryAnnotationSurvivesRelaunchExactly() async throws {
        let (saved, loaded) = try await saveAndReopen()
        XCTAssertEqual(loaded.annotations, saved.annotations)
        XCTAssertEqual(loaded.annotations.map(\.kind.typeName), kinds.map(\.typeName))
        XCTAssertEqual(loaded.crop, saved.crop)
        XCTAssertEqual(loaded.finish, saved.finish)
    }

    func testReopenedAnnotationsAreIndividuallyEditable() async throws {
        let (_, loaded) = try await saveAndReopen()
        var doc = EditingDocument(capture: loaded)
        for target in loaded.annotations {
            var edited = doc
            edited.update(target.id) { $0.style.color = RGBAColor(r: 0, g: 0.5, b: 1) }
            let changed = edited.capture.annotations.filter { $0.style.color != .black }
            XCTAssertEqual(changed.map(\.id), [target.id], "只有 \(target.kind.typeName) 被修改")
        }
        doc.remove([loaded.annotations[0].id])
        XCTAssertEqual(doc.capture.annotations.count, kinds.count - 1)
    }

    func testReopeningStartsWithAnEmptyUndoHistory() async throws {
        let (_, loaded) = try await saveAndReopen()
        let doc = EditingDocument(capture: loaded)
        XCTAssertFalse(doc.canUndo)
        XCTAssertFalse(doc.canRedo)
    }

    func testHitTestingWorksOnReopenedAnnotations() async throws {
        let (_, loaded) = try await saveAndReopen()
        let doc = EditingDocument(capture: loaded)
        XCTAssertNotNil(doc.hitTest(PixelPoint(x: 50, y: 50), tolerance: 2))  // 步驟標記
    }

    func testStepNumberingContinuesFromReopenedAnnotations() async throws {
        let (_, loaded) = try await saveAndReopen()
        XCTAssertEqual(EditingDocument(capture: loaded).nextStepNumber(), 8)
    }
}
