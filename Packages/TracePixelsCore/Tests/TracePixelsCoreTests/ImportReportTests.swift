import XCTest
@testable import TracePixelsCore

/// 彙總報告的規則（FR-034、FR-040、FR-045）：不需要螢幕，所以在核心測試。
final class ImportReportTests: XCTestCase {
    private func captures(_ count: Int) -> [Capture] {
        (0..<count).map { i in
            Capture(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                source: .imported(fileName: "f\(i).png"), pixelSize: PixelSize(width: 4, height: 4), scale: 1)
        }
    }

    private func failures(_ count: Int, reason: ImportFailure = .corrupt) -> [ImportFailureItem] {
        (0..<count).map { ImportFailureItem(name: "bad\($0).png", reason: reason) }
    }

    func testOnlyTheFirstFiveEditorsOpen() {
        let imported = captures(7)
        let report = ImportReport.make(
            from: ImportResult(imported: imported, failures: [], cancelled: false), openEditors: true)
        XCTAssertEqual(report.editorsToOpen, imported.prefix(5).map(\.id))
        XCTAssertEqual(report.onlyInLibraryCount, 2)
        XCTAssertTrue(report.needsAlert, "有項目只在資料庫中，必須告知")
    }

    func testNoEditorsOpenWhenOnlyImporting() {
        let report = ImportReport.make(
            from: ImportResult(imported: captures(3), failures: [], cancelled: false), openEditors: false)
        XCTAssertTrue(report.editorsToOpen.isEmpty)
        XCTAssertEqual(report.onlyInLibraryCount, 0, "只匯入時不算「沒開編輯器」")
        XCTAssertFalse(report.needsAlert)
    }

    func testAllSucceededAndAllOpenedNeedsNoAlert() {
        for count in [1, 5] {
            let report = ImportReport.make(
                from: ImportResult(imported: captures(count), failures: [], cancelled: false), openEditors: true)
            XCTAssertEqual(report.editorsToOpen.count, count)
            XCTAssertEqual(report.onlyInLibraryCount, 0)
            XCTAssertFalse(report.needsAlert)
        }
    }

    func testAtMostEightFailuresAreListed() {
        let report = ImportReport.make(
            from: ImportResult(imported: [], failures: failures(12), cancelled: false), openEditors: true)
        XCTAssertEqual(report.listedFailures.count, 8)
        XCTAssertEqual(report.unlistedFailureCount, 4)
        XCTAssertEqual(report.listedFailures.map(\.name), (0..<8).map { "bad\($0).png" })
        XCTAssertTrue(report.needsAlert)
    }

    func testNonFileItemsAreCountedNotListed() {
        let mixed = failures(2) + failures(3, reason: .notAFile)
        let report = ImportReport.make(
            from: ImportResult(imported: captures(1), failures: mixed, cancelled: false), openEditors: false)
        XCTAssertEqual(report.skippedNonFileCount, 3)
        XCTAssertEqual(report.listedFailures.count, 2)
        XCTAssertTrue(report.listedFailures.allSatisfy { $0.reason != .notAFile })
        XCTAssertTrue(report.needsAlert)
    }

    func testOnlyNonFileItemsStillNeedsAlert() {
        let report = ImportReport.make(
            from: ImportResult(imported: [], failures: failures(2, reason: .notAFile), cancelled: false),
            openEditors: false)
        XCTAssertEqual(report.skippedNonFileCount, 2)
        XCTAssertTrue(report.listedFailures.isEmpty)
        XCTAssertTrue(report.needsAlert)
    }

    func testExactlyEightFailuresLeaveNothingUnlisted() {
        let report = ImportReport.make(
            from: ImportResult(imported: [], failures: failures(8), cancelled: false), openEditors: false)
        XCTAssertEqual(report.listedFailures.count, 8)
        XCTAssertEqual(report.unlistedFailureCount, 0)
    }
}
