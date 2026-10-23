import AppKit
import SnagItCore

/// 把畫布上的滑鼠事件依目前工具轉成編輯操作。座標一律是影像像素。
@MainActor
final class ToolController {
    private let viewModel: EditorViewModel
    private let selectionController: SelectionController

    private struct Drawing {
        let id: Annotation.ID
        let origin: PixelPoint
        let tool: EditorTool
        var points: [PixelPoint]
    }

    private var drawing: Drawing?
    private var cropOrigin: PixelPoint?

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        selectionController = SelectionController(viewModel: viewModel)
    }

    func mouseDown(at point: PixelPoint, clickCount: Int, shift: Bool, tolerance: Double) {
        let tool = viewModel.tool
        switch tool {
        case .select:
            selectionController.mouseDown(at: point, clickCount: clickCount, shift: shift, tolerance: tolerance)

        case .crop:
            cropOrigin = point
            viewModel.cropDraft = PixelRect(x: point.x, y: point.y, width: 0, height: 0)

        case .step:
            viewModel.beginGesture()
            let number = viewModel.document.nextStepNumber()
            viewModel.add(.step(center: point, number: number))
            viewModel.endGesture()

        case .pen, .highlighter:
            viewModel.beginGesture()
            let kind: Annotation.Kind = tool == .pen ? .pen(points: [point]) : .highlighter(points: [point])
            let id = viewModel.add(kind)
            drawing = Drawing(id: id, origin: point, tool: tool, points: [point])

        case .text:
            viewModel.beginGesture()
            let id = viewModel.add(DraftShape.text.kind(from: point, to: point))
            drawing = Drawing(id: id, origin: point, tool: tool, points: [])

        case .arrow, .line, .rectangle, .ellipse, .blur, .pixelate:
            guard let shape = tool.draftShape else { return }
            viewModel.beginGesture()
            let id = viewModel.add(shape.kind(from: point, to: point))
            drawing = Drawing(id: id, origin: point, tool: tool, points: [])
        }
    }

    func mouseDragged(to point: PixelPoint, shift: Bool) {
        if viewModel.tool == .select {
            selectionController.mouseDragged(to: point)
            return
        }
        if viewModel.tool == .crop, let origin = cropOrigin {
            viewModel.cropDraft = Self.clampedCrop(from: origin, to: point, in: viewModel.capture.pixelSize)
            return
        }
        guard var drawing else { return }
        let id = drawing.id
        switch drawing.tool {
        case .pen, .highlighter:
            if let last = drawing.points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
            drawing.points.append(point)
            self.drawing = drawing
            let points = drawing.points
            let isPen = drawing.tool == .pen
            viewModel.mutate { $0.update(id) { $0.kind = isPen ? .pen(points: points) : .highlighter(points: points) } }
        default:
            guard let shape = drawing.tool.draftShape else { return }
            let kind = shape.kind(from: drawing.origin, to: point, constrain: shift)
            viewModel.mutate { $0.update(id) { $0.kind = kind } }
        }
    }

    func mouseUp(at point: PixelPoint) {
        if viewModel.tool == .select {
            selectionController.mouseUp()
            return
        }
        if viewModel.tool == .crop, let origin = cropOrigin {
            cropOrigin = nil
            let rect = Self.clampedCrop(from: origin, to: point, in: viewModel.capture.pixelSize)
            if rect.width >= 4, rect.height >= 4 { viewModel.commitCrop(rect) } else { viewModel.cropDraft = nil }
            return
        }
        guard let drawing else { return }
        self.drawing = nil

        if drawing.tool == .text {
            // 文字：拖曳出的範圍太小就給預設大小，然後直接進入編輯。
            let fontSize = viewModel.style.fontSize
            viewModel.mutate { doc in
                doc.update(drawing.id) { a in
                    guard case let .text(rect, string) = a.kind else { return }
                    var r = rect.normalized
                    if r.width < 20 { r.width = max(240, fontSize * 8) }
                    if r.height < fontSize { r.height = fontSize * 1.5 }
                    a.kind = .text(rect: r, string: string)
                }
            }
            viewModel.startTextEditing(drawing.id, isNew: true)
            return
        }

        viewModel.endGesture()
        // 單純點擊（幾乎沒有拖曳）不留下標註。
        if let created = viewModel.capture.annotations.first(where: { $0.id == drawing.id }), created.kind.isNegligible {
            viewModel.undo()
        } else {
            viewModel.selection = []
        }
    }

    /// 拖曳出的裁切框，夾限在影像範圍內。
    private static func clampedCrop(from a: PixelPoint, to b: PixelPoint, in size: PixelSize) -> PixelRect {
        let bounds = size.rect
        func clamp(_ p: PixelPoint) -> PixelPoint {
            PixelPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
        }
        return PixelRect(from: clamp(a), to: clamp(b))
    }
}
