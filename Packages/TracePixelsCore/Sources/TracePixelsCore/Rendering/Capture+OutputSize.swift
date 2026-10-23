import CoreGraphics
import Foundation

extension Capture {
    /// 套用裁切後（縮放前）的像素矩形；沒有裁切時是整張影像，裁切範圍完全在影像外時回傳 nil。
    /// 座標向外取整到整數像素。`Renderer.flatten` 與 `outputPixelSize` 共用這個換算，兩者不會分歧。
    func croppedPixelRect(imageWidth: Int, imageHeight: Int) -> CGRect? {
        let bounds = PixelRect(x: 0, y: 0, width: Double(imageWidth), height: Double(imageHeight))
        guard let crop else { return CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight) }
        guard let r = crop.clamped(to: bounds) else { return nil }
        return CGRect(
            x: r.minX.rounded(.down), y: r.minY.rounded(.down),
            width: max(1, r.maxX.rounded(.up) - r.minX.rounded(.down)),
            height: max(1, r.maxY.rounded(.up) - r.minY.rounded(.down)))
    }

    /// 匯出影像的像素尺寸：裁切 → 縮放 → 加上邊框與陰影的邊距。與 `Renderer.flatten` 的輸出一致。
    public var outputPixelSize: PixelSize {
        let rect = croppedPixelRect(imageWidth: pixelSize.width, imageHeight: pixelSize.height)
            ?? CGRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height)
        let scaled = outputScale == 1
            ? (width: Int(rect.width), height: Int(rect.height))
            : (width: max(1, Int((rect.width * outputScale).rounded())), height: max(1, Int((rect.height * outputScale).rounded())))
        let margin = finish.margin
        return PixelSize(width: scaled.width + 2 * margin, height: scaled.height + 2 * margin)
    }
}
