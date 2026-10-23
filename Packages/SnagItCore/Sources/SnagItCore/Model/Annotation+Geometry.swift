import Foundation

extension Annotation {
    /// 步驟標記圓形的半徑（像素）。畫布、命中測試與匯出都使用同一個公式。
    public static func stepRadius(for style: Style) -> Double {
        10 + style.lineWidth * 1.5
    }

    /// 實際描邊寬度：螢光筆比一般筆粗。
    public var strokeWidth: Double {
        if case .highlighter = kind { return style.lineWidth * 3 }
        return style.lineWidth
    }

    /// 標註占據的範圍（含描邊），用於重繪與選取框。
    public var bounds: PixelRect {
        let pad = strokeWidth / 2
        func around(_ points: [PixelPoint]) -> PixelRect {
            guard let first = points.first else { return PixelRect(x: 0, y: 0, width: 0, height: 0) }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return PixelRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
        }
        switch kind {
        case let .arrow(start, end), let .line(start, end):
            return around([start, end])
        case let .pen(points), let .highlighter(points):
            return around(points)
        case let .rectangle(rect, _), let .ellipse(rect, _):
            let r = rect.normalized
            return PixelRect(x: r.x - pad, y: r.y - pad, width: r.width + 2 * pad, height: r.height + 2 * pad)
        case let .text(rect, _), let .blur(rect, _), let .pixelate(rect, _):
            return rect.normalized
        case let .step(center, _):
            let r = Annotation.stepRadius(for: style)
            return PixelRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        }
    }
}
