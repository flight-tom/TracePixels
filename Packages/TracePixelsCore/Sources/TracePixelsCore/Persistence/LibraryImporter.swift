import Foundation

public struct ImportFailureItem: Sendable, Equatable {
    /// 檔案為檔名；非本機 URL 為完整的 URL 字串。
    public let name: String
    public let reason: ImportFailure

    public init(name: String, reason: ImportFailure) {
        self.name = name
        self.reason = reason
    }
}

public struct ImportResult: Sendable {
    /// 成功建立的項目，依輸入順序。
    public var imported: [Capture]
    public var failures: [ImportFailureItem]
    /// 是否因取消而提早結束；已完成的項目保留。
    public var cancelled: Bool

    public init(imported: [Capture], failures: [ImportFailureItem], cancelled: Bool) {
        self.imported = imported
        self.failures = failures
        self.cancelled = cancelled
    }

    /// 資料夾、網頁圖片等「根本不是檔案」的項目數量，彙總訊息會合併計數。
    public var skippedNonFileCount: Int { failures.filter { $0.reason == .notAFile }.count }
}

public struct ImportProgress: Sendable {
    /// 已處理（成功或失敗）的檔案數。
    public let done: Int
    public let total: Int
    /// 剛處理完的那個檔案。
    public let currentName: String
}

/// 批次匯入：逐檔讀取並存入資料庫。單檔失敗不影響其他檔案，也不在資料庫留下任何殘留。
public struct LibraryImporter: Sendable {
    private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    /// 依輸入順序循序處理（記憶體峰值只有一張圖）。檔案之間檢查 Task 取消。
    public func importFiles(
        _ urls: [URL],
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> ImportResult {
        var result = ImportResult(imported: [], failures: [], cancelled: false)
        for (index, url) in urls.enumerated() {
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            let name = url.isFileURL ? url.lastPathComponent : url.absoluteString
            do {
                let loaded = try ImageImporter.load(from: url)
                do {
                    let capture = try await store.create(
                        image: loaded.image, source: .imported(fileName: loaded.fileName), scale: 1.0)
                    result.imported.append(capture)
                } catch {
                    result.failures.append(ImportFailureItem(name: name, reason: .storageFailed))
                }
            } catch {
                result.failures.append(ImportFailureItem(name: name, reason: error))
            }
            progress?(ImportProgress(done: index + 1, total: urls.count, currentName: name))
        }
        return result
    }
}
