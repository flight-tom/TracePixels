# 契約：TracePixelsCore 新增的公開介面

延伸[功能 001 的核心介面契約](../../001-screenshot-capture-annotation/contracts/core-api.md)。以下為簽章層級，不含實作。

## 匯入單一檔案

```swift
public enum ImportLimits {
    public static let maxSide = 16384
    public static let maxPixels = 200_000_000
}

public enum ImportFailure: Error, Equatable, Sendable {
    case notAFile
    case unreadable
    case unsupportedFormat
    case corrupt
    case tooLarge(width: Int, height: Int)
    case storageFailed          // 寫入資料庫失敗（由 LibraryImporter 分類，ImageImporter 不會丟出）
}

public struct LoadedImage: Sendable {
    public let image: SendableImage      // 已套用方向、保留 alpha 與色彩空間；尺寸未被縮放
    public let fileName: String          // 原始檔名（含副檔名）
}

public enum ImageImporter {
    /// 讀取本機圖片檔的第 0 格。不修改、不鎖定原檔。
    /// - 非本機 URL、資料夾、不存在 → .notAFile
    /// - 超過 ImportLimits → .tooLarge（在解碼前判斷，不配置像素記憶體）
    public static func load(from url: URL) throws(ImportFailure) -> LoadedImage
}
```

保證：

1. 回傳影像的 `width × height` 等於「套用方向後」的檔案尺寸。
2. 有 alpha 的來源，回傳影像仍有 alpha，像素值不被預乘以外的方式改動。
3. 對同一檔案重複呼叫，像素結果完全相同。
4. 呼叫前後，檔案的內容與修改時間不變。

## 批次匯入

```swift
public struct ImportFailureItem: Sendable, Equatable {
    public let name: String
    public let reason: ImportFailure
}

public struct ImportResult: Sendable {
    public var imported: [Capture]
    public var failures: [ImportFailureItem]
    public var cancelled: Bool
    public var skippedNonFileCount: Int { get }   // reason == .notAFile 的筆數
}

public struct ImportProgress: Sendable {
    public let done: Int
    public let total: Int
    public let currentName: String
}

public struct LibraryImporter: Sendable {
    public init(store: LibraryStore)

    /// 依輸入順序逐檔匯入。單檔失敗不影響其他檔案。
    /// 支援 Task 取消：已完成的項目保留，result.cancelled = true。
    public func importFiles(
        _ urls: [URL],
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> ImportResult
}
```

保證：

1. 成功的檔案都各自成為一個新項目（`source = .imported(fileName:)`，`scale = 1.0`），即使同一檔案出現多次。
2. 失敗的檔案**不**在資料庫留下任何項目或殘留目錄。
3. `imported` 的順序與輸入順序一致（排除失敗者）。

## 彙總報告

```swift
public struct ImportReport: Sendable, Equatable {
    public static let maxEditors = 5
    public static let maxListedFailures = 8

    public let editorsToOpen: [Capture.ID]
    public let onlyInLibraryCount: Int
    public let listedFailures: [ImportFailureItem]
    public let unlistedFailureCount: Int
    public let skippedNonFileCount: Int
    public var needsAlert: Bool { get }

    /// 純函式：依匯入結果與意圖推導要開啟的編輯器與要顯示的訊息內容。
    public static func make(from result: ImportResult, openEditors: Bool) -> ImportReport
}
```

## 資料庫（變更）

```swift
public enum CaptureSource {            // 新增案例
    case imported(fileName: String)
}

public struct LibraryEntry {           // 新增欄位
    public let sourceFileName: String?
}

extension LibraryStore {
    /// 既有；現在以暫存目錄建立後原子改名。任一步驟失敗都不留下項目。
    public func create(image: SendableImage, source: CaptureSource, scale: Double, now: Date) throws -> Capture

    /// 新增。移除上次異常結束殘留的 *.importing 暫存目錄，回傳移除數量。
    @discardableResult
    public func removeStaleStaging() -> Int
}
```
