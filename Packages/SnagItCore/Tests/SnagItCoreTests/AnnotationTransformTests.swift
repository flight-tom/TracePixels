import XCTest
@testable import SnagItCore

final class AnnotationTransformTests: XCTestCase {
    private let r = PixelRect(x: 10, y: 20, width: 100, height: 50)

    func testTranslateMovesEveryKind() {
        let dx = 5.0, dy = -3.0
        XCTAssertEqual(
            Annotation.Kind.arrow(start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 10, y: 10)).translated(dx: dx, dy: dy),
            .arrow(start: PixelPoint(x: 5, y: -3), end: PixelPoint(x: 15, y: 7)))
        XCTAssertEqual(
            Annotation.Kind.rectangle(rect: r, filled: true).translated(dx: dx, dy: dy),
            .rectangle(rect: PixelRect(x: 15, y: 17, width: 100, height: 50), filled: true))
        XCTAssertEqual(
            Annotation.Kind.pen(points: [PixelPoint(x: 1, y: 1), PixelPoint(x: 2, y: 2)]).translated(dx: dx, dy: dy),
            .pen(points: [PixelPoint(x: 6, y: -2), PixelPoint(x: 7, y: -1)]))
        XCTAssertEqual(
            Annotation.Kind.step(center: PixelPoint(x: 50, y: 50), number: 4).translated(dx: dx, dy: dy),
            .step(center: PixelPoint(x: 55, y: 47), number: 4))
        XCTAssertEqual(
            Annotation.Kind.text(rect: r, string: "hi").translated(dx: dx, dy: dy),
            .text(rect: PixelRect(x: 15, y: 17, width: 100, height: 50), string: "hi"))
        XCTAssertEqual(
            Annotation.Kind.blur(rect: r, strength: 16).translated(dx: dx, dy: dy),
            .blur(rect: PixelRect(x: 15, y: 17, width: 100, height: 50), strength: 16))
    }

    func testAvailableHandlesPerKind() {
        XCTAssertEqual(Set(Annotation.Kind.rectangle(rect: r, filled: false).handles).count, 8)
        XCTAssertEqual(Set(Annotation.Kind.blur(rect: r, strength: 8).handles).count, 8)
        XCTAssertEqual(Annotation.Kind.arrow(start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 1, y: 1)).handles, [.start, .end])
        XCTAssertTrue(Annotation.Kind.step(center: PixelPoint(x: 0, y: 0), number: 1).handles.isEmpty)
        XCTAssertTrue(Annotation.Kind.pen(points: [PixelPoint(x: 0, y: 0)]).handles.isEmpty)
    }

    func testHandlePositionsOnRect() {
        let k = Annotation.Kind.ellipse(rect: r, filled: false)
        XCTAssertEqual(k.handlePoint(.topLeft), PixelPoint(x: 10, y: 20))
        XCTAssertEqual(k.handlePoint(.bottomRight), PixelPoint(x: 110, y: 70))
        XCTAssertEqual(k.handlePoint(.top), PixelPoint(x: 60, y: 20))
        XCTAssertEqual(k.handlePoint(.left), PixelPoint(x: 10, y: 45))
    }

    func testMovingCornerKeepsOppositeCornerFixed() {
        let k = Annotation.Kind.rectangle(rect: r, filled: true)
        XCTAssertEqual(
            k.moving(.bottomRight, to: PixelPoint(x: 210, y: 120)),
            .rectangle(rect: PixelRect(x: 10, y: 20, width: 200, height: 100), filled: true))
        XCTAssertEqual(
            k.moving(.topLeft, to: PixelPoint(x: 0, y: 0)),
            .rectangle(rect: PixelRect(x: 0, y: 0, width: 110, height: 70), filled: true))
    }

    func testMovingEdgeOnlyChangesThatAxis() {
        let k = Annotation.Kind.blur(rect: r, strength: 16)
        XCTAssertEqual(k.moving(.right, to: PixelPoint(x: 300, y: 999)), .blur(rect: PixelRect(x: 10, y: 20, width: 290, height: 50), strength: 16))
        XCTAssertEqual(k.moving(.top, to: PixelPoint(x: 999, y: 0)), .blur(rect: PixelRect(x: 10, y: 0, width: 100, height: 70), strength: 16))
    }

    func testDraggingPastTheOppositeEdgeFlipsInsteadOfGoingNegative() {
        let k = Annotation.Kind.rectangle(rect: r, filled: false)
        XCTAssertEqual(
            k.moving(.right, to: PixelPoint(x: -40, y: 0)),
            .rectangle(rect: PixelRect(x: -40, y: 20, width: 50, height: 50), filled: false))
    }

    func testMovingLineEndpoints() {
        let k = Annotation.Kind.line(start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 10, y: 10))
        XCTAssertEqual(k.moving(.end, to: PixelPoint(x: 50, y: 5)), .line(start: PixelPoint(x: 0, y: 0), end: PixelPoint(x: 50, y: 5)))
        XCTAssertEqual(k.moving(.start, to: PixelPoint(x: -5, y: -5)), .line(start: PixelPoint(x: -5, y: -5), end: PixelPoint(x: 10, y: 10)))
        XCTAssertEqual(k.handlePoint(.end), PixelPoint(x: 10, y: 10))
    }

    func testMovingAnUnsupportedHandleIsANoOp() {
        let k = Annotation.Kind.step(center: PixelPoint(x: 5, y: 5), number: 1)
        XCTAssertEqual(k.moving(.topLeft, to: PixelPoint(x: 0, y: 0)), k)
    }
}
