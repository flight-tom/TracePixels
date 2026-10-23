import Foundation

public enum ZOrder: Sendable {
    case front, back, forward, backward
}

/// 一個擷取在編輯器中的可變狀態：標註、裁切、縮放、修飾，以及復原歷史。
/// 歷史不跨工作階段保留（重新開啟擷取時從空白開始）。
public struct EditingDocument: Sendable {
    public private(set) var capture: Capture
    private var history = History<Capture>()
    /// 手勢（例如拖曳）進行中的起始狀態；手勢內的多次變更合併為一次歷史紀錄。
    private var gestureBase: Capture?

    public init(capture: Capture) {
        self.capture = capture
        normalizeZIndex()
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    // MARK: 變更

    private mutating func mutate(_ change: (inout Capture) -> Void) {
        let before = capture
        change(&capture)
        guard capture != before else { return }
        normalizeZIndex()
        if gestureBase == nil { history.record(before) }
    }

    /// 依 zIndex 穩定排序並重新編號為 0..<n。
    private mutating func normalizeZIndex() {
        let sorted = capture.annotations.enumerated()
            .sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }
            .map(\.element)
        capture.annotations = sorted.enumerated().map { index, annotation in
            var a = annotation
            a.zIndex = index
            return a
        }
    }

    /// 新增的標註放在最上層。
    public mutating func add(_ annotation: Annotation) {
        mutate { c in
            var a = annotation
            a.zIndex = (c.annotations.map(\.zIndex).max() ?? -1) + 1
            c.annotations.append(a)
        }
    }

    public mutating func update(_ id: Annotation.ID, _ change: (inout Annotation) -> Void) {
        mutate { c in
            guard let index = c.annotations.firstIndex(where: { $0.id == id }) else { return }
            change(&c.annotations[index])
        }
    }

    public mutating func remove(_ ids: Set<Annotation.ID>) {
        mutate { $0.annotations.removeAll { ids.contains($0.id) } }
    }

    public mutating func reorder(_ ids: Set<Annotation.ID>, to order: ZOrder) {
        mutate { c in
            var list = c.annotations.sorted { $0.zIndex < $1.zIndex }
            switch order {
            case .front:
                list = list.filter { !ids.contains($0.id) } + list.filter { ids.contains($0.id) }
            case .back:
                list = list.filter { ids.contains($0.id) } + list.filter { !ids.contains($0.id) }
            case .forward:
                var i = list.count - 2
                while i >= 0 {
                    if ids.contains(list[i].id), !ids.contains(list[i + 1].id) { list.swapAt(i, i + 1) }
                    i -= 1
                }
            case .backward:
                var i = 1
                while i < list.count {
                    if ids.contains(list[i].id), !ids.contains(list[i - 1].id) { list.swapAt(i, i - 1) }
                    i += 1
                }
            }
            c.annotations = list.enumerated().map { index, annotation in
                var a = annotation
                a.zIndex = index
                return a
            }
        }
    }

    /// 設定非破壞性裁切。範圍會被夾限在影像內；`nil` 清除裁切；夾限後小於 1 像素則忽略。
    public mutating func setCrop(_ rect: PixelRect?) {
        mutate { c in
            guard let rect else { c.crop = nil; return }
            guard let clamped = rect.clamped(to: c.pixelSize.rect), clamped.width >= 1, clamped.height >= 1 else { return }
            c.crop = clamped
        }
    }

    public mutating func setOutputScale(_ scale: Double) {
        mutate { $0.outputScale = scale }
    }

    public mutating func setFinish(_ finish: Finish) {
        mutate { $0.finish = finish }
    }

    // MARK: 手勢

    public mutating func beginGesture() {
        if gestureBase == nil { gestureBase = capture }
    }

    public mutating func endGesture() {
        guard let base = gestureBase else { return }
        gestureBase = nil
        if base != capture { history.record(base) }
    }

    // MARK: 復原與重做

    public mutating func undo() {
        guard let previous = history.undo(current: capture) else { return }
        capture = previous
    }

    public mutating func redo() {
        guard let next = history.redo(current: capture) else { return }
        capture = next
    }

    // MARK: 查詢

    /// 下一個步驟標記的編號：目前最大編號 + 1。刪除後不會自動重新編號。
    public func nextStepNumber() -> Int {
        let numbers = capture.annotations.compactMap { annotation -> Int? in
            if case let .step(_, number) = annotation.kind { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    /// 命中測試：回傳該點最上層的標註（容差單位為像素）。
    public func hitTest(_ point: PixelPoint, tolerance: Double) -> Annotation.ID? {
        capture.annotations
            .sorted { $0.zIndex > $1.zIndex }
            .first { $0.hits(point, tolerance: tolerance) }?
            .id
    }
}
