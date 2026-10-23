import Foundation

/// 遮蔽（馬賽克與模糊）。直接在像素緩衝區上「重建」像素，而不是疊一層效果：
/// 輸出只取決於各磁磚的平均值，所以磁磚內部的細節無法從結果還原（SC-005、憲章原則 III）。
enum Redaction {
    /// 磁磚大小的下限；與 `Annotation.minimumRedactionStrength` 一致。
    static let minimumTile = Int(Annotation.minimumRedactionStrength)

    private struct Layout {
        /// 影像內實際被處理的像素範圍（半開區間）。
        let x0, x1, y0, y1: Int
        /// 磁磚網格的錨點（區域左上角，可能在影像外）與邊長。
        let originX, originY, tile: Int
        let columns, rows: Int

        init?(region: PixelRect, strength: Double, width: Int, height: Int) {
            let tile = max(Self.minimumTile, Int(strength.rounded()))
            let r = region.normalized
            let originX = Int(r.minX.rounded(.down)), originY = Int(r.minY.rounded(.down))
            let x0 = max(0, originX), y0 = max(0, originY)
            let x1 = min(width, Int(r.maxX.rounded(.up))), y1 = min(height, Int(r.maxY.rounded(.up)))
            guard x1 > x0, y1 > y0 else { return nil }
            self.tile = tile
            self.originX = originX
            self.originY = originY
            self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1
            columns = (x1 - 1 - originX) / tile - (x0 - originX) / tile + 1
            rows = (y1 - 1 - originY) / tile - (y0 - originY) / tile + 1
        }

        private static let minimumTile = Redaction.minimumTile
        var firstColumn: Int { (x0 - originX) / tile }
        var firstRow: Int { (y0 - originY) / tile }

        func tileBounds(column: Int, row: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
            let tx = firstColumn + column, ty = firstRow + row
            return (max(x0, originX + tx * tile), min(x1, originX + (tx + 1) * tile),
                    max(y0, originY + ty * tile), min(y1, originY + (ty + 1) * tile))
        }
    }

    /// 每個磁磚的 RGBA 平均值（整數四捨五入），列優先。
    private static func tileMeans(
        _ layout: Layout, pixels: UnsafeMutablePointer<UInt8>, width: Int
    ) -> [[Double]] {
        var means: [[Double]] = []
        means.reserveCapacity(layout.columns * layout.rows)
        for row in 0..<layout.rows {
            for column in 0..<layout.columns {
                let b = layout.tileBounds(column: column, row: row)
                var sum = [UInt64](repeating: 0, count: 4)
                for y in b.y0..<b.y1 {
                    var i = (y * width + b.x0) * 4
                    for _ in b.x0..<b.x1 {
                        sum[0] += UInt64(pixels[i]); sum[1] += UInt64(pixels[i + 1])
                        sum[2] += UInt64(pixels[i + 2]); sum[3] += UInt64(pixels[i + 3])
                        i += 4
                    }
                }
                let count = UInt64((b.x1 - b.x0) * (b.y1 - b.y0))
                means.append(sum.map { Double(($0 + count / 2) / count) })
            }
        }
        return means
    }

    /// 馬賽克：每個磁磚填入該磁磚的平均顏色。
    static func pixelate(
        pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, region: PixelRect, strength: Double
    ) {
        guard let layout = Layout(region: region, strength: strength, width: width, height: height) else { return }
        let means = tileMeans(layout, pixels: pixels, width: width)
        for row in 0..<layout.rows {
            for column in 0..<layout.columns {
                let b = layout.tileBounds(column: column, row: row)
                let mean = means[row * layout.columns + column]
                for y in b.y0..<b.y1 {
                    var i = (y * width + b.x0) * 4
                    for _ in b.x0..<b.x1 {
                        for c in 0..<4 { pixels[i + c] = UInt8(mean[c]) }
                        i += 4
                    }
                }
            }
        }
    }

    /// 模糊：先取磁磚平均，再在磁磚中心之間做雙線性內插。輸出同樣只是磁磚平均值的函數。
    static func blur(
        pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, region: PixelRect, strength: Double
    ) {
        guard let layout = Layout(region: region, strength: strength, width: width, height: height) else { return }
        let means = tileMeans(layout, pixels: pixels, width: width)
        let n = Double(layout.tile)

        func sample(_ column: Int, _ row: Int, _ channel: Int) -> Double {
            let c = min(max(column, 0), layout.columns - 1), r = min(max(row, 0), layout.rows - 1)
            return means[r * layout.columns + c][channel]
        }

        for y in layout.y0..<layout.y1 {
            let v = (Double(y - layout.originY) + 0.5) / n - 0.5 - Double(layout.firstRow)
            let r0 = Int(v.rounded(.down)), fy = v - Double(r0)
            for x in layout.x0..<layout.x1 {
                let u = (Double(x - layout.originX) + 0.5) / n - 0.5 - Double(layout.firstColumn)
                let c0 = Int(u.rounded(.down)), fx = u - Double(c0)
                let i = (y * width + x) * 4
                for channel in 0..<4 {
                    let top = sample(c0, r0, channel) * (1 - fx) + sample(c0 + 1, r0, channel) * fx
                    let bottom = sample(c0, r0 + 1, channel) * (1 - fx) + sample(c0 + 1, r0 + 1, channel) * fx
                    let value = top * (1 - fy) + bottom * fy
                    pixels[i + channel] = UInt8(min(max(value.rounded(), 0), 255))
                }
            }
        }
    }
}
