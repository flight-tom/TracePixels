import XCTest
@testable import SnagItCore

final class DraftShapeTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> PixelPoint { PixelPoint(x: x, y: y) }

    func testPlainDragsProduceMatchingKinds() {
        XCTAssertEqual(DraftShape.arrow.kind(from: p(1, 2), to: p(30, 40)), .arrow(start: p(1, 2), end: p(30, 40)))
        XCTAssertEqual(DraftShape.line.kind(from: p(1, 2), to: p(30, 40)), .line(start: p(1, 2), end: p(30, 40)))
        XCTAssertEqual(
            DraftShape.rectangle.kind(from: p(50, 40), to: p(10, 10)),
            .rectangle(rect: PixelRect(x: 10, y: 10, width: 40, height: 30), filled: false))
        XCTAssertEqual(
            DraftShape.ellipse.kind(from: p(0, 0), to: p(20, 10)),
            .ellipse(rect: PixelRect(x: 0, y: 0, width: 20, height: 10), filled: false))
        XCTAssertEqual(
            DraftShape.text.kind(from: p(5, 5), to: p(105, 45)),
            .text(rect: PixelRect(x: 5, y: 5, width: 100, height: 40), string: ""))
    }

    func testRedactionDraftsUseDefaultStrengthAtLeastTheMinimum() {
        guard case let .blur(_, blurStrength) = DraftShape.blur.kind(from: p(0, 0), to: p(40, 40)),
              case let .pixelate(_, pixelateStrength) = DraftShape.pixelate.kind(from: p(0, 0), to: p(40, 40))
        else { return XCTFail("應該產生 blur 與 pixelate") }
        XCTAssertGreaterThanOrEqual(blurStrength, Annotation.minimumRedactionStrength)
        XCTAssertGreaterThanOrEqual(pixelateStrength, Annotation.minimumRedactionStrength)
    }

    func testConstrainedLineSnapsToMultiplesOf45DegreesKeepingLength() {
        for end in [p(100, 10), p(60, 50), p(5, 90), p(-80, 20), p(-30, -35)] {
            guard case let .line(start, snapped) = DraftShape.line.kind(from: p(0, 0), to: end, constrain: true) else {
                return XCTFail("應該是 line")
            }
            let length = hypot(snapped.x - start.x, snapped.y - start.y)
            XCTAssertEqual(length, hypot(end.x, end.y), accuracy: 1e-9)
            let angle = atan2(snapped.y, snapped.x) / (.pi / 4)
            XCTAssertEqual(angle, angle.rounded(), accuracy: 1e-9, "角度應為 45° 的整數倍：\(end)")
        }
    }

    func testConstrainedRectangleBecomesASquareInTheDragDirection() {
        XCTAssertEqual(
            DraftShape.rectangle.kind(from: p(0, 0), to: p(50, 30), constrain: true),
            .rectangle(rect: PixelRect(x: 0, y: 0, width: 50, height: 50), filled: false))
        XCTAssertEqual(
            DraftShape.ellipse.kind(from: p(0, 0), to: p(-50, 30), constrain: true),
            .ellipse(rect: PixelRect(x: -50, y: 0, width: 50, height: 50), filled: false))
        XCTAssertEqual(
            DraftShape.ellipse.kind(from: p(10, 10), to: p(0, -40), constrain: true),
            .ellipse(rect: PixelRect(x: -40, y: -40, width: 50, height: 50), filled: false))
    }

    func testNegligibleDetectsAccidentalClicks() {
        XCTAssertTrue(DraftShape.arrow.kind(from: p(5, 5), to: p(6, 6)).isNegligible)
        XCTAssertFalse(DraftShape.arrow.kind(from: p(5, 5), to: p(40, 40)).isNegligible)
        XCTAssertTrue(DraftShape.rectangle.kind(from: p(5, 5), to: p(7, 6)).isNegligible)
        XCTAssertFalse(DraftShape.rectangle.kind(from: p(5, 5), to: p(40, 6)).isNegligible)
        XCTAssertTrue(Annotation.Kind.pen(points: [p(1, 1)]).isNegligible)
        XCTAssertFalse(Annotation.Kind.pen(points: [p(1, 1), p(20, 20)]).isNegligible)
        XCTAssertFalse(Annotation.Kind.step(center: p(0, 0), number: 1).isNegligible)
    }
}
