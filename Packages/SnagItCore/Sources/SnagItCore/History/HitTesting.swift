import Foundation

extension Annotation {
    /// 點是否落在此標註上。線條類看與線段的距離；填滿的形狀看是否在內部；
    /// 未填滿的形狀只有靠近外框才算命中，避免擋住下方的標註。
    func hits(_ point: PixelPoint, tolerance: Double) -> Bool {
        let reach = tolerance + strokeWidth / 2
        switch kind {
        case let .arrow(start, end), let .line(start, end):
            return Self.distance(from: point, toSegment: start, end) <= reach
        case let .pen(points), let .highlighter(points):
            if points.count == 1, let only = points.first { return Self.distance(from: point, to: only) <= reach }
            return zip(points, points.dropFirst()).contains { Self.distance(from: point, toSegment: $0, $1) <= reach }
        case let .rectangle(rect, filled):
            let r = rect.normalized
            let expanded = PixelRect(x: r.x - tolerance, y: r.y - tolerance, width: r.width + 2 * tolerance, height: r.height + 2 * tolerance)
            if filled { return expanded.contains(point) }
            return Self.distanceToRectOutline(point, r) <= reach
        case let .ellipse(rect, filled):
            let r = rect.normalized
            let rx = r.width / 2, ry = r.height / 2
            guard rx > 0, ry > 0 else { return false }
            let dx = point.x - r.center.x, dy = point.y - r.center.y
            if filled {
                let ex = rx + tolerance, ey = ry + tolerance
                return (dx / ex) * (dx / ex) + (dy / ey) * (dy / ey) <= 1
            }
            // 未填滿：落在外緣與內緣（各偏移 reach）形成的環帶內。
            let outer = (dx / (rx + reach)) * (dx / (rx + reach)) + (dy / (ry + reach)) * (dy / (ry + reach))
            let innerRX = max(rx - reach, 0.001), innerRY = max(ry - reach, 0.001)
            let inner = (dx / innerRX) * (dx / innerRX) + (dy / innerRY) * (dy / innerRY)
            return outer <= 1 && inner >= 1
        case let .text(rect, _), let .blur(rect, _), let .pixelate(rect, _):
            let r = rect.normalized
            return PixelRect(x: r.x - tolerance, y: r.y - tolerance, width: r.width + 2 * tolerance, height: r.height + 2 * tolerance)
                .contains(point)
        case let .step(center, _):
            return Self.distance(from: point, to: center) <= Annotation.stepRadius(for: style) + tolerance
        }
    }

    private static func distance(from a: PixelPoint, to b: PixelPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func distance(from p: PixelPoint, toSegment a: PixelPoint, _ b: PixelPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(from: p, to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return distance(from: p, to: PixelPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private static func distanceToRectOutline(_ p: PixelPoint, _ r: PixelRect) -> Double {
        let corners = [
            PixelPoint(x: r.minX, y: r.minY), PixelPoint(x: r.maxX, y: r.minY),
            PixelPoint(x: r.maxX, y: r.maxY), PixelPoint(x: r.minX, y: r.maxY),
        ]
        return (0..<4).map { distance(from: p, toSegment: corners[$0], corners[($0 + 1) % 4]) }.min() ?? .infinity
    }
}
