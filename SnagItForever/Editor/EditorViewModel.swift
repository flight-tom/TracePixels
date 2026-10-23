import AppKit
import Combine
import SnagItCore

/// 一個編輯器視窗的狀態：文件（含復原歷史）、目前工具、選取與樣式。畫布與面板都觀察它。
@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var document: EditingDocument
    /// 原圖加上所有標註的合成結果，畫布直接顯示它。
    @Published private(set) var rendered: CGImage
    @Published private(set) var tool: EditorTool = .select
    @Published var selection: Set<Annotation.ID> = []
    /// 下一個建立的標註所使用的樣式；沒有選取時面板也顯示它。
    @Published private(set) var style: Style
    @Published private(set) var editingTextID: Annotation.ID?
    @Published var saveWarning: String?
    /// 拖曳裁切框時的暫時範圍；放開滑鼠才寫入文件（可復原）。
    @Published var cropDraft: PixelRect?
    /// 「調整輸出大小」面板是否顯示；工具列按鈕與選單項目共用。
    @Published var showsResizeSheet = false
    /// 套用裁切、縮放與修飾後的匯出預覽（畫面與匯出一致，FR-024）。
    @Published private(set) var exportPreview: NSImage?

    let original: CGImage
    private let preferences: Preferences
    private var editingTextIsNew = false
    private var previewTask: Task<Void, Never>?

    init(capture: Capture, original: CGImage, preferences: Preferences) {
        self.original = original
        self.preferences = preferences
        let document = EditingDocument(capture: capture)
        self.document = document
        rendered = Renderer.composite(document.capture, original: original)
        style = preferences.defaultStyle(for: EditorTool.select.rawValue)
    }

    var capture: Capture { document.capture }
    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }

    /// 畫布像素與「點」的比例（像素／點），即擷取時的縮放比例。
    var pixelsPerPoint: Double { max(capture.scale, 1) }

    var selectedAnnotations: [Annotation] {
        capture.annotations.filter { selection.contains($0.id) }
    }

    // MARK: 變更

    private func refresh() {
        let existing = Set(document.capture.annotations.map(\.id))
        let pruned = selection.intersection(existing)
        if pruned != selection { selection = pruned }
        var visible = document.capture
        if let hidden = editingTextID { visible.annotations.removeAll { $0.id == hidden } }
        rendered = Renderer.composite(visible, original: original)
        schedulePreview()
    }

    /// 只有在裁切、縮放或修飾不是預設值時才需要預覽；放在背景執行並去抖動。
    private func schedulePreview() {
        previewTask?.cancel()
        let capture = document.capture
        guard capture.crop != nil || capture.outputScale != 1 || capture.finish != .none else {
            exportPreview = nil
            return
        }
        let source = SendableImage(original)
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .utility) {
                try? Renderer.flatten(capture, original: source.cgImage)
            }.value
            guard !Task.isCancelled, let image else { return }
            self?.exportPreview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    // MARK: 裁切、縮放、修飾

    func commitCrop(_ rect: PixelRect) {
        cropDraft = nil
        mutate { $0.setCrop(rect) }
    }

    func clearCrop() { mutate { $0.setCrop(nil) } }

    func setOutputScale(_ scale: Double) { mutate { $0.setOutputScale(scale) } }

    func setFinish(_ change: (inout Finish) -> Void) {
        var finish = document.capture.finish
        change(&finish)
        mutate { $0.setFinish(finish) }
    }

    /// 目前匯出尺寸（像素）。算式在核心（`Capture.outputPixelSize`），與 `Renderer.flatten` 共用同一個換算。
    var outputPixelSize: PixelSize { capture.outputPixelSize }

    func mutate(_ change: (inout EditingDocument) -> Void) {
        change(&document)
        refresh()
    }

    func beginGesture() { document.beginGesture() }

    func endGesture() {
        document.endGesture()
        objectWillChange.send()
    }

    func undo() {
        guard editingTextID == nil else { return }
        document.undo()
        refresh()
    }

    func redo() {
        guard editingTextID == nil else { return }
        document.redo()
        refresh()
    }

    // MARK: 工具與樣式

    func setTool(_ new: EditorTool) {
        guard tool != new else { return }
        tool = new
        style = preferences.defaultStyle(for: new.rawValue)
        if style == Style(), preferences.defaultStyles[new.rawValue] == nil { style = new.factoryStyle }
        if new != .select { selection = [] }
    }

    /// 面板顯示的樣式：選取了標註時是第一個選取標註的樣式，否則是下一個建立標註的樣式。
    var inspectorStyle: Style {
        selectedAnnotations.first?.style ?? style
    }

    /// 面板作用的標註類型：單一選取時是它的類型；否則依目前工具推測。
    var inspectorKind: Annotation.Kind? {
        if let first = selectedAnnotations.first, selectedAnnotations.count == 1 { return first.kind }
        if let shape = tool.draftShape { return shape.kind(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 10, y: 10)) }
        switch tool {
        case .pen: return .pen(points: [])
        case .highlighter: return .highlighter(points: [])
        case .step: return .step(center: PixelPoint(x: 0, y: 0), number: 1)
        default: return nil
        }
    }

    /// 套用樣式變更：同時作用於選取的標註與「下一個標註」的預設樣式，並記住給該工具。
    func applyStyle(_ change: (inout Style) -> Void) {
        var next = style
        change(&next)
        style = next
        if tool != .select { preferences.defaultStyles[tool.rawValue] = next }
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate { doc in
            for id in ids { doc.update(id) { change(&$0.style) } }
        }
    }

    func setFilled(_ filled: Bool) {
        let ids = selection
        mutate { doc in
            for id in ids {
                doc.update(id) { a in
                    switch a.kind {
                    case let .rectangle(rect, _): a.kind = .rectangle(rect: rect, filled: filled)
                    case let .ellipse(rect, _): a.kind = .ellipse(rect: rect, filled: filled)
                    default: break
                    }
                }
            }
        }
    }

    func setRedactionStrength(_ strength: Double) {
        let ids = selection
        mutate { doc in
            for id in ids {
                doc.update(id) { a in
                    switch a.kind {
                    case let .blur(rect, _): a.kind = .blur(rect: rect, strength: strength)
                    case let .pixelate(rect, _): a.kind = .pixelate(rect: rect, strength: strength)
                    default: break
                    }
                }
            }
        }
    }

    // MARK: 標註操作

    @discardableResult
    func add(_ kind: Annotation.Kind) -> Annotation.ID {
        let annotation = Annotation(zIndex: 0, kind: kind, style: style)
        mutate { $0.add(annotation) }
        return annotation.id
    }

    func deleteSelection() {
        guard !selection.isEmpty, editingTextID == nil else { return }
        let ids = selection
        mutate { $0.remove(ids) }
        selection = []
    }

    func reorderSelection(_ order: ZOrder) {
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate { $0.reorder(ids, to: order) }
    }

    func nudgeSelection(dx: Double, dy: Double) {
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate { doc in
            for id in ids { doc.update(id) { $0.kind = $0.kind.translated(dx: dx, dy: dy) } }
        }
    }

    // MARK: 文字就地編輯

    /// 開始編輯一個文字標註。新建立的文字已在手勢內加入；既有文字則在這裡開始手勢。
    func startTextEditing(_ id: Annotation.ID, isNew: Bool) {
        if !isNew { document.beginGesture() }
        editingTextIsNew = isNew
        editingTextID = id
        selection = [id]
        refresh()
    }

    /// 結束編輯。空白文字：新建的整個取消（復原），既有的刪除。
    func finishTextEditing(string: String, fittedHeight: Double) {
        guard let id = editingTextID else { return }
        editingTextID = nil
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            if editingTextIsNew {
                document.endGesture()
                document.undo()
            } else {
                mutate { $0.remove([id]) }
                document.endGesture()
            }
            selection = []
        } else {
            mutate { doc in
                doc.update(id) { a in
                    guard case let .text(rect, _) = a.kind else { return }
                    var grown = rect.normalized
                    grown.height = max(grown.height, fittedHeight)
                    a.kind = .text(rect: grown, string: string)
                }
            }
            document.endGesture()
        }
        refresh()
        objectWillChange.send()
    }
}
