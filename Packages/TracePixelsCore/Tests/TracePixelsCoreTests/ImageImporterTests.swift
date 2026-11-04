import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import TracePixelsCore

/// 單一檔案的讀取、驗證與方向處理（FR-033、FR-035、FR-037、FR-038、FR-040、SC-010、SC-011）。
final class ImageImporterTests: XCTestCase {
    private var dir: TestDirectory!

    override func setUpWithError() throws { dir = try TestDirectory() }
    override func tearDown() { dir = nil }

    private func load(_ url: URL) throws -> LoadedImage { try ImageImporter.load(from: url) }

    private func failure(of url: URL, file: StaticString = #filePath, line: UInt = #line) -> ImportFailure? {
        do {
            _ = try ImageImporter.load(from: url)
            XCTFail("應該失敗", file: file, line: line)
            return nil
        } catch let error as ImportFailure {
            return error
        } catch {
            XCTFail("錯誤型別不對：\(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: 格式與尺寸（SC-011）

    func testEverySupportedFormatKeepsPixelSize() throws {
        let formats: [(String, UTType)] = [
            ("png", .png), ("jpg", .jpeg), ("tiff", .tiff), ("gif", .gif), ("bmp", .bmp), ("heic", .heic),
        ]
        let source = TestImages.gradient(width: 97, height: 61)
        var tested = 0
        for (ext, type) in formats {
            guard TestImages.canEncode(type) else {
                print("略過 \(ext)：本機沒有編碼器")
                continue
            }
            let url = dir.file("sample.\(ext)")
            try TestImages.write(source, as: type, to: url)
            let loaded = try load(url)
            XCTAssertEqual(loaded.image.cgImage.width, 97, ext)
            XCTAssertEqual(loaded.image.cgImage.height, 61, ext)
            XCTAssertEqual(loaded.fileName, "sample.\(ext)")
            tested += 1
        }
        XCTAssertGreaterThanOrEqual(tested, 4, "至少 PNG／JPEG／TIFF／GIF 要能測")
    }

    func testHEICIsSupportedWhenEncoderIsAvailable() throws {
        try XCTSkipUnless(TestImages.canEncode(.heic), "本機沒有 HEIC 編碼器")
        let url = dir.file("photo.heic")
        try TestImages.write(TestImages.gradient(width: 64, height: 48), as: .heic, to: url)
        let loaded = try load(url)
        XCTAssertEqual(loaded.image.cgImage.width, 64)
        XCTAssertEqual(loaded.image.cgImage.height, 48)
    }

    func testPNGPixelsAreIdenticalToTheSource() throws {
        let source = TestImages.gradient(width: 40, height: 30)
        let url = dir.file("g.png")
        try TestImages.write(source, as: .png, to: url)
        let loaded = try load(url)
        XCTAssertEqual(TestImages.pixels(loaded.image.cgImage), TestImages.pixels(source))
    }

    func testRepeatedLoadsGiveIdenticalPixels() throws {
        let url = dir.file("g.png")
        try TestImages.write(TestImages.gradient(width: 40, height: 30), as: .png, to: url)
        XCTAssertEqual(
            TestImages.pixels(try load(url).image.cgImage), TestImages.pixels(try load(url).image.cgImage))
    }

    func testAnimatedGIFUsesOnlyTheFirstFrame() throws {
        try XCTSkipUnless(TestImages.canEncode(.gif))
        let url = dir.file("anim.gif")
        try TestImages.writeAnimatedGIF(
            frames: [
                TestImages.solid(width: 20, height: 20, r: 255, g: 0, b: 0),
                TestImages.solid(width: 20, height: 20, r: 0, g: 0, b: 255),
            ], to: url)
        let pixel = TestImages.pixel(try load(url).image.cgImage, x: 10, y: 10)
        XCTAssertGreaterThan(pixel.r, 200)
        XCTAssertLessThan(pixel.b, 60)
    }

    // MARK: 透明度、方向、色彩（FR-038）

    func testAlphaIsPreserved() throws {
        let source = TestImages.make(width: 16, height: 16) { x, _ in
            x < 8 ? (0, 0, 0, 0) : (200, 100, 50, 255)
        }
        let url = dir.file("alpha.png")
        try TestImages.write(source, as: .png, to: url)
        let loaded = try load(url).image.cgImage
        XCTAssertEqual(TestImages.pixel(loaded, x: 2, y: 5).a, 0)
        let opaque = TestImages.pixel(loaded, x: 12, y: 5)
        XCTAssertEqual(opaque.a, 255)
        XCTAssertEqual(opaque.r, 200)
    }

    func testPartialAlphaStaysPartial() throws {
        let source = TestImages.make(width: 8, height: 8) { _, _ in (50, 25, 10, 128) }
        let url = dir.file("half.png")
        try TestImages.write(source, as: .png, to: url)
        let pixel = TestImages.pixel(try load(url).image.cgImage, x: 4, y: 4)
        XCTAssertEqual(Int(pixel.a), 128, accuracy: 1)
    }

    /// 左上角 16×16 是紅色，其餘藍色；TIFF 為無損，所以可以逐像素驗證轉正後的內容。
    private func markerImage(width: Int = 48, height: Int = 32) -> CGImage {
        TestImages.make(width: width, height: height) { x, y in
            x < 16 && y < 16 ? (255, 0, 0, 255) : (0, 0, 255, 255)
        }
    }

    /// EXIF 方向 → 原圖座標 (x, y) 轉正後的位置。
    private func destination(orientation: Int, x: Int, y: Int, width w: Int, height h: Int) -> (Int, Int) {
        switch orientation {
        case 1: return (x, y)
        case 2: return (w - 1 - x, y)
        case 3: return (w - 1 - x, h - 1 - y)
        case 4: return (x, h - 1 - y)
        case 5: return (y, x)
        case 6: return (h - 1 - y, x)
        case 7: return (h - 1 - y, w - 1 - x)
        default: return (y, w - 1 - x)  // 8
        }
    }

    func testEveryExifOrientationIsAppliedPixelExactly() throws {
        try XCTSkipUnless(TestImages.canEncode(.tiff))
        let w = 48, h = 32
        let source = markerImage(width: w, height: h)
        let sourcePixels = TestImages.pixels(source)
        for orientation in 1...8 {
            let url = dir.file("o\(orientation).tiff")
            try TestImages.write(source, as: .tiff, to: url, orientation: orientation)
            let loaded = try load(url).image.cgImage
            let swapped = orientation >= 5
            XCTAssertEqual(loaded.width, swapped ? h : w, "方向 \(orientation) 的寬")
            XCTAssertEqual(loaded.height, swapped ? w : h, "方向 \(orientation) 的高")
            let out = TestImages.pixels(loaded)
            for (x, y) in [(2, 2), (30, 5), (5, 25), (40, 28), (15, 15), (16, 16)] {
                let (dx, dy) = destination(orientation: orientation, x: x, y: y, width: w, height: h)
                let from = (y * w + x) * 4, to = (dy * loaded.width + dx) * 4
                XCTAssertEqual(
                    Array(out[to..<to + 4]), Array(sourcePixels[from..<from + 4]),
                    "方向 \(orientation)：原圖 (\(x),\(y)) 應在 (\(dx),\(dy))")
            }
        }
    }

    func testPortraitJPEGLoadsUpright() throws {
        let url = dir.file("portrait.jpg")
        try TestImages.write(markerImage(), as: .jpeg, to: url, orientation: 6, quality: 1)
        let loaded = try load(url).image.cgImage
        XCTAssertEqual(loaded.width, 32)
        XCTAssertEqual(loaded.height, 48)
        let marker = TestImages.pixel(loaded, x: 24, y: 8)  // 方向 6：左上角的標記轉到右上角
        XCTAssertGreaterThan(marker.r, 200)
        XCTAssertLessThan(marker.b, 80)
    }

    func testColorSpaceIsPreserved() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let source = TestImages.solid(width: 12, height: 12, colorSpace: p3, r: 0.9, g: 0.2, b: 0.1)
        let url = dir.file("p3.png")
        try TestImages.write(source, as: .png, to: url)
        let loaded = try load(url).image.cgImage
        XCTAssertEqual(loaded.colorSpace?.name as String?, CGColorSpace.displayP3 as String)
    }

    // MARK: 尺寸上限（FR-040）

    func testSideLimitIsInclusive() throws {
        for (w, h) in [(16384, 1), (1, 16384)] {
            let url = dir.file("edge-\(w)x\(h).png")
            try TestImages.write(TestImages.solid(width: w, height: h, r: 9, g: 9, b: 9), as: .png, to: url)
            let loaded = try load(url).image.cgImage
            XCTAssertEqual(loaded.width, w)
            XCTAssertEqual(loaded.height, h)
        }
    }

    func testSideOverTheLimitIsRejected() throws {
        for (w, h) in [(16385, 1), (1, 16385)] {
            let url = dir.file("over-\(w)x\(h).png")
            try TestImages.write(TestImages.solid(width: w, height: h, r: 9, g: 9, b: 9), as: .png, to: url)
            XCTAssertEqual(failure(of: url), .tooLarge(width: w, height: h))
        }
    }

    func testTotalPixelsOverTheLimitIsRejected() throws {
        // 14200 × 14200 = 201.64 百萬像素，每邊都在單邊上限內，只有總像素超標。
        let url = dir.file("huge.png")
        try TestImages.writeBlankGrayPNG(width: 14200, height: 14200, to: url)
        XCTAssertEqual(failure(of: url), .tooLarge(width: 14200, height: 14200))
    }

    func testRotatedOrientationSwapsDimensionsBeforeTheLimitCheck() throws {
        try XCTSkipUnless(TestImages.canEncode(.tiff))
        // 16384 × 2 的圖，方向 6 之後是 2 × 16384：仍在上限內，且尺寸對調。
        let url = dir.file("wide.tiff")
        try TestImages.write(TestImages.solid(width: 16384, height: 2, r: 1, g: 2, b: 3), as: .tiff, to: url, orientation: 6)
        let loaded = try load(url).image.cgImage
        XCTAssertEqual(loaded.width, 2)
        XCTAssertEqual(loaded.height, 16384)
    }

    // MARK: 不可匯入的輸入（FR-040、FR-045）

    func testDirectoryMissingPathAndRemoteURLAreNotFiles() throws {
        XCTAssertEqual(failure(of: try dir.subdirectory("folder")), .notAFile)
        XCTAssertEqual(failure(of: dir.file("nope.png")), .notAFile)
        XCTAssertEqual(failure(of: URL(string: "https://example.com/a.png")!), .notAFile)
    }

    func testTextFileWithImageExtensionIsUnsupportedFormat() throws {
        let url = dir.file("fake.png")
        try "這不是圖片".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(failure(of: url), .unsupportedFormat)
        let txt = dir.file("note.txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertEqual(failure(of: txt), .unsupportedFormat)
    }

    func testTruncatedPNGIsCorrupt() throws {
        let valid = dir.file("valid.png")
        try TestImages.write(TestImages.gradient(width: 200, height: 200), as: .png, to: valid)
        let broken = dir.file("broken.png")
        try TestImages.writeTruncatedCopy(of: valid, to: broken)
        XCTAssertEqual(failure(of: broken), .corrupt)
    }

    func testUnreadableFileIsReported() throws {
        try XCTSkipIf(getuid() == 0, "root 不受檔案權限限制")
        let url = dir.file("locked.png")
        try TestImages.write(TestImages.gradient(width: 10, height: 10), as: .png, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        XCTAssertEqual(failure(of: url), .unreadable)
    }

    // MARK: 原檔不被改動（FR-035、SC-010）

    func testSourceFileIsNeverModified() throws {
        let url = dir.file("keep.png")
        try TestImages.write(TestImages.gradient(width: 30, height: 30), as: .png, to: url)
        let before = try Data(contentsOf: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        _ = try load(url)
        _ = try load(url)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, modified)
    }

    func testFileNameIsReturnedAsIsForUnusualNames() throws {
        let names = ["我的 圖片 🌅.png", String(repeating: "長", count: 80) + ".png", "a b  c.PNG"]
        for name in names {
            let url = dir.file(name)
            try TestImages.write(TestImages.gradient(width: 8, height: 8), as: .png, to: url)
            XCTAssertEqual(try load(url).fileName, name)
        }
    }
}
