import AppKit
import SnagItCore

extension Notification.Name {
    /// 資料庫內容有變動（新增、刪除、清除）。資料庫視窗與偏好設定收到後重新讀取。
    static let libraryDidChange = Notification.Name("SnagItForever.libraryDidChange")
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var entries: [LibraryEntry] = []
    @Published private(set) var totalBytes: Int64 = 0
    @Published var selection: LibraryEntry.ID?
    @Published var pendingDeletion: LibraryEntry?

    private let library: LibraryStore
    private let editors: EditorWindowRegistry
    private var observer: NSObjectProtocol?

    init(library: LibraryStore, editors: EditorWindowRegistry) {
        self.library = library
        self.editors = editors
        observer = NotificationCenter.default.addObserver(
            forName: .libraryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() async {
        entries = await library.list()
        totalBytes = await library.totalSize()
        if let selection, !entries.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    /// 重新開啟擷取；已經開啟的會直接帶到前景。標註保持可編輯（FR-021）。
    func open(_ entry: LibraryEntry) {
        guard entry.isUsable else { return }
        Task {
            do {
                let (capture, image) = try await library.load(entry.id)
                editors.open(capture: capture, image: image.cgImage)
            } catch {
                present(error)
            }
        }
    }

    /// 使用者在確認對話框按下「刪除」後才呼叫（FR-022）。
    func confirmDeletion() {
        guard let entry = pendingDeletion else { return }
        pendingDeletion = nil
        Task {
            do {
                editors.close(entry.id)
                try await library.delete(entry.id)
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "無法完成這個動作")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "好"))
        alert.runModal()
    }
}
