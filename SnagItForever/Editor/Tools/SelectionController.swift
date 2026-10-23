import AppKit
import SnagItCore

/// 選取工具：點選、Shift 加選、移動、用控制點縮放，雙擊文字進入編輯。
@MainActor
final class SelectionController {
    private let viewModel: EditorViewModel

    private enum Drag {
        case moving(start: PixelPoint, originals: [Annotation.ID: Annotation.Kind])
        case resizing(id: Annotation.ID, handle: Handle, original: Annotation.Kind)
    }

    private var drag: Drag?

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }

    /// 單一選取時，點在哪個控制點上。
    func handle(at point: PixelPoint, tolerance: Double) -> (id: Annotation.ID, handle: Handle)? {
        guard viewModel.selection.count == 1, let annotation = viewModel.selectedAnnotations.first else { return nil }
        for handle in annotation.kind.handles {
            guard let position = annotation.kind.handlePoint(handle) else { continue }
            if hypot(position.x - point.x, position.y - point.y) <= tolerance { return (annotation.id, handle) }
        }
        return nil
    }

    func mouseDown(at point: PixelPoint, clickCount: Int, shift: Bool, tolerance: Double) {
        if let hit = handle(at: point, tolerance: tolerance),
           let annotation = viewModel.capture.annotations.first(where: { $0.id == hit.id }) {
            viewModel.beginGesture()
            drag = .resizing(id: hit.id, handle: hit.handle, original: annotation.kind)
            return
        }

        guard let id = viewModel.document.hitTest(point, tolerance: tolerance) else {
            if !shift { viewModel.selection = [] }
            return
        }

        if clickCount >= 2, let annotation = viewModel.capture.annotations.first(where: { $0.id == id }),
           case .text = annotation.kind {
            viewModel.startTextEditing(id, isNew: false)
            return
        }

        if shift {
            if viewModel.selection.contains(id) { viewModel.selection.remove(id) } else { viewModel.selection.insert(id) }
        } else if !viewModel.selection.contains(id) {
            viewModel.selection = [id]
        }

        var originals: [Annotation.ID: Annotation.Kind] = [:]
        for annotation in viewModel.selectedAnnotations { originals[annotation.id] = annotation.kind }
        guard !originals.isEmpty else { return }
        viewModel.beginGesture()
        drag = .moving(start: point, originals: originals)
    }

    func mouseDragged(to point: PixelPoint) {
        switch drag {
        case let .moving(start, originals):
            let dx = point.x - start.x, dy = point.y - start.y
            viewModel.mutate { doc in
                for (id, kind) in originals { doc.update(id) { $0.kind = kind.translated(dx: dx, dy: dy) } }
            }
        case let .resizing(id, handle, original):
            viewModel.mutate { doc in
                doc.update(id) { $0.kind = original.moving(handle, to: point) }
            }
        case nil:
            break
        }
    }

    func mouseUp() {
        guard drag != nil else { return }
        drag = nil
        viewModel.endGesture()
    }
}
