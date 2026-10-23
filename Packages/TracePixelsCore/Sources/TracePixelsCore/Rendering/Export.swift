import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public enum ImageFormat: Sendable, Equatable {
    case png
    case jpeg(quality: Double)

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}

public enum ExportError: Error {
    case encodingFailed
}

extension Renderer {
    /// 把合成後的影像編碼為檔案資料。JPEG 不支援透明，先鋪在白底上；品質夾限在 0–1。
    public static func encode(_ image: CGImage, as format: ImageFormat) throws -> Data {
        switch format {
        case .png:
            guard let data = Thumbnailer.encode(image, type: .png, quality: nil) else { throw ExportError.encodingFailed }
            return data
        case let .jpeg(quality):
            let opaque = onWhite(image) ?? image
            let clamped = min(max(quality, 0), 1)
            guard let data = Thumbnailer.encode(opaque, type: .jpeg, quality: clamped) else { throw ExportError.encodingFailed }
            return data
        }
    }

    private static func onWhite(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
