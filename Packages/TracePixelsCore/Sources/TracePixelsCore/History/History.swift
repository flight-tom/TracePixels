/// 快照式復原／重做堆疊。不設上限（FR-012）。
struct History<State: Sendable>: Sendable {
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 記錄「變更前」的狀態；新的編輯會清掉重做堆疊。
    mutating func record(_ before: State) {
        undoStack.append(before)
        redoStack.removeAll()
    }

    mutating func undo(current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
