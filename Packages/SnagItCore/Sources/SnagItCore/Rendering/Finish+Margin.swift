import Foundation

extension Finish {
    /// 匯出時各邊額外增加的像素：邊框寬度加上陰影擴散所需的邊距。
    /// 沒有邊框也沒有陰影時為 0（影像尺寸不變）。
    public var margin: Int {
        let borderWidth = border.map { Int($0.width.rounded(.up)) } ?? 0
        let shadowMargin = shadow.map { Int((($0.blurRadius * 2) + max(abs($0.offsetX), abs($0.offsetY))).rounded(.up)) } ?? 0
        return max(0, borderWidth) + max(0, shadowMargin)
    }
}
