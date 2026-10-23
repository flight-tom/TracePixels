import Foundation

/// 一個顯示器的幾何資訊。`frame` 為全域「點」座標、左上為原點（與 ScreenCaptureKit 一致）。
public struct DisplayInfo: Sendable, Equatable {
    public let id: UInt32
    public let frame: PixelRect
    /// 像素／點比例，例如 Retina 為 2。
    public let scale: Double

    public init(id: UInt32, frame: PixelRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

/// 區域選取換算後的結果：要擷取哪個顯示器的哪一塊，以及輸出的原生像素尺寸。
public struct RegionSelection: Sendable, Equatable {
    public let displayID: UInt32
    /// 相對於該顯示器左上角的選取範圍，單位為點。
    public let sourceRect: PixelRect
    /// 以顯示器原生解析度擷取時的像素尺寸。
    public let pixelSize: PixelSize
    /// 顯示器的像素／點比例，直接取自顯示器（例如 2.0）。
    /// 不能用 `pixelSize.width / sourceRect.width` 反推：像素尺寸有四捨五入，反推出來會是 1.9996 這類不精確的值。
    public let scale: Double
}

/// 擷取座標換算。純邏輯，不依賴螢幕或視窗伺服器。
public enum CaptureGeometry {
    /// 選取範圍至少要有的邊長（點）。
    public static let minimumSelectionLength: Double = 1

    /// 點所在的顯示器；邊界採左閉右開，使相鄰顯示器的交界點只屬於其中一個。
    public static func display(containing point: PixelPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { d in
            point.x >= d.frame.minX && point.x < d.frame.maxX
                && point.y >= d.frame.minY && point.y < d.frame.maxY
        }
    }

    /// 整個顯示器的原生像素尺寸。
    public static func pixelSize(of display: DisplayInfo) -> PixelSize {
        PixelSize(
            width: Int((display.frame.width * display.scale).rounded()),
            height: Int((display.frame.height * display.scale).rounded()))
    }

    /// 把拖曳的兩個全域點換算為選取結果。
    /// 選取限制在「拖曳起點所在的顯示器」內，超出的部分被夾限（FR-002）。
    /// 起點不在任何顯示器內，或夾限後任一邊小於 1 點時回傳 nil。
    public static func selection(
        from start: PixelPoint, to end: PixelPoint, displays: [DisplayInfo]
    ) -> RegionSelection? {
        guard let display = display(containing: start, in: displays) else { return nil }
        let dragged = PixelRect(from: start, to: end)
        guard let clamped = dragged.intersection(display.frame),
              clamped.width >= minimumSelectionLength, clamped.height >= minimumSelectionLength
        else { return nil }

        let local = PixelRect(
            x: clamped.x - display.frame.x, y: clamped.y - display.frame.y,
            width: clamped.width, height: clamped.height)
        let size = PixelSize(
            width: max(1, Int((local.width * display.scale).rounded())),
            height: max(1, Int((local.height * display.scale).rounded())))
        return RegionSelection(displayID: display.id, sourceRect: local, pixelSize: size, scale: display.scale)
    }
}
