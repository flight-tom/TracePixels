import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import TracePixelsCore

/// 批次匯入（FR-035、FR-036、FR-040、FR-045、SC-013、SC-014）。
final class LibraryImporterTests: XCTestCase {
    private var dir: TestDirectory!
    private var libraryURL: URL!
    private var store: LibraryStore!
    private var importer: LibraryImporter!

    override func setUpWithError() throws {
        dir = try TestDirectory()
        libraryURL = try dir.subdirectory("library")
        store = LibraryStore(directory: libraryURL)
        importer = LibraryImporter(store: store)
    }

    override func tearDown() {
        store = nil
        importer = nil
        dir = nil
    }

    private func png(_ name: String, width: Int = 30, height: Int = 20) throws -> URL {
        let url = dir.file(name)
        try TestImages.write(TestImages.gradient(width: width, height: height), as: .png, to: url)
        return url
    }

    private func libraryContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: libraryURL.path).sorted()
    }

    func testValidFilesBecomeImportedCapturesInInputOrder() async throws {
        let urls = [try png("a.png", width: 10, height: 10), try png("b.png", width: 20, height: 12), try png("c.png", width: 5, height: 9)]
        let result = await importer.importFiles(urls)
        XCTAssertEqual(result.imported.count, 3)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(
            result.imported.map(\.source), [.imported(fileName: "a.png"), .imported(fileName: "b.png"), .imported(fileName: "c.png")])
        XCTAssertEqual(result.imported.map(\.pixelSize), [PixelSize(width: 10, height: 10), PixelSize(width: 20, height: 12), PixelSize(width: 5, height: 9)])
        XCTAssertTrue(result.imported.allSatisfy { $0.scale == 1.0 })
        let entries = await store.list()
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy(\.isUsable))
    }

    func testMixedInputKeepsValidOnesAndLeavesNothingBehind() async throws {
        let fake = dir.file("fake.png")
        try "不是圖片".write(to: fake, atomically: true, encoding: .utf8)
        let text = dir.file("note.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        let folder = try dir.subdirectory("folder")
        let urls = [try png("one.png"), fake, text, folder, URL(string: "https://example.com/x.png")!, try png("two.png")]

        let result = await importer.importFiles(urls)

        XCTAssertEqual(result.imported.count, 2)
        XCTAssertEqual(result.failures.count, 4)
        XCTAssertEqual(result.failures.map(\.reason), [.unsupportedFormat, .unsupportedFormat, .notAFile, .notAFile])
        XCTAssertEqual(result.failures.map(\.name), ["fake.png", "note.txt", "folder", "https://example.com/x.png"])
        XCTAssertEqual(result.skippedNonFileCount, 2)

        let entries = await store.list()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy(\.isUsable), "不可有「無法讀取」的項目")
        let names = try libraryContents()
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.allSatisfy { $0.hasSuffix(".tracepixelscapture") }, "不可有殘留的暫存目錄：\(names)")
    }

    func testSameFileImportedTwiceGivesTwoIndependentItems() async throws {
        let url = try png("same.png")
        let result = await importer.importFiles([url, url])
        XCTAssertEqual(result.imported.count, 2)
        XCTAssertNotEqual(result.imported[0].id, result.imported[1].id)
        let list = await store.list()
        XCTAssertEqual(list.count, 2)
    }

    func testItemsSurviveDeletionOfTheSourceFile() async throws {
        let url = try png("gone.png", width: 33, height: 22)
        let result = await importer.importFiles([url])
        try FileManager.default.removeItem(at: url)
        let (capture, image) = try await store.load(result.imported[0].id)
        XCTAssertEqual(image.cgImage.width, 33)
        XCTAssertEqual(capture.source, .imported(fileName: "gone.png"))
    }

    func testSourceFilesAreNotModified() async throws {
        let url = try png("untouched.png")
        let before = try Data(contentsOf: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        _ = await importer.importFiles([url])
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, modified)
    }

    func testImportedImageIsImmutableAndAnnotationsRoundTripAcrossStores() async throws {
        let result = await importer.importFiles([try png("edit.png")])
        var capture = result.imported[0]
        let imageURL = libraryURL.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture/image.png")
        let before = try Data(contentsOf: imageURL)

        capture.annotations = [Annotation(zIndex: 0, kind: .step(center: PixelPoint(x: 4, y: 4), number: 1), style: Style())]
        _ = try await store.save(capture)
        XCTAssertEqual(try Data(contentsOf: imageURL), before, "匯入的影像不可被修改")

        // 模擬重新啟動：全新的 LibraryStore 讀同一個目錄（SC-014）。
        let reopened = LibraryStore(directory: libraryURL)
        let (loaded, _) = try await reopened.load(capture.id)
        XCTAssertEqual(loaded.annotations, capture.annotations)
        XCTAssertEqual(loaded.source, .imported(fileName: "edit.png"))
    }

    func testProgressIsReportedAfterEachFile() async throws {
        let bad = dir.file("bad.png")
        try "x".write(to: bad, atomically: true, encoding: .utf8)
        let urls = [try png("p1.png"), bad, try png("p3.png")]
        let box = ProgressBox()
        _ = await importer.importFiles(urls) { box.append($0) }
        let reports = box.values
        XCTAssertEqual(reports.map(\.done), [1, 2, 3])
        XCTAssertTrue(reports.allSatisfy { $0.total == 3 })
        XCTAssertEqual(reports.map(\.currentName), ["p1.png", "bad.png", "p3.png"])
    }

    func testCancellationKeepsFinishedItemsAndLeavesNoResidue() async throws {
        let urls = try (1...4).map { try png("c\($0).png") }
        let importer = self.importer!
        let result = await Task {
            await importer.importFiles(urls) { progress in
                if progress.done == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.imported.count, 2)
        let list = await store.list()
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(try libraryContents().allSatisfy { $0.hasSuffix(".tracepixelscapture") })
    }

    func testStorageFailureIsClassifiedAndNothingIsLeftBehind() async throws {
        try XCTSkipIf(getuid() == 0, "root 不受檔案權限限制")
        let urls = [try png("s1.png"), try png("s2.png")]
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: libraryURL.path)
        let result = await importer.importFiles(urls)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: libraryURL.path)

        XCTAssertTrue(result.imported.isEmpty)
        XCTAssertEqual(result.failures.map(\.reason), [.storageFailed, .storageFailed])
        XCTAssertEqual(try libraryContents(), [])
    }

    func testEmptyInputGivesEmptyResult() async {
        let result = await importer.importFiles([])
        XCTAssertTrue(result.imported.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.cancelled)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ImportProgress] = []
    func append(_ value: ImportProgress) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [ImportProgress] { lock.lock(); defer { lock.unlock() }; return storage }
}
