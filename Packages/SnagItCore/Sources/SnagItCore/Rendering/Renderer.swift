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
        // 用 calloc 取得歸零的緩衝區：`[UInt8](repeating:count:)` 在 Debug 組態是未特化的泛型，
        // 5K 影像（約 5900 萬個元素）要花近百毫秒。
        guard let base = calloc(width * height * 4, 1) else { return original }
        defer { free(base) }
        guard let ctx = CGContext(
            data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo)
        else { return original }
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
        return ctx.makeImage() ?? original
    }

    /// 把合成結果畫進呼叫端的 context（填滿 0..<寬、0..<高；context 為預設的左下原點）。
    public static func draw(_ capture: Capture, original: CGImage, into context: CGContext) {
        let image = composite(capture, original: original)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// 合成最終匯出影像：標註與遮蔽 → 裁切 → 縮放 → 邊框、陰影與圓角。
    /// 全部是非破壞性的：不會修改傳入的 `capture` 或原圖。
    public static func flatten(_ capture: Capture, original: CGImage) throws -> CGImage {
        var image = composite(capture, original: original)

        if let crop = capture.crop {
            let bounds = PixelRect(x: 0, y: 0, width: Double(image.width), height: Double(image.height))
            guard let r = crop.clamped(to: bounds) else { throw ExportError.encodingFailed }
            let rect = CGRect(
                x: r.minX.rounded(.down), y: r.minY.rounded(.down),
                width: max(1, r.maxX.rounded(.up) - r.minX.rounded(.down)),
                height: max(1, r.maxY.rounded(.up) - r.minY.rounded(.down)))
            guard let cropped = image.cropping(to: rect) else { throw ExportError.encodingFailed }
            image = cropped
        }

        if capture.outputScale != 1 {
            image = try resized(image, scale: capture.outputScale)
        }

        if capture.finish != .none {
            image = try decorated(image, with: capture.finish)
        }
        return image
    }

    // MARK: 縮放與修飾

    private static func makeContext(width: Int, height: Int) throws -> CGContext {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo)
        else { throw ExportError.encodingFailed }
        ctx.interpolationQuality = .high
        return ctx
    }

    private static func resized(_ image: CGImage, scale: Double) throws -> CGImage {
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let ctx = try makeContext(width: width, height: height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else { throw ExportError.encodingFailed }
        return result
    }

    private static func roundedPath(_ rect: CGRect, radius: Double) -> CGPath {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// 邊框（在影像外圍）、陰影與圓角。畫布往四邊各擴張 `finish.margin` 像素。
    private static func decorated(_ image: CGImage, with finish: Finish) throws -> CGImage {
        let margin = finish.margin
        let borderWidth = finish.border.map { Double(Int($0.width.rounded(.up))) } ?? 0
        let width = image.width + 2 * margin, height = image.height + 2 * margin
        let ctx = try makeContext(width: width, height: height)

        let inner = CGRect(x: margin, y: margin, width: image.width, height: image.height)
        let framed = inner.insetBy(dx: -borderWidth, dy: -borderWidth)
        let radius = min(finish.cornerRadius, min(framed.width, framed.height) / 2)

        func enableShadow() {
            guard let shadow = finish.shadow else { return }
            // 規格中 offsetY 為正代表往下；CoreGraphics 的 y 軸向上，所以取負號。
            ctx.setShadow(
                offset: CGSize(width: shadow.offsetX, height: -shadow.offsetY),
                blur: CGFloat(shadow.blurRadius), color: cgColor(shadow.color))
        }

        // 先用整個外框形狀填色來產生陰影（不能在裁切範圍內畫，否則陰影會被裁掉）；
        // 有邊框時這個填色就是邊框，沒有邊框時之後會被影像以 .copy 完全蓋掉。
        ctx.saveGState()
        enableShadow()
        ctx.setFillColor(finish.border.map { cgColor($0.color) } ?? CGColor(gray: 0, alpha: 1))
        ctx.addPath(roundedPath(framed, radius: radius))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(roundedPath(inner, radius: max(radius - borderWidth, 0)))
        ctx.clip()
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: inner)
        ctx.restoreGState()

        guard let result = ctx.makeImage() else { throw ExportError.encodingFailed }
        return result
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
