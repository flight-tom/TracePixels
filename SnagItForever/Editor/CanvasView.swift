import AppKit
import Combine
import SnagItCore

/// 編輯器畫布。座標：左上原點（翻轉），大小為影像的「點」尺寸（像素尺寸除以擷取時的縮放比例）。
/// 顯示的是 `Renderer` 的合成結果（與匯出同一份程式碼），選取框與控制點畫在其上。
@MainActor
final class CanvasView: NSView {
    private let viewModel: EditorViewModel
    private let tools: ToolController
    private var textEditor: TextEditingController?
    private var cancellables = Set<AnyCancellable>()
    private let pixelsPerPoint: Double

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        tools = ToolController(viewModel: viewModel)
        pixelsPerPoint = viewModel.pixelsPerPoint
        let image = viewModel.rendered
        super.init(frame: NSRect(
            x: 0, y: 0, width: Double(image.width) / viewModel.pixelsPerPoint,
            height: Double(image.height) / viewModel.pixelsPerPoint))

        // objectWillChange 在變更「之前」發出；下一輪 run loop 再讀新值。
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.viewModelChanged() }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: Double { Double(enclosingScrollView?.magnification ?? 1) }

    private func viewModelChanged() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        if let id = viewModel.editingTextID {
            if textEditor == nil, let annotation = viewModel.capture.annotations.first(where: { $0.id == id }) {
                textEditor = TextEditingController(viewModel: viewModel, annotation: annotation, in: self)
            }
        } else if textEditor != nil {
            textEditor = nil
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: viewModel.tool == .select ? .arrow : .crosshair)
    }

    // MARK: 繪製

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = magnification >= 2 ? .none : .high
        NSImage(cgImage: viewModel.rendered, size: bounds.size).draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        drawCrop()
        drawSelection()
    }

    /// 有裁切範圍（或正在拖曳）時，把範圍外加暗，並描出範圍邊框。匯出只會包含範圍內的內容。
    private func drawCrop() {
        guard let crop = viewModel.cropDraft ?? viewModel.capture.crop else { return }
        let hole = viewRect(crop)
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: hole))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
        let border = NSBezierPath(rect: hole)
        border.lineWidth = CGFloat(1 / magnification)
        NSColor.white.setStroke()
        border.stroke()
    }

    private func viewRect(_ r: PixelRect) -> NSRect {
        let n = r.normalized
        return NSRect(x: n.x / pixelsPerPoint, y: n.y / pixelsPerPoint, width: n.width / pixelsPerPoint, height: n.height / pixelsPerPoint)
    }

    private func drawSelection() {
        let scale = CGFloat(1 / magnification)
        let accent = NSColor.controlAccentColor
        for annotation in viewModel.selectedAnnotations where annotation.id != viewModel.editingTextID {
            let outline = NSBezierPath(rect: viewRect(annotation.bounds))
            outline.lineWidth = scale
            outline.setLineDash([4 * scale, 3 * scale], count: 2, phase: 0)
            accent.setStroke()
            outline.stroke()
        }
        guard viewModel.selection.count == 1, let annotation = viewModel.selectedAnnotations.first,
              annotation.id != viewModel.editingTextID else { return }
        let size = 8 * scale
        for handle in annotation.kind.handles {
            guard let p = annotation.kind.handlePoint(handle) else { continue }
            let box = NSRect(x: p.x / pixelsPerPoint - size / 2, y: p.y / pixelsPerPoint - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: box).fill()
            let border = NSBezierPath(rect: box)
            border.lineWidth = scale
            accent.setStroke()
            border.stroke()
        }
    }

    // MARK: 滑鼠

    private func pixelPoint(_ event: NSEvent) -> PixelPoint {
        let p = convert(event.locationInWindow, from: nil)
        return PixelPoint(x: Double(p.x) * pixelsPerPoint, y: Double(p.y) * pixelsPerPoint)
    }

    /// 約 6 個螢幕點對應的影像像素（隨縮放調整）。
    private var tolerance: Double { 6 * pixelsPerPoint / magnification }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        tools.mouseDown(
            at: pixelPoint(event), clickCount: event.clickCount,
            shift: event.modifierFlags.contains(.shift), tolerance: tolerance)
    }

    override func mouseDragged(with event: NSEvent) {
        tools.mouseDragged(to: pixelPoint(event), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        tools.mouseUp(at: pixelPoint(event))
    }

    // MARK: 鍵盤

    override func keyDown(with event: NSEvent) {
        guard viewModel.editingTextID == nil else { return super.keyDown(with: event) }
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if plain {
            switch event.keyCode {
            case 51, 117:  // ⌫、Forward Delete
                viewModel.deleteSelection()
                return
            case 53:  // Esc
                viewModel.selection = []
                viewModel.setTool(.select)
                return
            case 123, 124, 125, 126:  // 方向鍵：微調 1 像素（Shift 為 10）
                let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
                switch event.keyCode {
                case 123: viewModel.nudgeSelection(dx: -step, dy: 0)
                case 124: viewModel.nudgeSelection(dx: step, dy: 0)
                case 125: viewModel.nudgeSelection(dx: 0, dy: step)
                default: viewModel.nudgeSelection(dx: 0, dy: -step)
                }
                return
            default:
                break
            }
            if let key = event.charactersIgnoringModifiers?.lowercased(),
               let tool = EditorTool.allCases.first(where: { $0.key == key }) {
                viewModel.setTool(tool)
                return
            }
        }
        super.keyDown(with: event)
    }
}
