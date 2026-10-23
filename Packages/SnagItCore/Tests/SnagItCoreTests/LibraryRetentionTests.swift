import XCTest
@testable import SnagItCore

final class LibraryRetentionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryRetention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 自行走訪目錄加總（同步函式；FileManager 的列舉器不能在 async 環境使用）。
    private func sizeOnDisk() -> Int64 {
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])!
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    private func image() -> SendableImage { SendableImage(TestImages.gradient(width: 64, height: 48)) }

    func testTotalSizeIsZeroForEmptyLibrary() async {
        let store = LibraryStore(directory: directory)
        let size = await store.totalSize()
        XCTAssertEqual(size, 0)
    }

    func testTotalSizeCountsEveryFileInEveryPackage() async throws {
        let store = LibraryStore(directory: directory)
        _ = try await store.create(image: image(), source: .region, scale: 1)
        _ = try await store.create(image: image(), source: .region, scale: 1)

        let expected = sizeOnDisk()
        let size = await store.totalSize()
        XCTAssertGreaterThan(size, 0)
        XCTAssertEqual(size, expected)
    }

    func testLibraryNeverDeletesAnythingOnItsOwn() async throws {
        let store = LibraryStore(directory: directory)
        for year in 0..<6 {
            _ = try await store.create(
                image: image(), source: .region, scale: 1,
                now: Date(timeIntervalSince1970: Double(year) * 86_400))  // 1970 年的舊資料
        }
        let entries = await store.list()
        XCTAssertEqual(entries.count, 6)
    }

    func testDeleteOlderRemovesOnlyEntriesBeforeTheCutoff() async throws {
        let store = LibraryStore(directory: directory)
        let day: Double = 86_400
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = try await store.create(image: image(), source: .region, scale: 1, now: now.addingTimeInterval(-40 * day))
        let older = try await store.create(image: image(), source: .region, scale: 1, now: now.addingTimeInterval(-90 * day))
        let recent = try await store.create(image: image(), source: .region, scale: 1, now: now.addingTimeInterval(-5 * day))

        let removed = try await store.deleteOlder(than: now.addingTimeInterval(-30 * day))
        XCTAssertEqual(removed, 2)
        let ids = await store.list().map(\.id)
        XCTAssertEqual(ids, [recent.id])
        XCTAssertFalse(ids.contains(old.id))
        XCTAssertFalse(ids.contains(older.id))
    }

    func testDeleteOlderWithNothingToDeleteReturnsZero() async throws {
        let store = LibraryStore(directory: directory)
        _ = try await store.create(image: image(), source: .region, scale: 1, now: Date())
        let removed = try await store.deleteOlder(than: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(removed, 0)
        let entries = await store.list()
        XCTAssertEqual(entries.count, 1)
    }

    func testDeleteOlderLeavesUnusableEntriesAlone() async throws {
        let store = LibraryStore(directory: directory)
        let capture = try await store.create(image: image(), source: .region, scale: 1, now: Date(timeIntervalSince1970: 1_000))
        let doc = directory.appendingPathComponent("\(capture.id.uuidString).snagitcapture/document.json")
        try Data("broken".utf8).write(to: doc)  // 損毀項目不是使用者能判斷日期的資料，不自動清除
        let removed = try await store.deleteOlder(than: Date())
        XCTAssertEqual(removed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: doc.deletingLastPathComponent().path))
    }
}
