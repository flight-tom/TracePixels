import XCTest
@testable import SnagItCore

final class RendererTests: XCTestCase {
    private let size = PixelSize(width: 200, height: 100)

    private func white() -> CGImage {
        TestImages.solid(width: size.width, height: size.height, r: 255, g: 255, b: 255)
    }

    private func capture(_ annotations: [Annotation]) -> Capture {
        Capture(createdAt: Date(timeIntervalSince1970: 0), source: .region, pixelSize: size, scale: 1, annotations: annotations)
    }

    private func render(_ kinds: [Annotation.Kind], style: Style = Style(color: .black, lineWidth: 6)) -> CGImage {
        let items = kinds.enumerated().map { Annotation(zIndex: $0.offset, kind: $0.element, style: style) }
        return Renderer.composite(capture(items), original: white())
    }

    private func isWhite(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool { p.r > 250 && p.g > 250 && p.b > 250 }
    private func isDark(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool { p.r < 60 && p.g < 60 && p.b < 60 }

    // MARK: 各類型畫在預期位置（左上為原點）

    func testRectangleFilledPaintsInsideAndNotOutside() {
        let img = render([.rectangle(rect: PixelRect(x: 20, y: 10, width: 40, height: 30), filled: true)])
        XCTAssertTrue(isDark(TestImages.pixel(img, x: 40, y: 25)))
        XCTAssertTrue(isWhite(TestImages.pixel(img, x: 120, y: 25)))
        XCTAssertTrue(isWhite(TestImages.pixel(img, x: 40, y: 80)), "矩形在上方；下方不該有東西（驗證 y 軸方向）")
    }

    func testRectangleOutlineLeavesInteriorWhite() {
        let img = render([.rectangle(rect: PixelRect(x: 20, y: 10, width: 80, height: 60), filled: false)])
        XCTAssertTrue(isDark(TestImages.pixel(img, x: 20, y: 40)))
        XCTAssertTrue(isWhite(TestImages.pixel(img, x: 60, y: 40)))
    }

    func testLineAndArrowPaintAlongTheirPath() {
        let line = render([.line(start: PixelPoint(x: 10, y: 50), end: PixelPoint(x: 190, y: 50))])
        XCTAssertTrue(isDark(TestImages.pixel(line, x: 100, y: 50)))
        XCTAssertTrue(isWhite(TestImages.pixel(line, x: 100, y: 70)))

        let arrow = render([.arrow(start: PixelPoint(x: 10, y: 50), end: PixelPoint(x: 150, y: 50))])
        XCTAssertTrue(isDark(TestImages.pixel(arrow, x: 80, y: 50)))
        XCTAssertTrue(isDark(TestImages.pixel(arrow, x: 140, y: 50)), "箭頭頭部在終點附近")
        XCTAssertTrue(isWhite(TestImages.pixel(arrow, x: 175, y: 50)), "終點之後不該有東西")
    }

    func testEllipseFilledCoversCenterButNotBoundingBoxCorner() {
        let img = render([.ellipse(rect: PixelRect(x: 20, y: 10, width: 100, height: 60), filled: true)])
        XCTAssertTrue(isDark(TestImages.pixel(img, x: 70, y: 40)))
        XCTAssertTrue(isWhite(TestImages.pixel(img, x: 22, y: 12)))
    }

    func testPenAndHighlighter() {
        let pen = render([.pen(points: [PixelPoint(x: 10, y: 20), PixelPoint(x: 100, y: 20), PixelPoint(x: 100, y: 80)])])
        XCTAssertTrue(isDark(TestImages.pixel(pen, x: 50, y: 20)))
        XCTAssertTrue(isDark(TestImages.pixel(pen, x: 100, y: 60)))
        XCTAssertTrue(isWhite(TestImages.pixel(pen, x: 50, y: 60)))

        let hl = render([.highlighter(points: [PixelPoint(x: 10, y: 50), PixelPoint(x: 190, y: 50)])],
                        style: Style(color: .yellow, lineWidth: 8))
        let p = TestImages.pixel(hl, x: 100, y: 50)
        XCTAssertFalse(isWhite(p), "螢光筆有上色")
        XCTAssertGreaterThan(p.r, 200, "半透明：底下的白色仍透出來")
    }

    func testTextDrawsSomethingInsideItsRectOnly() {
        let img = render([.text(rect: PixelRect(x: 10, y: 10, width: 120, height: 40), string: "Hello")],
                         style: Style(color: .black, fontSize: 28))
        let pixels = TestImages.pixels(img)
        var inside = false, outside = false
        for y in 0..<size.height {
            for x in 0..<size.width where !(pixels[(y * size.width + x) * 4] > 250) {
                if (10..<130).contains(x) && (10..<50).contains(y) { inside = true } else { outside = true }
            }
        }
        XCTAssertTrue(inside)
        XCTAssertFalse(outside)
    }

    func testStepMarkerFillsCircleAtCenter() {
        let style = Style(color: .red, lineWidth: 4)
        let img = render([.step(center: PixelPoint(x: 100, y: 50), number: 3)], style: style)
        let edge = TestImages.pixel(img, x: 100 + Int(Annotation.stepRadius(for: style)) - 3, y: 50)
        XCTAssertGreaterThan(edge.r, 200)
        XCTAssertLessThan(edge.g, 80)
        XCTAssertTrue(isWhite(TestImages.pixel(img, x: 100 + Int(Annotation.stepRadius(for: style)) + 6, y: 50)))
    }

    func testHigherZIndexDrawsOnTop() {
        let red = Style(color: RGBAColor(r: 1, g: 0, b: 0), lineWidth: 2)
        let blue = Style(color: RGBAColor(r: 0, g: 0, b: 1), lineWidth: 2)
        let a = Annotation(zIndex: 0, kind: .rectangle(rect: PixelRect(x: 10, y: 10, width: 60, height: 60), filled: true), style: red)
        let b = Annotation(zIndex: 1, kind: .rectangle(rect: PixelRect(x: 40, y: 20, width: 60, height: 60), filled: true), style: blue)
        let img = Renderer.composite(capture([b, a]), original: white())  // 傳入順序與 zIndex 無關
        let overlap = TestImages.pixel(img, x: 55, y: 40)
        XCTAssertGreaterThan(overlap.b, 200)
        XCTAssertLessThan(overlap.r, 60)
    }

    // MARK: SC-006 畫面與匯出一致

    func testDrawIntoContextMatchesCompositeAndFlatten() throws {
        let items = [
            Annotation(zIndex: 0, kind: .arrow(start: PixelPoint(x: 10, y: 10), end: PixelPoint(x: 150, y: 70)), style: Style()),
            Annotation(zIndex: 1, kind: .text(rect: PixelRect(x: 20, y: 60, width: 100, height: 30), string: "你好"), style: Style(color: .black)),
            Annotation(zIndex: 2, kind: .pixelate(rect: PixelRect(x: 120, y: 10, width: 64, height: 32), strength: 8)),
        ]
        let c = capture(items)
        let original = TestImages.gradient(width: size.width, height: size.height)

        // CoreGraphics 的字形快取讓「同一字型與大小的第一次繪製」與之後的結果在邊緣像素上有細微差異；
        // 先繪製一次讓快取就緒，才能逐像素比對。實際使用時畫布早已重繪過多次，匯出看到的是同一份快取。
        _ = Renderer.composite(c, original: original)

        let composite = TestImages.pixels(Renderer.composite(c, original: original))
        let flattened = TestImages.pixels(try Renderer.flatten(c, original: original))
        XCTAssertEqual(flattened, composite)

        var data = [UInt8](repeating: 0, count: size.width * size.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: size.width * 4, space: TestImages.colorSpace, bitmapInfo: TestImages.bitmapInfo)!
            Renderer.draw(c, original: original, into: ctx)
        }
        XCTAssertEqual(data, composite)
    }

    func testRenderingNeverModifiesTheOriginalImage() throws {
        let original = TestImages.gradient(width: size.width, height: size.height)
        let before = TestImages.pixels(original)
        let c = capture([
            Annotation(zIndex: 0, kind: .rectangle(rect: PixelRect(x: 0, y: 0, width: 200, height: 100), filled: true)),
            Annotation(zIndex: 1, kind: .blur(rect: PixelRect(x: 0, y: 0, width: 200, height: 100), strength: 16)),
        ])
        _ = Renderer.composite(c, original: original)
        _ = try Renderer.flatten(c, original: original)
        XCTAssertEqual(TestImages.pixels(original), before)
    }
}
