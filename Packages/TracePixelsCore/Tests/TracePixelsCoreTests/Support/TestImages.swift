import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

// MARK: 檔案輔助（匯入測試用）


/// 測試用的暫存目錄；`deinit` 時（含恢復權限後）整個移除。
final class TestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TracePixelsCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func subdirectory(_ name: String) throws -> URL {
        let dir = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    deinit {
        // 先恢復可能被測試改過的權限，才能刪得掉。
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in walker {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}

extension TestImages {
    /// 本機的 ImageIO 能否寫出此類型（例如部分環境沒有 HEIC 編碼器）。
    static func canEncode(_ type: UTType) -> Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(type.identifier)
    }

    /// 把影像寫成指定格式的檔案；`orientation` 為 EXIF 方向 1～8。
    static func write(
        _ image: CGImage, as type: UTType, to url: URL, orientation: Int? = nil, quality: Double? = nil
    ) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// 多格 GIF（每格延遲 0.1 秒）。
    static func writeAnimatedGIF(frames: [CGImage], to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, fileProperties as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]
        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// 以指定色彩空間繪製的純色影像（用來驗證色彩描述檔被保留）。
    static func solid(
        width: Int, height: Int, colorSpace space: CGColorSpace, r: CGFloat, g: CGFloat, b: CGFloat
    ) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: space, components: [r, g, b, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// 全黑的 8 位元灰階 PNG（壓縮後只有幾百 KB，但像素數很大）。用來測試總像素上限。
    static func writeBlankGrayPNG(width: Int, height: Int, to url: URL) throws {
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let image = ctx.makeImage()
        else { throw CocoaError(.fileWriteUnknown) }
        try write(image, as: .png, to: url)
    }

    /// 取 `url` 這個有效檔案的前半段，造出被截斷的檔案。
    static func writeTruncatedCopy(of source: URL, to url: URL) throws {
        let data = try Data(contentsOf: source)
        try data.prefix(max(data.count / 2, 16)).write(to: url)
    }
}
