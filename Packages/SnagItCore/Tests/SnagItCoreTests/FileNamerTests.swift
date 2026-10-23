import XCTest
@testable import SnagItCore

final class FileNamerTests: XCTestCase {
    private var folder: URL!
    // 固定時區，避免測試依賴執行環境：2026-10-23 14:30:05 UTC
    private let date = Date(timeIntervalSince1970: 1_792_765_805)
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("FileNamerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testNameFollowsSnagItForeverTimestampFormat() {
        let url = FileNamer.uniqueURL(in: folder, date: date, ext: "png", timeZone: utc)
        XCTAssertEqual(url.lastPathComponent, "SnagItForever 2026-10-23 14.30.05.png")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
    }

    func testExtensionIsUsedAsGiven() {
        XCTAssertEqual(FileNamer.uniqueURL(in: folder, date: date, ext: "jpg", timeZone: utc).pathExtension, "jpg")
    }

    func testExistingFileGetsSequenceNumberStartingAtTwo() throws {
        let first = FileNamer.uniqueURL(in: folder, date: date, ext: "png", timeZone: utc)
        try Data().write(to: first)
        let second = FileNamer.uniqueURL(in: folder, date: date, ext: "png", timeZone: utc)
        XCTAssertEqual(second.lastPathComponent, "SnagItForever 2026-10-23 14.30.05 2.png")
        try Data().write(to: second)
        let third = FileNamer.uniqueURL(in: folder, date: date, ext: "png", timeZone: utc)
        XCTAssertEqual(third.lastPathComponent, "SnagItForever 2026-10-23 14.30.05 3.png")
    }

    func testSequenceIsPerExtension() throws {
        try Data().write(to: FileNamer.uniqueURL(in: folder, date: date, ext: "png", timeZone: utc))
        XCTAssertEqual(
            FileNamer.uniqueURL(in: folder, date: date, ext: "jpg", timeZone: utc).lastPathComponent,
            "SnagItForever 2026-10-23 14.30.05.jpg")
    }

    func testTimezoneChangesTheTimestamp() {
        let taipei = TimeZone(identifier: "Asia/Taipei")!
        XCTAssertEqual(
            FileNamer.uniqueURL(in: folder, date: date, ext: "png", timeZone: taipei).lastPathComponent,
            "SnagItForever 2026-10-23 22.30.05.png")
    }
}
