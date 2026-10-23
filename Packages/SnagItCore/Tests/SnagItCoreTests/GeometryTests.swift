import XCTest
@testable import SnagItCore

final class GeometryTests: XCTestCase {
    func testNormalizedFlipsNegativeWidthAndHeight() {
        let r = PixelRect(x: 100, y: 80, width: -40, height: -30).normalized
        XCTAssertEqual(r, PixelRect(x: 60, y: 50, width: 40, height: 30))
    }

    func testNormalizedKeepsPositiveRect() {
        let r = PixelRect(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(r.normalized, r)
    }

    func testEdges() {
        let r = PixelRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(r.minX, 10); XCTAssertEqual(r.maxX, 40)
        XCTAssertEqual(r.minY, 20); XCTAssertEqual(r.maxY, 60)
        XCTAssertEqual(r.center, PixelPoint(x: 25, y: 40))
    }

    func testContainsPoint() {
        let r = PixelRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(r.contains(PixelPoint(x: 5, y: 5)))
        XCTAssertTrue(r.contains(PixelPoint(x: 0, y: 10)))
        XCTAssertFalse(r.contains(PixelPoint(x: 10.1, y: 5)))
    }

    func testIntersection() {
        let a = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let b = PixelRect(x: 5, y: 5, width: 10, height: 10)
        XCTAssertEqual(a.intersection(b), PixelRect(x: 5, y: 5, width: 5, height: 5))
        XCTAssertNil(a.intersection(PixelRect(x: 20, y: 20, width: 1, height: 1)))
    }

    func testUnion() {
        let a = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let b = PixelRect(x: 5, y: 5, width: 10, height: 10)
        XCTAssertEqual(a.union(b), PixelRect(x: 0, y: 0, width: 15, height: 15))
    }

    func testClampedToBounds() {
        let bounds = PixelRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(
            PixelRect(x: -10, y: 90, width: 50, height: 50).clamped(to: bounds),
            PixelRect(x: 0, y: 90, width: 40, height: 10))
        XCTAssertNil(PixelRect(x: 200, y: 200, width: 5, height: 5).clamped(to: bounds))
    }

    func testRectFromTwoPoints() {
        let r = PixelRect(from: PixelPoint(x: 50, y: 60), to: PixelPoint(x: 10, y: 20))
        XCTAssertEqual(r, PixelRect(x: 10, y: 20, width: 40, height: 40))
    }

    func testPixelSizeRect() {
        XCTAssertEqual(PixelSize(width: 640, height: 480).rect, PixelRect(x: 0, y: 0, width: 640, height: 480))
    }
}
