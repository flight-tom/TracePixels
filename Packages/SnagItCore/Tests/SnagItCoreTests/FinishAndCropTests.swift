import XCTest
@testable import SnagItCore

final class FinishAndCropTests: XCTestCase {
    private let size = PixelSize(width: 200, height: 100)

    private func white() -> CGImage { TestImages.solid(width: size.width, height: size.height, r: 255, g: 255, b: 255) }

    private func capture(_ annotations: [Annotation] = [], configure: (inout Capture) -> Void = { _ in }) -> Capture {
        var c = Capture(createdAt: Date(timeIntervalSince1970: 0), source: .region, pixelSize: size, scale: 1, annotations: annotations)
        configure(&c)
        return c
    }

    private let redStyle = Style(color: RGBAColor(r: 1, g: 0, b: 0), lineWidth: 2)

    private func redRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Annotation {
        Annotation(zIndex: 0, kind: .rectangle(rect: PixelRect(x: x, y: y, width: w, height: h), filled: true), style: redStyle)
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }

    private func containsRed(_ image: CGImage) -> Bool {
        let px = TestImages.pixels(image)
        return stride(from: 0, to: px.count, by: 4).contains { px[$0] > 200 && px[$0 + 1] < 60 && px[$0 + 2] < 60 }
    }

    // MARK: 驗證規則

    func testCropMustStayInsideTheImageAndBeAtLeastOnePixel() {
        XCTAssertNoThrow(try capture { $0.crop = PixelRect(x: 0, y: 0, width: 200, height: 100) }.validate())
        XCTAssertThrowsError(try capture { $0.crop = PixelRect(x: 150, y: 0, width: 100, height: 50) }.validate())
        XCTAssertThrowsError(try capture { $0.crop = PixelRect(x: 0, y: 0, width: 0.4, height: 50) }.validate())
    }

    func testOutputScaleIsClampedBetweenPointOneAndFour() {
        XCTAssertEqual(capture { $0.outputScale = 0 }.outputScale, 0.1)
        XCTAssertEqual(capture { $0.outputScale = 99 }.outputScale, 4.0)
        XCTAssertEqual(capture { $0.outputScale = 2.5 }.outputScale, 2.5)
    }

    // MARK: 裁切

    func testFlattenSizeEqualsTheCropRect() throws {
        let out = try Renderer.flatten(capture { $0.crop = PixelRect(x: 100, y: 50, width: 80, height: 40) }, original: white())
        XCTAssertEqual(out.width, 80)
        XCTAssertEqual(out.height, 40)
    }

    func testCropKeepsVisibleAnnotationsAndDropsOutsideOnes() throws {
        let c = capture([redRect(150, 70, 30, 20)]) { $0.crop = PixelRect(x: 100, y: 50, width: 100, height: 50) }
        let inside = try Renderer.flatten(c, original: white())
        XCTAssertTrue(isRed(TestImages.pixel(inside, x: 65, y: 30)), "裁切後座標會位移：(165,80) → (65,30)")

        let outside = capture([redRect(10, 10, 30, 30)]) { $0.crop = PixelRect(x: 100, y: 50, width: 100, height: 50) }
        XCTAssertFalse(containsRed(try Renderer.flatten(outside, original: white())))
    }

    func testPartiallyOverlappingAnnotationIsClippedByTheCrop() throws {
        let c = capture([redRect(80, 40, 60, 40)]) { $0.crop = PixelRect(x: 100, y: 50, width: 100, height: 50) }
        let out = try Renderer.flatten(c, original: white())
        XCTAssertTrue(isRed(TestImages.pixel(out, x: 10, y: 10)))   // 原圖 (110,60)，矩形內
        XCTAssertFalse(isRed(TestImages.pixel(out, x: 60, y: 10)))  // 原圖 (160,60)，矩形之外
    }

    // MARK: 縮放

    func testOutputScaleResizesTheResult() throws {
        let double = try Renderer.flatten(capture { $0.outputScale = 2 }, original: white())
        XCTAssertEqual(double.width, 400); XCTAssertEqual(double.height, 200)
        let half = try Renderer.flatten(capture { $0.outputScale = 0.5 }, original: white())
        XCTAssertEqual(half.width, 100); XCTAssertEqual(half.height, 50)
    }

    func testCropThenScale() throws {
        let c = capture { $0.crop = PixelRect(x: 0, y: 0, width: 50, height: 30); $0.outputScale = 3 }
        let out = try Renderer.flatten(c, original: white())
        XCTAssertEqual(out.width, 150); XCTAssertEqual(out.height, 90)
    }

    func testScaledResultNeverCollapsesBelowOnePixel() throws {
        let tiny = capture { $0.crop = PixelRect(x: 0, y: 0, width: 3, height: 3); $0.outputScale = 0.1 }
        let out = try Renderer.flatten(tiny, original: white())
        XCTAssertGreaterThanOrEqual(out.width, 1); XCTAssertGreaterThanOrEqual(out.height, 1)
    }

    // MARK: 邊框、陰影、圓角

    func testBorderAddsItsWidthOnEverySide() throws {
        let finish = Finish(border: Finish.Border(color: RGBAColor(r: 0, g: 0, b: 1), width: 6))
        let out = try Renderer.flatten(capture { $0.finish = finish }, original: white())
        XCTAssertEqual(out.width, 212); XCTAssertEqual(out.height, 112)
        let edge = TestImages.pixel(out, x: 2, y: 50)
        XCTAssertGreaterThan(edge.b, 200); XCTAssertLessThan(edge.r, 60)
        let center = TestImages.pixel(out, x: 106, y: 56)
        XCTAssertGreaterThan(center.r, 250)
    }

    func testShadowAddsAMarginWithSoftTransparency() throws {
        let shadow = Finish.Shadow(blurRadius: 10, offsetX: 0, offsetY: 8, color: RGBAColor(r: 0, g: 0, b: 0, a: 0.6))
        let finish = Finish(shadow: shadow)
        let margin = finish.margin
        XCTAssertGreaterThan(margin, 0)
        let out = try Renderer.flatten(capture { $0.finish = finish }, original: white())
        XCTAssertEqual(out.width, 200 + 2 * margin); XCTAssertEqual(out.height, 100 + 2 * margin)

        XCTAssertEqual(TestImages.pixel(out, x: 0, y: 0).a, 0, "最外側的角落完全透明")
        let below = TestImages.pixel(out, x: out.width / 2, y: margin + 100 + 3)    // 圖下緣外 3 像素
        let above = TestImages.pixel(out, x: out.width / 2, y: margin - 4)           // 圖上緣外 3 像素
        XCTAssertGreaterThan(below.a, 0, "陰影有投射到下方")
        XCTAssertGreaterThan(below.a, above.a, "offsetY 為正代表陰影往下")
        XCTAssertEqual(TestImages.pixel(out, x: out.width / 2, y: out.height / 2).a, 255)
    }

    func testCornerRadiusMakesTheCornersTransparent() throws {
        let out = try Renderer.flatten(capture { $0.finish = Finish(cornerRadius: 20) }, original: white())
        XCTAssertEqual(out.width, 200); XCTAssertEqual(out.height, 100)
        XCTAssertEqual(TestImages.pixel(out, x: 0, y: 0).a, 0)
        XCTAssertEqual(TestImages.pixel(out, x: 199, y: 99).a, 0)
        XCTAssertEqual(TestImages.pixel(out, x: 100, y: 50).a, 255)
        XCTAssertEqual(TestImages.pixel(out, x: 100, y: 0).a, 255, "邊的中央不受圓角影響")
    }

    func testDefaultFinishChangesNothing() throws {
        let c = capture([redRect(10, 10, 30, 30)])
        XCTAssertEqual(
            TestImages.pixels(try Renderer.flatten(c, original: white())),
            TestImages.pixels(Renderer.composite(c, original: white())))
        XCTAssertEqual(Finish.none.margin, 0)
    }

    // MARK: 非破壞性

    func testFlattenDoesNotChangeTheCaptureOrTheOriginal() throws {
        let original = TestImages.gradient(width: size.width, height: size.height)
        let before = TestImages.pixels(original)
        let c = capture([redRect(10, 10, 30, 30)]) {
            $0.crop = PixelRect(x: 5, y: 5, width: 100, height: 50)
            $0.outputScale = 2
            $0.finish = Finish(border: Finish.Border(color: .black, width: 4), shadow: Finish.Shadow(blurRadius: 6, offsetX: 2, offsetY: 2, color: .black), cornerRadius: 8)
        }
        let snapshot = c
        _ = try Renderer.flatten(c, original: original)
        XCTAssertEqual(c, snapshot)
        XCTAssertEqual(TestImages.pixels(original), before)
    }
}
