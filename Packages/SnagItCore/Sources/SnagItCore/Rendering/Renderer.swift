import CoreGraphics
import CoreText
import Foundation

/// 標註渲染。畫布與匯出共用同一份程式碼，所以畫面與匯出的結果一致（SC-006）。
/// 座標：影像像素、左上為原點。永遠不修改傳入的原圖。
public enum Renderer {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    // MARK: 公開介面

    /// 原圖加上所有標註（依 zIndex 由下而上）。模糊與馬賽克會遮蔽它們下方的一切，包含較低層的標註。
    public static func composite(_ capture: Capture, original: CGImage) -> CGImage {
        let width = original.width, height = original.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        var result: CGImage?
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: colorSpace, bitmapInfo: bitmapInfo)
            else { return }
            ctx.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))

            // 之後改用左上為原點的座標繪製標註。
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)

            let pixels = base.assumingMemoryBound(to: UInt8.self)
            for annotation in capture.annotations.sorted(by: { $0.zIndex < $1.zIndex }) {
                switch annotation.kind {
                case let .blur(rect, strength):
                    Redaction.blur(pixels: pixels, width: width, height: height, region: rect, strength: strength)
                case let .pixelate(rect, strength):
                    Redaction.pixelate(pixels: pixels, width: width, height: height, region: rect, strength: strength)
                default:
                    draw(annotation, in: ctx)
                }
            }
            result = ctx.makeImage()
        }
        return result ?? original
    }

    /// 把合成結果畫進呼叫端的 context（填滿 0..<寬、0..<高；context 為預設的左下原點）。
    public static func draw(_ capture: Capture, original: CGImage, into context: CGContext) {
        let image = composite(capture, original: original)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// 合成最終匯出影像。
    public static func flatten(_ capture: Capture, original: CGImage) throws -> CGImage {
        composite(capture, original: original)
    }

    // MARK: 逐類型繪製

    private static func cgColor(_ c: RGBAColor) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), CGFloat(c.a)])
            ?? CGColor(gray: 0, alpha: 1)
    }

    private static func cgRect(_ r: PixelRect) -> CGRect {
        let n = r.normalized
        return CGRect(x: n.x, y: n.y, width: n.width, height: n.height)
    }

    private static func cgPoint(_ p: PixelPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private static func draw(_ annotation: Annotation, in ctx: CGContext) {
        let style = annotation.style
        let stroke = cgColor(style.color)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineWidth(CGFloat(annotation.strokeWidth))
        ctx.setStrokeColor(stroke)
        ctx.setFillColor(cgColor(style.fillColor ?? style.color))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.kind {
        case let .line(start, end):
            ctx.move(to: cgPoint(start))
            ctx.addLine(to: cgPoint(end))
            ctx.strokePath()

        case let .arrow(start, end):
            drawArrow(from: start, to: end, width: annotation.strokeWidth, color: stroke, in: ctx)

        case let .rectangle(rect, filled):
            let r = cgRect(rect)
            if filled { ctx.fill(r) }
            ctx.stroke(r)

        case let .ellipse(rect, filled):
            let r = cgRect(rect)
            if filled { ctx.fillEllipse(in: r) }
            ctx.strokeEllipse(in: r)

        case let .pen(points):
            strokePolyline(points, width: annotation.strokeWidth, color: stroke, in: ctx)

        case let .highlighter(points):
            ctx.setLineCap(.butt)
            strokePolyline(points, width: annotation.strokeWidth, color: cgColor(RGBAColor(
                r: style.color.r, g: style.color.g, b: style.color.b, a: style.color.a * 0.45)), in: ctx)

        case let .text(rect, string):
            drawText(string, in: cgRect(rect), style: style, ctx: ctx)

        case let .step(center, number):
            drawStep(number, at: center, style: style, in: ctx)

        case .blur, .pixelate:
            break  // 由 composite 直接在像素上處理
        }
    }

    private static func strokePolyline(_ points: [PixelPoint], width: Double, color: CGColor, in ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.setLineWidth(CGFloat(width))
        ctx.setStrokeColor(color)
        if points.count == 1 {
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
            return
        }
        ctx.move(to: cgPoint(first))
        for p in points.dropFirst() { ctx.addLine(to: cgPoint(p)) }
        ctx.strokePath()
    }

    private static func drawArrow(from start: PixelPoint, to end: PixelPoint, width: Double, color: CGColor, in ctx: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 1 else { return }
        let ux = dx / length, uy = dy / length
        let headLength = min(max(14, width * 4), length)
        let halfWidth = headLength * tan(30 * .pi / 180)
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        // 軸線只畫到頭部內側，避免圓端點超出尖端。
        ctx.setLineCap(.butt)
        ctx.move(to: cgPoint(start))
        ctx.addLine(to: CGPoint(x: base.x + ux * headLength * 0.2, y: base.y + uy * headLength * 0.2))
        ctx.strokePath()

        ctx.setFillColor(color)
        ctx.move(to: cgPoint(end))
        ctx.addLine(to: CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth))
        ctx.addLine(to: CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: 文字

    private static func font(named name: String, size: Double, bold: Bool = false) -> CTFont {
        if name == Style.defaultFontName || name.isEmpty {
            let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, CGFloat(size), nil)
            return base ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
        }
        return CTFontCreateWithName(name as CFString, CGFloat(size), nil)
    }

    private static func attributed(_ string: String, font: CTFont, color: CGColor) -> CFAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return NSAttributedString(string: string, attributes: attributes) as CFAttributedString
    }

    /// 在目前為「左上原點」的 context 中，於 `rect` 內排版並繪製文字（自動換行、裁在矩形內）。
    private static func drawText(_ string: String, in rect: CGRect, style: Style, ctx: CGContext) {
        guard !string.isEmpty, rect.width > 0, rect.height > 0 else { return }
        ctx.clip(to: rect)
        // 切回「左下原點」的局部座標系給 CoreText 使用。
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        let text = attributed(string, font: font(named: style.fontName, size: style.fontSize), color: cgColor(style.color))
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: rect.height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    private static func drawStep(_ number: Int, at center: PixelPoint, style: Style, in ctx: CGContext) {
        let radius = Annotation.stepRadius(for: style)
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(cgColor(style.fillColor ?? style.color))
        ctx.fillEllipse(in: circle)

        let label = attributed(String(number), font: font(named: Style.defaultFontName, size: radius * 1.1, bold: true), color: CGColor(gray: 1, alpha: 1))
        let line = CTLineCreateWithAttributedString(label)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = CGPoint(x: -textWidth / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, ctx)
    }
}
