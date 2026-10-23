import Foundation

/// 以「按下→拖曳」建立的形狀。把拖曳的兩個點換算成標註幾何，供編輯器邊拖邊更新。
public enum DraftShape: Sendable {
    case arrow, line, rectangle, ellipse, blur, pixelate, text

    /// 新建模糊與馬賽克的預設強度（磁磚大小）。
    public static let defaultRedactionStrength: Double = 16

    /// `constrain` 為真（按住 Shift）時：線條與箭頭對齊 45° 的倍數，矩形與橢圓變成正方形。
    public func kind(from a: PixelPoint, to b: PixelPoint, constrain: Bool = false) -> Annotation.Kind {
        switch self {
        case .arrow:
            let end = constrain ? Self.snapped(from: a, to: b) : b
            return .arrow(start: a, end: end)
        case .line:
            let end = constrain ? Self.snapped(from: a, to: b) : b
            return .line(start: a, end: end)
        case .rectangle:
            return .rectangle(rect: Self.rect(from: a, to: b, square: constrain), filled: false)
        case .ellipse:
            return .ellipse(rect: Self.rect(from: a, to: b, square: constrain), filled: false)
        case .blur:
            return .blur(rect: Self.rect(from: a, to: b, square: constrain), strength: Self.defaultRedactionStrength)
        case .pixelate:
            return .pixelate(rect: Self.rect(from: a, to: b, square: constrain), strength: Self.defaultRedactionStrength)
        case .text:
            return .text(rect: Self.rect(from: a, to: b, square: false), string: "")
        }
    }

    private static func rect(from a: PixelPoint, to b: PixelPoint, square: Bool) -> PixelRect {
        guard square else { return PixelRect(from: a, to: b) }
        let side = max(abs(b.x - a.x), abs(b.y - a.y))
        let end = PixelPoint(x: a.x + (b.x >= a.x ? side : -side), y: a.y + (b.y >= a.y ? side : -side))
        return PixelRect(from: a, to: end)
    }

    /// 保持長度，把方向對齊到最近的 45° 倍數。
    private static func snapped(from a: PixelPoint, to b: PixelPoint) -> PixelPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return b }
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return PixelPoint(x: a.x + length * cos(angle), y: a.y + length * sin(angle))
    }
}

extension Annotation.Kind {
    /// 太小而可能是誤觸的標註（單純點擊）。步驟標記與文字框不受影響。
    public var isNegligible: Bool {
        let minimum = 3.0
        switch self {
        case let .arrow(start, end), let .line(start, end):
            return hypot(end.x - start.x, end.y - start.y) < minimum
        case let .rectangle(rect, _), let .ellipse(rect, _), let .blur(rect, _), let .pixelate(rect, _):
            let r = rect.normalized
            return r.width < minimum && r.height < minimum
        case let .pen(points), let .highlighter(points):
            return points.count < 2
        case .step, .text:
            return false
        }
    }
}
