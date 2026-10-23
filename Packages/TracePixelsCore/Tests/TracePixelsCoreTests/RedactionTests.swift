import XCTest
@testable import TracePixelsCore

final class RedactionTests: XCTestCase {
    private let size = PixelSize(width: 96, height: 64)

    private func capture(_ annotations: [Annotation]) -> Capture {
        Capture(createdAt: Date(timeIntervalSince1970: 0), source: .region, pixelSize: size, scale: 1, annotations: annotations)
    }

    /// 棋盤：兩色平均後恰為 128，因此任何 8×8 整磚的平均值都相同。
    private func checker(phase: Int = 0) -> CGImage {
        TestImages.make(width: size.width, height: size.height) { x, y in
            let v: UInt8 = (x + y + phase) % 2 == 0 ? 100 : 156
            return (v, v, v, 255)
        }
    }

    private func flat() -> CGImage {
        TestImages.solid(width: size.width, height: size.height, r: 128, g: 128, b: 128)
    }

    /// 只取區域內的像素：區域外兩張原圖本來就不同，不在比較範圍內。
    private func inside(_ pixels: [UInt8], _ region: PixelRect) -> [UInt8] {
        var out: [UInt8] = []
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let i = (y * size.width + x) * 4
                out += pixels[i..<i + 4]
            }
        }
        return out
    }

    private func redact(_ kind: Annotation.Kind, over image: CGImage) -> [UInt8] {
        let c = capture([Annotation(zIndex: 0, kind: kind)])
        return TestImages.pixels(Renderer.composite(c, original: image))
    }

    // MARK: SC-005 不可還原

    func testPixelateOutputDependsOnlyOnTileMeans() {
        let region = PixelRect(x: 5, y: 3, width: 40, height: 24)
        let kind = Annotation.Kind.pixelate(rect: region, strength: 8)
        // 兩張圖在每個磁磚內的細節完全不同（純色 vs 棋盤），磁磚平均值相同。
        let reference = inside(redact(kind, over: flat()), region)
        XCTAssertEqual(inside(redact(kind, over: checker()), region), reference)
        XCTAssertEqual(inside(redact(kind, over: checker(phase: 1)), region), reference)
    }

    func testBlurOutputDependsOnlyOnTileMeans() {
        let region = PixelRect(x: 5, y: 3, width: 40, height: 24)
        let kind = Annotation.Kind.blur(rect: region, strength: 8)
        XCTAssertEqual(inside(redact(kind, over: checker()), region), inside(redact(kind, over: flat()), region))
    }

    func testRedactionActuallyChangesTheOriginalDetail() {
        let kind = Annotation.Kind.pixelate(rect: PixelRect(x: 0, y: 0, width: 32, height: 32), strength: 8)
        let original = TestImages.pixels(checker())
        XCTAssertNotEqual(redact(kind, over: checker()), original)
    }

    func testStrengthBelowMinimumUsesEightPixelTiles() {
        // 強度 2 會被提升為 8；所以結果與強度 8 相同。
        let region = PixelRect(x: 0, y: 0, width: 32, height: 32)
        let gradient = TestImages.gradient(width: size.width, height: size.height)
        XCTAssertEqual(
            redact(.pixelate(rect: region, strength: 2), over: gradient),
            redact(.pixelate(rect: region, strength: 8), over: gradient))
    }

    func testPixelateMakesEveryTileUniform() {
        let gradient = TestImages.gradient(width: size.width, height: size.height)
        let region = PixelRect(x: 0, y: 0, width: 32, height: 32)
        let out = redact(.pixelate(rect: region, strength: 8), over: gradient)
        for ty in 0..<4 {
            for tx in 0..<4 {
                let first = (ty * 8 * size.width + tx * 8) * 4
                for dy in 0..<8 {
                    for dx in 0..<8 {
                        let i = ((ty * 8 + dy) * size.width + tx * 8 + dx) * 4
                        XCTAssertEqual(Array(out[i..<i + 4]), Array(out[first..<first + 4]), "磚 (\(tx),\(ty)) 像素 (\(dx),\(dy))")
                    }
                }
            }
        }
    }

    func testPixelsOutsideTheRegionAreUntouched() {
        let gradient = TestImages.gradient(width: size.width, height: size.height)
        let original = TestImages.pixels(gradient)
        let out = redact(.blur(rect: PixelRect(x: 20, y: 20, width: 16, height: 16), strength: 8), over: gradient)
        for y in 0..<size.height {
            for x in 0..<size.width where !(20..<36).contains(x) || !(20..<36).contains(y) {
                let i = (y * size.width + x) * 4
                XCTAssertEqual(Array(out[i..<i + 4]), Array(original[i..<i + 4]))
            }
        }
    }

    func testRegionOutsideImageIsClippedWithoutCrashing() {
        let kind = Annotation.Kind.pixelate(rect: PixelRect(x: -20, y: -20, width: 400, height: 400), strength: 16)
        let out = redact(kind, over: checker())
        XCTAssertEqual(out.count, size.width * size.height * 4)
    }

    // MARK: 遮蔽也蓋住它下方的標註

    func testRedactionAlsoObscuresAnnotationsBelowIt() {
        let base = TestImages.solid(width: size.width, height: size.height, r: 255, g: 255, b: 255)
        let arrow = Annotation(zIndex: 0, kind: .line(start: PixelPoint(x: 0, y: 16), end: PixelPoint(x: 95, y: 16)),
                               style: Style(color: .black, lineWidth: 2))
        let cover = Annotation(zIndex: 1, kind: .pixelate(rect: PixelRect(x: 0, y: 0, width: 96, height: 32), strength: 32))
        let plain = TestImages.pixels(Renderer.composite(capture([arrow]), original: base))
        let covered = TestImages.pixels(Renderer.composite(capture([arrow, cover]), original: base))
        // 沒遮蔽時線上的像素是黑的；遮蔽之後該列變成與磁磚平均一致的淺灰，不再是黑色。
        let i = (16 * size.width + 48) * 4
        XCTAssertLessThan(plain[i], 40)
        XCTAssertGreaterThan(covered[i], 200)
    }
}
