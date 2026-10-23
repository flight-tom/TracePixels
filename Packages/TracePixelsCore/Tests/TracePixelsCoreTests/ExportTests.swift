import ImageIO
import XCTest
@testable import TracePixelsCore

final class ExportTests: XCTestCase {
    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func testFileExtensions() {
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.jpeg(quality: 0.9).fileExtension, "jpg")
    }

    func testPNGRoundTripIsLossless() throws {
        let image = TestImages.gradient(width: 64, height: 48)
        let data = try Renderer.encode(image, as: .png)
        let decoded = try XCTUnwrap(decode(data))
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        XCTAssertEqual(TestImages.pixels(decoded), TestImages.pixels(image))
    }

    func testJPEGKeepsDimensionsAndLowerQualityIsSmaller() throws {
        let image = TestImages.gradient(width: 200, height: 150)
        let high = try Renderer.encode(image, as: .jpeg(quality: 0.95))
        let low = try Renderer.encode(image, as: .jpeg(quality: 0.2))
        XCTAssertEqual(try XCTUnwrap(decode(high)).width, 200)
        XCTAssertEqual(try XCTUnwrap(decode(low)).height, 150)
        XCTAssertLessThan(low.count, high.count)
    }

    func testJPEGFlattensTransparencyOntoWhite() throws {
        let transparent = TestImages.make(width: 32, height: 32) { _, _ in (0, 0, 0, 0) }
        let data = try Renderer.encode(transparent, as: .jpeg(quality: 0.9))
        let p = TestImages.pixel(try XCTUnwrap(decode(data)), x: 16, y: 16)
        XCTAssertGreaterThan(p.r, 245)
        XCTAssertGreaterThan(p.g, 245)
        XCTAssertGreaterThan(p.b, 245)
    }

    func testQualityOutsideZeroToOneIsClamped() throws {
        let image = TestImages.gradient(width: 32, height: 32)
        XCTAssertNoThrow(try Renderer.encode(image, as: .jpeg(quality: 5)))
        XCTAssertNoThrow(try Renderer.encode(image, as: .jpeg(quality: -1)))
    }

    func testExportedPNGContainsTheFlattenedAnnotations() throws {
        let base = TestImages.solid(width: 100, height: 60, r: 255, g: 255, b: 255)
        let rect = Annotation(
            zIndex: 0, kind: .rectangle(rect: PixelRect(x: 10, y: 10, width: 40, height: 30), filled: true),
            style: Style(color: RGBAColor(r: 0, g: 0, b: 1), lineWidth: 2))
        let capture = Capture(
            createdAt: Date(timeIntervalSince1970: 0), source: .region,
            pixelSize: PixelSize(width: 100, height: 60), scale: 1, annotations: [rect])
        let data = try Renderer.encode(try Renderer.flatten(capture, original: base), as: .png)
        let decoded = try XCTUnwrap(decode(data))
        let inside = TestImages.pixel(decoded, x: 30, y: 25)
        let outside = TestImages.pixel(decoded, x: 80, y: 25)
        XCTAssertGreaterThan(inside.b, 200)
        XCTAssertLessThan(inside.r, 60)
        XCTAssertGreaterThan(outside.r, 250)
    }
}
