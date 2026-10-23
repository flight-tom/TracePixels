import XCTest
@testable import TracePixelsCore

final class ModelCodingTests: XCTestCase {
    private func sampleKinds() -> [Annotation.Kind] {
        [
            .arrow(start: PixelPoint(x: 1, y: 2), end: PixelPoint(x: 3, y: 4)),
            .line(start: PixelPoint(x: 5, y: 6), end: PixelPoint(x: 7, y: 8)),
            .rectangle(rect: PixelRect(x: 1, y: 1, width: 10, height: 10), filled: true),
            .ellipse(rect: PixelRect(x: 2, y: 2, width: 20, height: 10), filled: false),
            .pen(points: [PixelPoint(x: 0, y: 0), PixelPoint(x: 1, y: 1), PixelPoint(x: 2, y: 3)]),
            .highlighter(points: [PixelPoint(x: 0, y: 0), PixelPoint(x: 9, y: 9)]),
            .text(rect: PixelRect(x: 4, y: 4, width: 100, height: 30), string: "你好 hello"),
            .step(center: PixelPoint(x: 50, y: 50), number: 3),
            .blur(rect: PixelRect(x: 0, y: 0, width: 40, height: 40), strength: 16),
            .pixelate(rect: PixelRect(x: 0, y: 0, width: 40, height: 40), strength: 12),
        ]
    }

    private func makeCapture(annotations: [Annotation] = []) -> Capture {
        Capture(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .region, pixelSize: PixelSize(width: 800, height: 600), scale: 2,
            annotations: annotations)
    }

    func testEveryKindRoundTripsThroughJSON() throws {
        let annotations = sampleKinds().enumerated().map { index, kind in
            Annotation(zIndex: index, kind: kind, style: Style())
        }
        let capture = makeCapture(annotations: annotations)
        let data = try Capture.encoder().encode(capture)
        let decoded = try Capture.decoder().decode(Capture.self, from: data)
        XCTAssertEqual(decoded, capture)
        XCTAssertEqual(decoded.annotations.count, 10)
    }

    func testKindTypeNamesMatchContract() throws {
        let names = ["arrow", "line", "rectangle", "ellipse", "pen", "highlighter", "text", "step", "blur", "pixelate"]
        XCTAssertEqual(sampleKinds().map(\.typeName), names)
        let data = try JSONEncoder().encode(Annotation(zIndex: 0, kind: sampleKinds()[0], style: Style()))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((object["kind"] as! [String: Any])["type"] as? String, "arrow")
    }

    func testCaptureSourceCoding() throws {
        for source in [CaptureSource.region, .window(title: "文件", appName: "Pages"), .display(index: 1)] {
            let data = try JSONEncoder().encode(source)
            XCTAssertEqual(try JSONDecoder().decode(CaptureSource.self, from: data), source)
        }
    }

    // MARK: 驗證規則

    func testLineWidthIsClampedTo1Through64() {
        XCTAssertEqual(Style(lineWidth: 0).lineWidth, 1)
        XCTAssertEqual(Style(lineWidth: 100).lineWidth, 64)
        var style = Style(lineWidth: 4)
        style.lineWidth = 500
        XCTAssertEqual(style.lineWidth, 64)
    }

    func testFontSizeIsClampedTo8Through400() {
        XCTAssertEqual(Style(fontSize: 2).fontSize, 8)
        XCTAssertEqual(Style(fontSize: 1000).fontSize, 400)
    }

    func testBlurAndPixelateStrengthBelow8IsRaisedTo8() {
        let rect = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let blur = Annotation(zIndex: 0, kind: .blur(rect: rect, strength: 2), style: Style())
        let pixelate = Annotation(zIndex: 0, kind: .pixelate(rect: rect, strength: 0), style: Style())
        XCTAssertEqual(blur.kind, .blur(rect: rect, strength: 8))
        XCTAssertEqual(pixelate.kind, .pixelate(rect: rect, strength: 8))
        var mutable = blur
        mutable.kind = .blur(rect: rect, strength: 1)
        XCTAssertEqual(mutable.kind, .blur(rect: rect, strength: 8))
    }

    func testDecodingAlsoEnforcesMinimumRedactionStrength() throws {
        let json = """
        {"id":"A1000000-0000-0000-0000-000000000000","zIndex":0,
         "kind":{"type":"blur","rect":{"x":0,"y":0,"width":10,"height":10},"strength":1},
         "style":{"color":{"r":1,"g":0,"b":0,"a":1},"lineWidth":4,"fontName":"x","fontSize":24}}
        """
        let a = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        XCTAssertEqual(a.kind, .blur(rect: PixelRect(x: 0, y: 0, width: 10, height: 10), strength: 8))
    }

    func testOutputScaleIsClamped() {
        var capture = makeCapture()
        capture.outputScale = 10
        XCTAssertEqual(capture.outputScale, 4.0)
        capture.outputScale = 0.01
        XCTAssertEqual(capture.outputScale, 0.1)
    }

    func testValidateRejectsNonPositivePixelSize() {
        var capture = makeCapture()
        capture.pixelSize = PixelSize(width: 0, height: 10)
        XCTAssertThrowsError(try capture.validate()) {
            XCTAssertEqual($0 as? CaptureValidationError, .invalidPixelSize)
        }
    }

    func testValidateRequiresCropInsideImageAtLeastOnePixel() {
        var capture = makeCapture()
        capture.crop = PixelRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNoThrow(try capture.validate())
        capture.crop = PixelRect(x: 700, y: 0, width: 200, height: 100)
        XCTAssertThrowsError(try capture.validate()) {
            XCTAssertEqual($0 as? CaptureValidationError, .cropOutOfBounds)
        }
        capture.crop = PixelRect(x: 0, y: 0, width: 0.5, height: 10)
        XCTAssertThrowsError(try capture.validate()) {
            XCTAssertEqual($0 as? CaptureValidationError, .cropOutOfBounds)
        }
    }

    func testValidateRejectsDuplicateAnnotationIDs() {
        let id = UUID()
        let a = Annotation(id: id, zIndex: 0, kind: .step(center: PixelPoint(x: 0, y: 0), number: 1), style: Style())
        let b = Annotation(id: id, zIndex: 1, kind: .step(center: PixelPoint(x: 5, y: 5), number: 2), style: Style())
        XCTAssertThrowsError(try makeCapture(annotations: [a, b]).validate()) {
            XCTAssertEqual($0 as? CaptureValidationError, .duplicateAnnotationIDs)
        }
    }

    // MARK: 向前相容

    func testUnknownKindIsSkippedButPreservedOnReencode() throws {
        let capture = makeCapture(annotations: [
            Annotation(zIndex: 0, kind: .step(center: PixelPoint(x: 1, y: 1), number: 1), style: Style())
        ])
        var object = try JSONSerialization.jsonObject(with: Capture.encoder().encode(capture)) as! [String: Any]
        var annotations = object["annotations"] as! [[String: Any]]
        annotations.append([
            "id": "B1000000-0000-0000-0000-000000000000", "zIndex": 1,
            "kind": ["type": "hologram", "depth": 9],
            "style": ["color": ["r": 0, "g": 0, "b": 0, "a": 1], "lineWidth": 4, "fontName": "x", "fontSize": 24],
        ])
        object["annotations"] = annotations
        let modified = try JSONSerialization.data(withJSONObject: object)

        let decoded = try Capture.decoder().decode(Capture.self, from: modified)
        XCTAssertEqual(decoded.annotations.count, 1)

        let reencoded = try Capture.encoder().encode(decoded)
        let again = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        let list = again["annotations"] as! [[String: Any]]
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.contains { ($0["kind"] as? [String: Any])?["type"] as? String == "hologram" })
    }
}
