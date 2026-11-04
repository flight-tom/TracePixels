import XCTest
@testable import TracePixelsCore

final class LibraryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracePixelsCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func image(_ w: Int = 64, _ h: Int = 48) -> SendableImage {
        SendableImage(TestImages.gradient(width: w, height: h))
    }

    func testCreateWritesPackageWithImageDocumentAndThumbnail() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(), source: .region, scale: 2)
        let package = directory.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture")
        for name in ["image.png", "document.json", "thumbnail.jpg"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent(name).path), name)
        }
        XCTAssertEqual(capture.pixelSize, PixelSize(width: 64, height: 48))
        XCTAssertEqual(capture.scale, 2)
        XCTAssertEqual(capture.schemaVersion, Capture.currentSchemaVersion)
    }

    func testLoadReturnsSameCaptureAndImage() async throws {
        let store = LibraryStore(directory: directory)
        let source = image()
        let created = try await store.create(image: source, source: .display(index: 0), scale: 1)
        let (loaded, loadedImage) = try await store.load(created.id)
        XCTAssertEqual(loaded.id, created.id)
        XCTAssertEqual(loaded.source, .display(index: 0))
        XCTAssertEqual(TestImages.pixels(loadedImage.cgImage), TestImages.pixels(source.cgImage))
    }

    func testSavePersistsAnnotationsAndStampsModifiedAt() async throws {
        let store = LibraryStore(directory: directory)
        var capture = try await store.create(image: image(), source: .region, scale: 1)
        capture.annotations = [Annotation(zIndex: 0, kind: .step(center: PixelPoint(x: 5, y: 5), number: 1), style: Style())]
        let saved = try await store.save(capture)
        XCTAssertGreaterThanOrEqual(saved.modifiedAt, capture.createdAt)
        let (reloaded, _) = try await store.load(capture.id)
        XCTAssertEqual(reloaded.annotations, capture.annotations)
    }

    func testSaveNeverModifiesOriginalImageBytes() async throws {
        let store = LibraryStore(directory: directory)
        var capture = try await store.create(image: image(), source: .region, scale: 1)
        let imageURL = directory.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture/image.png")
        let before = try Data(contentsOf: imageURL)
        capture.annotations = [Annotation(zIndex: 0, kind: .blur(rect: PixelRect(x: 0, y: 0, width: 32, height: 32), strength: 8), style: Style())]
        _ = try await store.save(capture)
        _ = try await store.save(capture)
        XCTAssertEqual(try Data(contentsOf: imageURL), before)
    }

    func testListIsNewestFirst() async throws {
        let store = LibraryStore(directory: directory)
        let old = try await store.create(image: image(), source: .region, scale: 1, now: Date(timeIntervalSince1970: 1_000_000))
        let new = try await store.create(image: image(), source: .region, scale: 1, now: Date(timeIntervalSince1970: 2_000_000))
        let middle = try await store.create(image: image(), source: .region, scale: 1, now: Date(timeIntervalSince1970: 1_500_000))
        let ids = await store.list().map(\.id)
        XCTAssertEqual(ids, [new.id, middle.id, old.id])
    }

    func testDeleteRemovesPackage() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(), source: .region, scale: 1)
        try await store.delete(capture.id)
        let entries = await store.list()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture").path))
    }

    func testCorruptEntryIsIsolatedAndNotDeleted() async throws {
        let store = LibraryStore(directory: directory)
        let good = try await store.create(image: image(), source: .region, scale: 1)
        let bad = try await store.create(image: image(), source: .region, scale: 1)
        let badPackage = directory.appendingPathComponent("\(bad.id.uuidString).tracepixelscapture")
        try Data("not json".utf8).write(to: badPackage.appendingPathComponent("document.json"))

        let entries = await store.list()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.id == good.id }?.isUsable, true)
        XCTAssertEqual(entries.first { $0.id == bad.id }?.isUsable, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: badPackage.path))
        let loadedGood = try await store.load(good.id)
        XCTAssertEqual(loadedGood.0.id, good.id)
    }

    func testHigherSchemaVersionIsUnusableAndNeverOverwritten() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(), source: .region, scale: 1)
        let docURL = directory.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture/document.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: docURL)) as! [String: Any]
        object["schemaVersion"] = Capture.currentSchemaVersion + 1
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: docURL)

        let entry = await store.list().first { $0.id == capture.id }
        XCTAssertEqual(entry?.isUsable, false)
        do {
            _ = try await store.save(capture)
            XCTFail("應該拒絕覆寫較新版本的文件")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: docURL), future)
    }

    func testMissingThumbnailIsRebuilt() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(), source: .region, scale: 1)
        let thumb = directory.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture/thumbnail.jpg")
        try FileManager.default.removeItem(at: thumb)
        let entry = await store.list().first
        XCTAssertNotNil(entry?.thumbnailURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumb.path))
    }

    func testThumbnailLongestSideIs320() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(1600, 900), source: .region, scale: 2)
        let thumb = directory.appendingPathComponent("\(capture.id.uuidString).tracepixelscapture/thumbnail.jpg")
        let src = CGImageSourceCreateWithURL(thumb as CFURL, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(max(img.width, img.height), 320)
    }

    // MARK: 暫存目錄建立與殘留清理（匯入功能）

    func testCreateLeavesOnlyTheFinishedPackage() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(), source: .region, scale: 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names, ["\(capture.id.uuidString).tracepixelscapture"])
    }

    func testFailedCreateLeavesNoItemAndNoStagingDirectory() async throws {
        try XCTSkipIf(getuid() == 0, "root 不受檔案權限限制")
        let store = LibraryStore(directory: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        do {
            _ = try await store.create(image: image(), source: .region, scale: 1)
            XCTFail("目錄唯讀時應該失敗")
        } catch {}
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        let list = await store.list()
        XCTAssertTrue(list.isEmpty)
    }

    func testStaleStagingDirectoriesAreIgnoredThenRemoved() async throws {
        let store = LibraryStore(directory: directory)
        let kept = try await store.create(image: image(), source: .region, scale: 1)
        let stale = directory.appendingPathComponent("\(UUID().uuidString).importing", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("半成品".utf8).write(to: stale.appendingPathComponent("image.png"))

        let listed = await store.list()
        XCTAssertEqual(listed.map(\.id), [kept.id], "暫存目錄不可被當成項目列出")

        let removed = await store.removeStaleStaging()
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        let after = await store.list()
        XCTAssertEqual(after.map(\.id), [kept.id], "正式項目不受影響")
        let again = await store.removeStaleStaging()
        XCTAssertEqual(again, 0)
    }

    func testTotalSizeCountsStagingDirectories() async throws {
        let store = LibraryStore(directory: directory)
        let before = await store.totalSize()
        let stale = directory.appendingPathComponent("\(UUID().uuidString).importing", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: stale.appendingPathComponent("image.png"))
        let after = await store.totalSize()
        XCTAssertEqual(after - before, 4096)
    }

    func testListExposesSourceFileNameOnlyForImportedItems() async throws {
        let store = LibraryStore(directory: directory)
        let imported = try await store.create(image: image(), source: .imported(fileName: "IMG_0042.HEIC"), scale: 1)
        let region = try await store.create(image: image(), source: .region, scale: 1)
        let broken = UUID()
        let brokenURL = directory.appendingPathComponent("\(broken.uuidString).tracepixelscapture", isDirectory: true)
        try FileManager.default.createDirectory(at: brokenURL, withIntermediateDirectories: true)

        let entries = await store.list()
        XCTAssertEqual(entries.first { $0.id == imported.id }?.sourceFileName, "IMG_0042.HEIC")
        XCTAssertNil(entries.first { $0.id == region.id }?.sourceFileName)
        let brokenEntry = entries.first { $0.id == broken }
        XCTAssertNotNil(brokenEntry)
        XCTAssertNil(brokenEntry?.sourceFileName)
        XCTAssertEqual(brokenEntry?.isUsable, false)
    }
}
