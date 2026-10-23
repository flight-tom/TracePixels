import CoreGraphics
import Foundation
@testable import TracePixelsCore

/// 測試用影像工廠與像素讀取輔助。所有影像皆為 sRGB、RGBA8、預乘 alpha。
enum TestImages {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    static func make(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = fill(x, y)
                let i = (y * width + x) * 4
                data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = a
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func solid(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        make(width: width, height: height) { _, _ in (r, g, b, 255) }
    }

    /// 每個像素的值都不同，用來偵測像素是否被改動。
    static func gradient(width: Int, height: Int) -> CGImage {
        make(width: width, height: height) { x, y in
            (UInt8((x * 255) / max(width - 1, 1)), UInt8((y * 255) / max(height - 1, 1)), UInt8((x + y) % 256), 255)
        }
    }

    /// 讀出 RGBA8 像素資料（左上為原點）。
    static func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let p = pixels(image)
        let i = (y * image.width + x) * 4
        return (p[i], p[i + 1], p[i + 2], p[i + 3])
    }
}
