import AppKit
import TracePixelsCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// 全域「點」座標、左上為原點的顯示器資訊（與 ScreenCaptureKit 的座標一致）。
    var displayInfo: DisplayInfo {
        DisplayInfo(
            id: displayID,
            frame: PixelRect(
                x: frame.minX, y: ScreenGeometry.primaryHeight - frame.maxY,
                width: frame.width, height: frame.height),
            scale: Double(backingScaleFactor))
    }
}

/// AppKit（左下原點）與擷取座標（左上原點）之間的換算。
enum ScreenGeometry {
    /// 主螢幕（有選單列的那個）的高度；全域座標的翻轉以它為基準。
    static var primaryHeight: Double {
        Double(NSScreen.screens.first?.frame.height ?? 0)
    }

    static var displays: [DisplayInfo] {
        NSScreen.screens.map(\.displayInfo)
    }

    static func topLeft(fromAppKit point: NSPoint) -> PixelPoint {
        PixelPoint(x: Double(point.x), y: primaryHeight - Double(point.y))
    }
}
