import Foundation

/// 由匯入結果推導出的彙總：要開哪些編輯器、要在訊息裡列出什麼。
/// 純資料與純函式，沒有 UI 相依，所以可以無螢幕測試（FR-034、FR-040、FR-045）。
public struct ImportReport: Sendable, Equatable {
    public static let maxEditors = 5
    public static let maxListedFailures = 8

    /// 要自動開啟編輯器的項目（依匯入順序）。
    public let editorsToOpen: [Capture.ID]
    /// 已匯入但因超過上限而沒有開編輯器的數量（只在要開編輯器的情境才會大於 0）。
    public let onlyInLibraryCount: Int
    /// 要逐筆列出的失敗（不含 `notAFile`）。
    public let listedFailures: [ImportFailureItem]
    /// 超過列出上限而省略的失敗數量。
    public let unlistedFailureCount: Int
    /// 資料夾、網頁圖片等非檔案項目的合併計數。
    public let skippedNonFileCount: Int

    /// 是否需要跳出彙總訊息。全部成功且全部開啟（或本來就只匯入）時不打擾使用者。
    public var needsAlert: Bool {
        onlyInLibraryCount > 0 || !listedFailures.isEmpty || unlistedFailureCount > 0 || skippedNonFileCount > 0
    }

    public static func make(from result: ImportResult, openEditors: Bool) -> ImportReport {
        let ids = result.imported.map(\.id)
        let opened = openEditors ? Array(ids.prefix(maxEditors)) : []
        let onlyInLibrary = openEditors ? max(0, ids.count - maxEditors) : 0

        let real = result.failures.filter { $0.reason != .notAFile }
        return ImportReport(
            editorsToOpen: opened,
            onlyInLibraryCount: onlyInLibrary,
            listedFailures: Array(real.prefix(maxListedFailures)),
            unlistedFailureCount: max(0, real.count - maxListedFailures),
            skippedNonFileCount: result.skippedNonFileCount)
    }
}
