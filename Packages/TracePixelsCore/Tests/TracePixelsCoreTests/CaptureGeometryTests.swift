import XCTest
@testable import TracePixelsCore

final class CaptureGeometryTests: XCTestCase {
    // 全域點座標、左上為原點；主螢幕在原點，第二個螢幕接在右邊。
    private let main = DisplayInfo(id: 1, frame: PixelRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private let side = DisplayInfo(id: 2, frame: PixelRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1)

    private func select(_ a: (Double, Double), _ b: (Double, Double)) -> RegionSelection? {
        CaptureGeometry.selection(
            from: PixelPoint(x: a.0, y: a.1), to: PixelPoint(x: b.0, y: b.1), displays: [main, side])
    }

    func testSimpleSelectionOnRetinaDisplay() {
        let s = select((100, 100), (300, 250))
        XCTAssertEqual(s?.displayID, 1)
        XCTAssertEqual(s?.sourceRect, PixelRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(s?.pixelSize, PixelSize(width: 400, height: 300))
    }

    func testReversedDragGivesSameSelection() {
        XCTAssertEqual(select((300, 250), (100, 100)), select((100, 100), (300, 250)))
    }

    func testSelectionOnSecondDisplayIsDisplayLocal() {
        let s = select((1500, 100), (1700, 200))
        XCTAssertEqual(s?.displayID, 2)
        XCTAssertEqual(s?.sourceRect, PixelRect(x: 60, y: 100, width: 200, height: 100))
        XCTAssertEqual(s?.pixelSize, PixelSize(width: 200, height: 100))
    }

    func testSelectionIsClampedToDisplayWhereDragStarted() {
        // 起點在主螢幕，終點拖進第二個螢幕：只保留主螢幕內的部分。
        let s = select((1400, 100), (1600, 200))
        XCTAssertEqual(s?.displayID, 1)
        XCTAssertEqual(s?.sourceRect, PixelRect(x: 1400, y: 100, width: 40, height: 100))
    }

    func testSelectionDraggedOutOfTopLeftIsClamped() {
        let s = select((50, 60), (-100, -100))
        XCTAssertEqual(s?.sourceRect, PixelRect(x: 0, y: 0, width: 50, height: 60))
    }

    func testStartOutsideAllDisplaysGivesNil() {
        XCTAssertNil(select((-500, -500), (10, 10)))
    }

    func testSelectionSmallerThanOnePointGivesNil() {
        XCTAssertNil(select((100, 100), (100.4, 300)))
        XCTAssertNil(select((100, 100), (100, 100)))
    }

    func testPixelSizeRoundsToNearestPixel() {
        // 10.25 點 × 2 = 20.5 像素 → 四捨五入為 21
        let s = select((0, 0), (10.25, 5))
        XCTAssertEqual(s?.pixelSize.width, 21)
        XCTAssertEqual(s?.pixelSize.height, 10)
    }

    func testDisplayContainingPoint() {
        XCTAssertEqual(CaptureGeometry.display(containing: PixelPoint(x: 10, y: 10), in: [main, side])?.id, 1)
        XCTAssertEqual(CaptureGeometry.display(containing: PixelPoint(x: 1440, y: 10), in: [main, side])?.id, 2)
        XCTAssertNil(CaptureGeometry.display(containing: PixelPoint(x: 9999, y: 9999), in: [main, side]))
    }

    func testFullDisplayPixelSize() {
        XCTAssertEqual(CaptureGeometry.pixelSize(of: main), PixelSize(width: 2880, height: 1800))
        XCTAssertEqual(CaptureGeometry.pixelSize(of: side), PixelSize(width: 1920, height: 1080))
    }

    // MARK: 擷取倍率必須是顯示器的倍率，不能由「像素 ÷ 點」反推

    func testSelectionCarriesTheDisplayScaleExactly() {
        XCTAssertEqual(select((100, 100), (300, 250))?.scale, 2)
        XCTAssertEqual(select((1500, 100), (1700, 200))?.scale, 1)
    }

    func testScaleStaysExactEvenWhenPixelRoundingWouldSkewTheRatio() throws {
        // 寬 486.6 點 × 2 = 973.2 像素，四捨五入為 973；973 ÷ 486.6 ≈ 1.9996，不是 2。
        let s = try XCTUnwrap(select((100, 100), (586.6, 400)))
        XCTAssertEqual(s.pixelSize.width, 973)
        XCTAssertNotEqual(Double(s.pixelSize.width) / s.sourceRect.width, 2, "反推的倍率會有誤差")
        XCTAssertEqual(s.scale, 2, "但記錄的倍率必須是顯示器的 2.0")
    }

    func testSelectionScaleFollowsEachDisplayInAMixedScaleSetup() {
        let retina = DisplayInfo(id: 1, frame: PixelRect(x: 0, y: 0, width: 1000, height: 800), scale: 2)
        let external = DisplayInfo(id: 2, frame: PixelRect(x: 1000, y: 0, width: 1000, height: 800), scale: 1.5)
        let a = CaptureGeometry.selection(from: PixelPoint(x: 10, y: 10), to: PixelPoint(x: 99.3, y: 77.7), displays: [retina, external])
        let b = CaptureGeometry.selection(from: PixelPoint(x: 1010, y: 10), to: PixelPoint(x: 1099.3, y: 77.7), displays: [retina, external])
        XCTAssertEqual(a?.scale, 2)
        XCTAssertEqual(b?.scale, 1.5)
    }
}
