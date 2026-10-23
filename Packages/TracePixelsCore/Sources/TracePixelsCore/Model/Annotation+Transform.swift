import Foundation

/// 選取標註後可拖曳的控制點。
public enum Handle: Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case start, end
}

extension Annotation.Kind {
    private var isRectLike: Bool {
        switch self {
        case .rectangle, .ellipse, .text, .blur, .pixelate: true
        default: false
        }
    }

    private var rect: PixelRect? {
        switch self {
        case let .rectangle(rect, _), let .ellipse(rect, _), let .text(rect, _),
             let .blur(rect, _), let .pixelate(rect, _):
            rect.normalized
        default:
            nil
        }
    }

    private func replacingRect(_ new: PixelRect) -> Annotation.Kind {
        switch self {
        case let .rectangle(_, filled): .rectangle(rect: new, filled: filled)
        case let .ellipse(_, filled): .ellipse(rect: new, filled: filled)
        case let .text(_, string): .text(rect: new, string: string)
        case let .blur(_, strength): .blur(rect: new, strength: strength)
        case let .pixelate(_, strength): .pixelate(rect: new, strength: strength)
        default: self
        }
    }

    /// 整個標註平移。
    public func translated(dx: Double, dy: Double) -> Annotation.Kind {
        func move(_ p: PixelPoint) -> PixelPoint { PixelPoint(x: p.x + dx, y: p.y + dy) }
        func move(_ r: PixelRect) -> PixelRect { PixelRect(x: r.x + dx, y: r.y + dy, width: r.width, height: r.height) }
        switch self {
        case let .arrow(start, end): return .arrow(start: move(start), end: move(end))
        case let .line(start, end): return .line(start: move(start), end: move(end))
        case let .rectangle(rect, filled): return .rectangle(rect: move(rect), filled: filled)
        case let .ellipse(rect, filled): return .ellipse(rect: move(rect), filled: filled)
        case let .pen(points): return .pen(points: points.map(move))
        case let .highlighter(points): return .highlighter(points: points.map(move))
        case let .text(rect, string): return .text(rect: move(rect), string: string)
        case let .step(center, number): return .step(center: move(center), number: number)
        case let .blur(rect, strength): return .blur(rect: move(rect), strength: strength)
        case let .pixelate(rect, strength): return .pixelate(rect: move(rect), strength: strength)
        }
    }

    /// 此類型提供的控制點：矩形類 8 個、線條類 2 個、其他（步驟、手繪）只能移動。
    public var handles: [Handle] {
        if isRectLike { return [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left] }
        switch self {
        case .arrow, .line: return [.start, .end]
        default: return []
        }
    }

    public func handlePoint(_ handle: Handle) -> PixelPoint? {
        if let r = rect {
            switch handle {
            case .topLeft: return PixelPoint(x: r.minX, y: r.minY)
            case .top: return PixelPoint(x: r.center.x, y: r.minY)
            case .topRight: return PixelPoint(x: r.maxX, y: r.minY)
            case .right: return PixelPoint(x: r.maxX, y: r.center.y)
            case .bottomRight: return PixelPoint(x: r.maxX, y: r.maxY)
            case .bottom: return PixelPoint(x: r.center.x, y: r.maxY)
            case .bottomLeft: return PixelPoint(x: r.minX, y: r.maxY)
            case .left: return PixelPoint(x: r.minX, y: r.center.y)
            case .start, .end: return nil
            }
        }
        switch (self, handle) {
        case let (.arrow(start, _), .start), let (.line(start, _), .start): return start
        case let (.arrow(_, end), .end), let (.line(_, end), .end): return end
        default: return nil
        }
    }

    /// 把一個控制點拖到 `point`，其餘固定。拖過對邊時會翻轉而不是產生負尺寸。
    public func moving(_ handle: Handle, to point: PixelPoint) -> Annotation.Kind {
        if let r = rect {
            var left = r.minX, right = r.maxX, top = r.minY, bottom = r.maxY
            switch handle {
            case .topLeft: left = point.x; top = point.y
            case .top: top = point.y
            case .topRight: right = point.x; top = point.y
            case .right: right = point.x
            case .bottomRight: right = point.x; bottom = point.y
            case .bottom: bottom = point.y
            case .bottomLeft: left = point.x; bottom = point.y
            case .left: left = point.x
            case .start, .end: return self
            }
            return replacingRect(PixelRect(from: PixelPoint(x: left, y: top), to: PixelPoint(x: right, y: bottom)))
        }
        switch (self, handle) {
        case let (.arrow(_, end), .start): return .arrow(start: point, end: end)
        case let (.arrow(start, _), .end): return .arrow(start: start, end: point)
        case let (.line(_, end), .start): return .line(start: point, end: end)
        case let (.line(start, _), .end): return .line(start: start, end: point)
        default: return self
        }
    }
}
