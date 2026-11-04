import CoreGraphics
import Foundation
import ImageIO

/// 匯入圖片的尺寸上限。超過者拒絕（不縮小後匯入，縮小會改變使用者的像素內容）。
public enum ImportLimits {
    /// 套用方向後的單邊像素上限。
    public static let maxSide = 16384
    /// 總像素上限。
    public static let maxPixels = 200_000_000
}

/// 無法匯入某個項目的原因。
public enum ImportFailure: Error, Equatable, Sendable {
    /// 資料夾、不存在的路徑，或非本機 URL（例如網頁圖片）。
    case notAFile
    /// 沒有讀取權限或讀取失敗。
    case unreadable
    /// ImageIO 不認得這個檔案（文字檔、PDF、副檔名是假的…）。
    case unsupportedFormat
    /// 認得格式，但內容已損毀或不完整。
    case corrupt
    /// 超過 `ImportLimits`。寬高為套用方向後的尺寸。
    case tooLarge(width: Int, height: Int)
    /// 寫入資料庫失敗（磁碟已滿、位置不可寫…）。只由 `LibraryImporter` 使用。
    case storageFailed
}

public struct LoadedImage: Sendable {
    /// 已套用方向、保留 alpha 與色彩空間、尺寸未被縮放的第 0 格。
    public let image: SendableImage
    /// 原始檔名（含副檔名，不含目錄）。
    public let fileName: String
}

/// 讀取本機圖片檔。不修改、不鎖定原檔。
public enum ImageImporter {
    public static func load(from url: URL) throws(ImportFailure) -> LoadedImage {
        guard url.isFileURL else { throw .notAFile }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { throw .notAFile }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw .unreadable }

        // 不快取：這個來源只用一次，不要讓 ImageIO 為它長期保留解碼結果。
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw .unsupportedFormat
        }
        guard let type = CGImageSourceGetType(source), CGImageSourceGetCount(source) > 0 else {
            throw .unsupportedFormat
        }
        // ImageIO 對被截斷的檔案很寬鬆（缺的部分補成空白仍回報成功）。PNG 格式嚴格，必須有 IEND 結尾，
        // 缺了就視為損毀；JPEG 等格式常有合法的結尾雜訊，檢查容易誤殺好檔案，所以不做同樣的檢查。
        if (type as String) == "public.png", !hasPNGTrailer(url) { throw .corrupt }

        // 先只讀屬性判斷尺寸，超過上限就不解碼（解碼一張 5 億像素的圖會先配置數 GB 記憶體）。
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0, rawHeight > 0
        else { throw .corrupt }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = (5...8).contains(orientation)
        let width = swapsAxes ? rawHeight : rawWidth
        let height = swapsAxes ? rawWidth : rawHeight

        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        if overflow || max(width, height) > ImportLimits.maxSide || pixels > ImportLimits.maxPixels {
            throw .tooLarge(width: width, height: height)
        }

        let decoded: CGImage?
        if orientation == 1 {
            decoded = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        } else {
            // 縮圖 API 是 ImageIO 內建套用 EXIF 方向的標準路徑；最大邊設為原尺寸，所以不會縮小。
            decoded = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
        }
        guard let image = decoded, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw .corrupt
        }
        guard image.width == width, image.height == height else { throw .corrupt }
        return LoadedImage(image: SendableImage(image), fileName: url.lastPathComponent)
    }

    /// 檔案尾端 4 KB 內是否有 PNG 的 IEND 區塊（長度 0、類型 `IEND`）。
    private static func hasPNGTrailer(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return false }
        let tail = min(size, 4096)
        guard (try? handle.seek(toOffset: size - tail)) != nil,
              let data = try? handle.read(upToCount: Int(tail))
        else { return false }
        let marker: [UInt8] = [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44]  // 長度 0 + "IEND"
        let bytes = [UInt8](data)
        guard bytes.count >= marker.count else { return false }
        for start in stride(from: bytes.count - marker.count, through: 0, by: -1)
        where Array(bytes[start..<start + marker.count]) == marker {
            return true
        }
        return false
    }
}
