import CoreGraphics
import Foundation

public enum LibraryError: Error, Equatable {
    case notFound
    case corrupt
    case unsupportedSchemaVersion(Int)
    case imageEncodingFailed
}

public struct LibraryEntry: Sendable, Identifiable {
    public let id: Capture.ID
    public let createdAt: Date
    public let thumbnailURL: URL?
    public let isUsable: Bool
}

/// 檔案式資料庫。每個擷取是一個 `<UUID>.snagitcapture/` 目錄：
/// `image.png`（原圖，建立後不再修改）、`document.json`（標註與中繼資料）、`thumbnail.jpg`。
public actor LibraryStore {
    public static let packageExtension = "snagitcapture"
    private static let imageName = "image.png"
    private static let documentName = "document.json"
    private static let thumbnailName = "thumbnail.jpg"

    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: 路徑

    private func packageURL(_ id: Capture.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.packageExtension)", isDirectory: true)
    }

    /// 日期只保留到秒，與 ISO 8601 的磁碟格式一致。
    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    // MARK: 建立與儲存

    public func create(
        image: SendableImage,
        source: CaptureSource,
        scale: Double,
        now: Date = Date()
    ) throws -> Capture {
        let cg = image.cgImage
        guard let png = Thumbnailer.pngData(from: cg) else { throw LibraryError.imageEncodingFailed }
        let capture = Capture(
            createdAt: Self.wholeSeconds(now), source: source,
            pixelSize: PixelSize(width: cg.width, height: cg.height), scale: scale)
        let package = packageURL(capture.id)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        try png.write(to: package.appendingPathComponent(Self.imageName), options: .atomic)
        try Capture.encoder().encode(capture).write(
            to: package.appendingPathComponent(Self.documentName), options: .atomic)
        if let jpeg = Thumbnailer.jpegData(from: cg) {
            try jpeg.write(to: package.appendingPathComponent(Self.thumbnailName), options: .atomic)
        }
        return capture
    }

    /// 寫入 `document.json`（原子取代）並更新 `modifiedAt`。絕不修改 `image.png`；
    /// 磁碟上的文件版本較新時拒絕覆寫。
    @discardableResult
    public func save(_ capture: Capture, now: Date = Date()) throws -> Capture {
        let package = packageURL(capture.id)
        let documentURL = package.appendingPathComponent(Self.documentName)
        if let existing = try? Data(contentsOf: documentURL),
           let version = Self.schemaVersion(in: existing), version > Capture.currentSchemaVersion {
            throw LibraryError.unsupportedSchemaVersion(version)
        }
        guard fileManager.fileExists(atPath: package.path) else { throw LibraryError.notFound }
        var saved = capture
        saved.modifiedAt = max(Self.wholeSeconds(now), capture.createdAt)
        try Capture.encoder().encode(saved).write(to: documentURL, options: .atomic)
        return saved
    }

    // MARK: 讀取

    public func load(_ id: Capture.ID) throws -> (Capture, SendableImage) {
        let package = packageURL(id)
        guard fileManager.fileExists(atPath: package.path) else { throw LibraryError.notFound }
        let capture = try readDocument(at: package)
        guard let data = try? Data(contentsOf: package.appendingPathComponent(Self.imageName)),
              let image = Thumbnailer.decode(data)
        else { throw LibraryError.corrupt }
        return (capture, SendableImage(image))
    }

    private func readDocument(at package: URL) throws -> Capture {
        guard let data = try? Data(contentsOf: package.appendingPathComponent(Self.documentName)) else {
            throw LibraryError.corrupt
        }
        if let version = Self.schemaVersion(in: data), version > Capture.currentSchemaVersion {
            throw LibraryError.unsupportedSchemaVersion(version)
        }
        guard let capture = try? Capture.decoder().decode(Capture.self, from: data) else {
            throw LibraryError.corrupt
        }
        return capture
    }

    private static func schemaVersion(in data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int
    }

    /// 列出所有項目，由新到舊。損毀或版本較新的項目以不可用狀態列出，不影響其他項目，也不會被刪除。
    public func list() -> [LibraryEntry] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        else { return [] }

        var entries: [LibraryEntry] = []
        for url in items where url.pathExtension == Self.packageExtension {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let thumbnail = url.appendingPathComponent(Self.thumbnailName)
            if let capture = try? readDocument(at: url),
               fileManager.fileExists(atPath: url.appendingPathComponent(Self.imageName).path) {
                entries.append(LibraryEntry(
                    id: id, createdAt: capture.createdAt,
                    thumbnailURL: ensureThumbnail(in: url), isUsable: true))
            } else {
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                entries.append(LibraryEntry(
                    id: id, createdAt: created,
                    thumbnailURL: fileManager.fileExists(atPath: thumbnail.path) ? thumbnail : nil,
                    isUsable: false))
            }
        }
        return entries.sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }

    /// 縮圖遺失時由 `image.png` 重建。
    private func ensureThumbnail(in package: URL) -> URL? {
        let thumbnail = package.appendingPathComponent(Self.thumbnailName)
        if fileManager.fileExists(atPath: thumbnail.path) { return thumbnail }
        guard let data = try? Data(contentsOf: package.appendingPathComponent(Self.imageName)),
              let image = Thumbnailer.decode(data),
              let jpeg = Thumbnailer.jpegData(from: image),
              (try? jpeg.write(to: thumbnail, options: .atomic)) != nil
        else { return nil }
        return thumbnail
    }

    // MARK: 刪除

    public func delete(_ id: Capture.ID) throws {
        let package = packageURL(id)
        guard fileManager.fileExists(atPath: package.path) else { throw LibraryError.notFound }
        try fileManager.removeItem(at: package)
    }
}
