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
public enum ImageFormat: Sendable, Equatable { case png; case jpeg(quality: Double) }  // fileExtension、contentType

public enum Renderer {
    /// 原圖加上所有標註（依 zIndex 由下而上）。模糊與馬賽克直接重建像素，且會蓋住它下方較低層的標註。
    public static func composite(_ capture: Capture, original: CGImage) -> CGImage

    /// 把 composite 的結果畫進呼叫端的 context（填滿 0..<寬、0..<高）。
    public static func draw(_ capture: Capture, original: CGImage, into: CGContext)

    /// 最終匯出影像：標註與遮蔽 → 裁切 → 縮放 → 邊框、陰影、圓角。
    public static func flatten(_ capture: Capture, original: CGImage) throws -> CGImage

    /// 編碼為檔案資料。JPEG 鋪白底、品質夾限在 0–1。
    public static func encode(_ image: CGImage, as format: ImageFormat) throws -> Data
}

extension Finish { public var margin: Int }  // 邊框寬度 + 陰影邊距；沒有邊框與陰影時為 0
```

**保證**

- 畫布顯示的是 `composite`，匯出用的 `flatten` 以同一份 `composite` 為基礎，所以兩者一致（SC-006）。
- `blur`／`pixelate` 區域內的輸出只是磁磚平均值的函數，不含磁磚內的高頻資訊（SC-005）；強度低於 8 一律提升為 8。
- `composite` 與 `flatten` 不修改傳入的 `capture` 與 `original`。
- 同字型與大小的文字，第一次繪製與之後的邊緣像素有細微差異（CoreGraphics 字形快取）；要逐像素比對渲染結果時先渲染一次。
- 效能：5K 影像含 100 個標註，單次 `composite` 中位數 ≤ 33 ms（SC-004）。

## 互動用的純邏輯

```swift
public enum DraftShape { case arrow, line, rectangle, ellipse, blur, pixelate, text
    func kind(from: PixelPoint, to: PixelPoint, constrain: Bool = false) -> Annotation.Kind }  // Shift 約束
extension Annotation.Kind {
    var isNegligible: Bool                                  // 太小而可能是誤觸
    func translated(dx: Double, dy: Double) -> Annotation.Kind
    var handles: [Handle]; func handlePoint(_ h: Handle) -> PixelPoint?
    func moving(_ h: Handle, to: PixelPoint) -> Annotation.Kind  // 拖過對邊會翻轉
}
public enum CaptureGeometry {   // 螢幕點座標（左上原點）→ 擷取範圍與原生像素尺寸
    static func selection(from: PixelPoint, to: PixelPoint, displays: [DisplayInfo]) -> RegionSelection?
    static func display(containing: PixelPoint, in: [DisplayInfo]) -> DisplayInfo?
    static func pixelSize(of: DisplayInfo) -> PixelSize
}
```

## 資料庫

`CGImage` 在 Swift 6 語言模式下不是 `Sendable`。`SnagItCore` 以 `public struct SendableImage: @unchecked Sendable { public let cgImage: CGImage }` 包裝跨 actor 傳遞的影像；影像建立後不可變，因此是安全的。`LibraryStore` 的方法跨 actor 邊界時使用 `SendableImage`。

```swift
public actor LibraryStore {
    public init(directory: URL)

    public func list() -> [LibraryEntry]                              // 由新到舊；缺縮圖時重建
    public func create(image: SendableImage, source: CaptureSource, scale: Double, now: Date = Date()) throws -> Capture
    public func load(_ id: Capture.ID) throws -> (Capture, SendableImage)
    @discardableResult
    public func save(_ capture: Capture, now: Date = Date()) throws -> Capture  // 原子寫入 document.json 並更新 modifiedAt；絕不改 image.png；磁碟上版本較新時拒絕
    public func delete(_ id: Capture.ID) throws
    public func totalSize() -> Int64
    @discardableResult
    public func deleteOlder(than: Date) throws -> Int                 // 只刪可用項目，回傳刪除數量；資料庫本身絕不自動刪除
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
    public static func uniqueURL(in folder: URL, date: Date, ext: String, timeZone: TimeZone = .current) -> URL
}
```
