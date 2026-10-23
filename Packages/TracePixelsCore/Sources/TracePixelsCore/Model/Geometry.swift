import Foundation

/// 影像像素座標系中的點（左上為原點，x 向右、y 向下）。
public struct PixelPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 影像的整數像素尺寸。
public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// 以原點為左上角、涵蓋整張影像的矩形。
    public var rect: PixelRect {
        PixelRect(x: 0, y: 0, width: Double(width), height: Double(height))
    }
}

/// 影像像素座標系中的矩形。寬或高可能為負值（拖曳方向相反）；需要時用 `normalized` 轉為正值。
public struct PixelRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// 由兩個對角點建立（順序不拘），結果的寬高必為非負。
    public init(from a: PixelPoint, to b: PixelPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// 寬高轉為非負，原點相應移動。
    public var normalized: PixelRect {
        PixelRect(
            x: width < 0 ? x + width : x,
            y: height < 0 ? y + height : y,
            width: abs(width),
            height: abs(height))
    }

    public var minX: Double { normalized.x }
    public var minY: Double { normalized.y }
    public var maxX: Double { normalized.x + normalized.width }
    public var maxY: Double { normalized.y + normalized.height }
    public var center: PixelPoint { PixelPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    /// 邊界上的點視為包含。
    public func contains(_ point: PixelPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// 兩矩形的交集；沒有重疊（面積為零或不相交）時回傳 nil。
    public func intersection(_ other: PixelRect) -> PixelRect? {
        let left = max(minX, other.minX)
        let top = max(minY, other.minY)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    public func union(_ other: PixelRect) -> PixelRect {
        let left = min(minX, other.minX)
        let top = min(minY, other.minY)
        let right = max(maxX, other.maxX)
        let bottom = max(maxY, other.maxY)
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// 夾限在 `bounds` 內；完全在外面時回傳 nil。
    public func clamped(to bounds: PixelRect) -> PixelRect? {
        normalized.intersection(bounds)
    }
}
