import UniformTypeIdentifiers
import XCTest
@testable import TracePixelsCore

/// SC-004：最高 5K 解析度、含 100 個標註的影像上，每個畫面更新耗時中位數不超過 33 毫秒，
/// 匯出（flatten）在 2 秒內完成。
/// SC-009、SC-012：匯入 12 百萬像素的截圖，核心步驟（解碼＋存入資料庫）在 700 毫秒內、高細節照片在 3 秒內；
/// 20 張一般大小的圖片在 10 秒內全部匯入。
final class PerformanceTests: XCTestCase {
    private let size = PixelSize(width: 5120, height: 2880)

    private func makeCapture() -> Capture {
        var annotations: [Annotation] = []
        for i in 0..<100 {
            let x = Double((i % 10) * 480 + 40), y = Double((i / 10) * 270 + 30)
            let style = Style(color: RGBAColor(r: Double(i % 3) / 2, g: Double(i % 5) / 4, b: 0.4), lineWidth: 6)
            let kind: Annotation.Kind
            switch i % 8 {
            case 0: kind = .arrow(start: PixelPoint(x: x, y: y), end: PixelPoint(x: x + 300, y: y + 120))
            case 1: kind = .rectangle(rect: PixelRect(x: x, y: y, width: 260, height: 140), filled: i % 16 == 1)
            case 2: kind = .ellipse(rect: PixelRect(x: x, y: y, width: 240, height: 140), filled: false)
            case 3: kind = .text(rect: PixelRect(x: x, y: y, width: 300, height: 60), string: "標註 \(i) Annotation")
            case 4: kind = .step(center: PixelPoint(x: x + 20, y: y + 20), number: i)
            case 5: kind = .pen(points: (0..<40).map { PixelPoint(x: x + Double($0) * 6, y: y + sin(Double($0) / 3) * 30) })
            case 6: kind = .highlighter(points: [PixelPoint(x: x, y: y), PixelPoint(x: x + 280, y: y + 10)])
            default: kind = .pixelate(rect: PixelRect(x: x, y: y, width: 200, height: 120), strength: 16)
            }
            annotations.append(Annotation(zIndex: i, kind: kind, style: style))
        }
        return Capture(createdAt: Date(timeIntervalSince1970: 0), source: .region, pixelSize: size, scale: 2, annotations: annotations)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func milliseconds(_ block: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    func testFrameRenderMedianIsWithin33Milliseconds() {
        let capture = makeCapture()
        XCTAssertEqual(capture.annotations.count, 100)
        let original = TestImages.make(width: size.width, height: size.height) { x, y in
            (UInt8(truncatingIfNeeded: x / 20), UInt8(truncatingIfNeeded: y / 11), 128, 255)
        }
        _ = Renderer.composite(capture, original: original)  // 暖機：字形與色彩空間快取
        let samples = (0..<30).map { _ in milliseconds { _ = Renderer.composite(capture, original: original) } }
        let result = median(samples)
        print("PERF 單次渲染中位數：\(String(format: "%.1f", result)) ms（上限 33 ms）；最小 \(String(format: "%.1f", samples.min()!)) ms")
        XCTAssertLessThanOrEqual(result, 33, "SC-004：單次渲染中位數應 ≤ 33 ms")
    }

    func testFlattenFinishesWithinTwoSeconds() throws {
        var capture = makeCapture()
        capture.finish = Finish(border: Finish.Border(color: .black, width: 8), shadow: Finish.Shadow(blurRadius: 20, offsetX: 0, offsetY: 8, color: RGBAColor(r: 0, g: 0, b: 0, a: 0.5)), cornerRadius: 24)
        let original = TestImages.solid(width: size.width, height: size.height, r: 200, g: 200, b: 200)
        let elapsed = try milliseconds { _ = try Renderer.flatten(capture, original: original) }
        print("PERF flatten（含邊框陰影圓角）：\(String(format: "%.0f", elapsed)) ms（上限 2000 ms）")
        XCTAssertLessThanOrEqual(elapsed, 2000)
    }

    // MARK: 匯入（SC-009、SC-012）

    private func importTwelveMegapixels(_ image: CGImage, as type: UTType, name: String) async throws -> (elapsed: Double, pixels: Int) {
        let dir = try TestDirectory()
        let url = dir.file(name)
        try TestImages.write(image, as: type, to: url, quality: 0.85)
        let store = LibraryStore(directory: try dir.subdirectory("library"))

        let start = DispatchTime.now().uptimeNanoseconds
        let loaded = try ImageImporter.load(from: url)
        _ = try await store.create(image: loaded.image, source: .imported(fileName: name), scale: 1)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return (elapsed, loaded.image.cgImage.width * loaded.image.cgImage.height)
    }

    /// 截圖類（大片純色、文字與介面元件）：PNG 編碼很快，核心步驟要在 700 毫秒內，為編輯器開啟留出餘裕。
    func testImportingATwelveMegapixelScreenshotStaysWithinTheBudget() async throws {
        let screenshot = TestImages.make(width: 4000, height: 3000) { x, y in
            if y < 80 { return (240, 240, 245, 255) }
            if x < 300 { return (30, 32, 38, 255) }
            if (x / 7 + y / 5) % 23 == 0 && y % 40 < 14 { return (20, 20, 20, 255) }
            return (250, 250, 252, 255)
        }
        let result = try await importTwelveMegapixels(screenshot, as: .png, name: "shot.png")
        print("PERF 匯入 12 百萬像素截圖（解碼＋存入資料庫）：\(String(format: "%.0f", result.elapsed)) ms（上限 700 ms）")
        XCTAssertEqual(result.pixels, 12_000_000)
        XCTAssertLessThanOrEqual(result.elapsed, 700)
    }

    /// 近乎雜訊的高細節照片幾乎無法壓縮，PNG 編碼是主要成本（見 research.md D-18），上限放寬為 3 秒；
    /// 超過 1 秒時 App 會顯示進度（FR-041）。
    func testImportingATwelveMegapixelNoisyPhotoStaysWithinThreeSeconds() async throws {
        let photo = TestImages.make(width: 4000, height: 3000) { x, y in
            let n = UInt8(truncatingIfNeeded: (x &* 31) ^ (y &* 17) ^ ((x &* y) >> 3))
            return (UInt8(truncatingIfNeeded: x / 16) &+ n / 8, UInt8(truncatingIfNeeded: y / 12) &+ n / 8, n, 255)
        }
        let result = try await importTwelveMegapixels(photo, as: .jpeg, name: "photo.jpg")
        print("PERF 匯入 12 百萬像素高細節照片（解碼＋存入資料庫）：\(String(format: "%.0f", result.elapsed)) ms（上限 3000 ms）")
        XCTAssertEqual(result.pixels, 12_000_000)
        XCTAssertLessThanOrEqual(result.elapsed, 3000)
    }

    func testImportingTwentyTypicalImagesFinishesWithinTenSeconds() async throws {
        let dir = try TestDirectory()
        var urls: [URL] = []
        for i in 0..<20 {
            let url = dir.file("shot-\(i).png")
            try TestImages.write(TestImages.gradient(width: 1600, height: 1000), as: .png, to: url)
            urls.append(url)
        }
        let importer = LibraryImporter(store: LibraryStore(directory: try dir.subdirectory("library")))

        let start = DispatchTime.now().uptimeNanoseconds
        let result = await importer.importFiles(urls)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        print("PERF 匯入 20 張 1600×1000 PNG：\(String(format: "%.0f", elapsed)) ms（上限 10000 ms）")
        XCTAssertEqual(result.imported.count, 20)
        XCTAssertLessThanOrEqual(elapsed, 10_000)
    }
}
