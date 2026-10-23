# 契約：SnagItCore 對 App 公開的介面

`SnagItCore` 是 App 與純邏輯之間的邊界。以下是 App target 允許依賴的公開介面；此處為介面簽章層級的契約，不含實作。型別細節見 [data-model.md](../data-model.md)。

## 編輯文件

```swift
/// 一個擷取在編輯器中的可變狀態，包含標註與復原歷史。
public struct EditingDocument: Sendable {
    public private(set) var capture: Capture
    public var canUndo: Bool { get }
    public var canRedo: Bool { get }

    public mutating func add(_ annotation: Annotation)
    public mutating func update(_ id: Annotation.ID, _ change: (inout Annotation) -> Void)
    public mutating func remove(_ ids: Set<Annotation.ID>)
    public mutating func reorder(_ ids: Set<Annotation.ID>, to: ZOrder)   // front/back/forward/backward
    public mutating func setCrop(_ rect: PixelRect?)
    public mutating func setOutputScale(_ scale: Double)
    public mutating func setFinish(_ finish: Finish)

    /// 把連續的小變更（例如拖曳）合併為一次歷史紀錄。
    public mutating func beginGesture()
    public mutating func endGesture()

    public mutating func undo()
    public mutating func redo()

    /// 命中測試：回傳該點最上層的標註（容差為像素）。
    public func hitTest(_ point: PixelPoint, tolerance: Double) -> Annotation.ID?
}
```

## 渲染與匯出

```swift
public enum ImageFormat: Sendable { case png, jpeg(quality: Double) }

public struct Renderer {
    /// 畫布與匯出共用。把標註畫進 context；context 的座標系為影像像素、左上為原點。
    public static func draw(_ capture: Capture, original: CGImage, into: CGContext, includeSelectionChrome: Bool)

    /// 合成最終影像（套用 crop、遮蔽、標註、finish、outputScale）。
    public static func flatten(_ capture: Capture, original: CGImage) throws -> CGImage

    public static func encode(_ image: CGImage, as format: ImageFormat) throws -> Data
}
```

**保證**

- `flatten` 與 `draw` 使用同一份繪製程式碼（SC-006）。
- `flatten` 的輸出在 `blur`／`pixelate` 區域內只是原圖磁磚平均值的函數，不含磁磚內的高頻資訊（SC-005）。
- `flatten` 不修改傳入的 `original`。

## 資料庫

```swift
public actor LibraryStore {
    public init(directory: URL)

    public func list() async -> [LibraryEntry]                       // 由新到舊
    public func create(image: CGImage, source: CaptureSource, scale: Double) async throws -> Capture
    public func load(_ id: Capture.ID) async throws -> (Capture, CGImage)
    public func save(_ capture: Capture) async throws                // 原子寫入 document.json 與必要時重建縮圖
    public func delete(_ id: Capture.ID) async throws
    public func totalSize() async -> Int64
    public func deleteOlder(than: Date) async throws -> Int          // 回傳刪除數量
}

public struct LibraryEntry: Sendable {
    public let id: Capture.ID
    public let createdAt: Date
    public let thumbnailURL: URL?
    public let isUsable: Bool
}
```

## 檔名

```swift
public struct FileNamer {
    /// 例如 "SnagItForever 2026-10-23 14.30.05.png"；若已存在則加序號 " 2"、" 3"…
    public static func uniqueURL(in folder: URL, date: Date, ext: String) -> URL
}
```
