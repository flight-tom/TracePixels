import XCTest
@testable import TracePixelsCore

/// SC-004：最高 5K 解析度、含 100 個標註的影像上，每個畫面更新耗時中位數不超過 33 毫秒，
/// 匯出（flatten）在 2 秒內完成。
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
}
