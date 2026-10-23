import AppKit
import SnagItCore
import SwiftUI

/// 工具列按鈕呼叫的視窗層級動作。
struct EditorWindowActions {
    var zoomIn: () -> Void = {}
    var zoomOut: () -> Void = {}
    var zoomToFit: () -> Void = {}
    var copyImage: () -> Void = {}
    var saveAs: () -> Void = {}
    var share: (NSView) -> Void = { _ in }
    var dragPayload: () -> (item: NSPasteboardItem, preview: NSImage)? = { nil }
}

/// 一個擷取對應一個編輯器視窗：上方工具列、中間畫布（可縮放平移）、右側屬性面板。
/// 選單動作（復原、縮放、順序…）沿 responder chain 送到這裡。
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let captureID: Capture.ID
    private let environment: AppEnvironment
    private weak var registry: EditorWindowRegistry?
    private let viewModel: EditorViewModel
    private let canvas: CanvasView
    private let scrollView = NSScrollView()
    private let autosave: AutosaveController
    private lazy var exporter = ExportActions(
        viewModel: viewModel, preferences: environment.preferences, window: { [weak self] in self?.window })

    @MainActor
    init(capture: Capture, image: CGImage, environment: AppEnvironment, registry: EditorWindowRegistry) {
        captureID = capture.id
        self.environment = environment
        self.registry = registry
        viewModel = EditorViewModel(capture: capture, original: image, preferences: environment.preferences)
        canvas = CanvasView(viewModel: viewModel)
        autosave = AutosaveController(viewModel: viewModel, library: environment.library)

        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let inspectorWidth: CGFloat = 250
        let content = NSSize(
            width: min(max(canvas.frame.width + inspectorWidth, 760), visible.width * 0.85),
            height: min(max(canvas.frame.height + 40, 480), visible.height * 0.85))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 420)
        window.title = Self.title(for: capture)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        var actions = EditorWindowActions()
        actions.zoomIn = { [weak self] in self?.zoomIn(nil) }
        actions.zoomOut = { [weak self] in self?.zoomOut(nil) }
        actions.zoomToFit = { [weak self] in self?.zoomToFit(nil) }
        actions.copyImage = { [weak self] in self?.copy(nil) }
        actions.saveAs = { [weak self] in self?.saveAs(nil) }
        actions.share = { [weak self] view in self?.exporter.share(relativeTo: view) }
        actions.dragPayload = { [weak self] in self?.exporter.dragPayload() }
        buildLayout(in: window, inspectorWidth: inspectorWidth, actions: actions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    private static func title(for capture: Capture) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: capture.createdAt)
    }

    @MainActor
    private func buildLayout(in window: NSWindow, inspectorWidth: CGFloat, actions: EditorWindowActions) {
        let container = NSView()
        let toolbar = NSHostingView(rootView: ToolbarView(viewModel: viewModel, actions: actions))
        let inspector = NSHostingView(rootView: InspectorView(viewModel: viewModel))
        let separator = NSBox()
        separator.boxType = .separator

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.documentView = canvas
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true

        for view in [toolbar, inspector, scrollView, separator] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 40),
            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: separator.bottomAnchor),
            inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inspector.widthAnchor.constraint(equalToConstant: inspectorWidth),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
    }

    func show() {
        if let window { environment.activationPolicy.track(window) }
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 同步保存目前內容。
    @MainActor
    func flush() async {
        await autosave.flush()
    }

    func windowWillClose(_ notification: Notification) {
        let autosave = autosave
        Task { @MainActor in await autosave.flush() }
        registry?.closed(captureID)
    }

    // MARK: 選單動作（responder chain）

    @MainActor @objc func undo(_ sender: Any?) { viewModel.undo() }
    @MainActor @objc func redo(_ sender: Any?) { viewModel.redo() }
    @MainActor @objc func deleteSelection(_ sender: Any?) { viewModel.deleteSelection() }

    @MainActor @objc func selectTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = EditorTool(rawValue: raw) else { return }
        viewModel.setTool(tool)
    }

    @MainActor @objc func resizeOutput(_ sender: Any?) { viewModel.showsResizeSheet = true }
    @MainActor @objc func clearCrop(_ sender: Any?) { viewModel.clearCrop() }

    @MainActor @objc func bringToFront(_ sender: Any?) { viewModel.reorderSelection(.front) }
    @MainActor @objc func sendToBack(_ sender: Any?) { viewModel.reorderSelection(.back) }
    @MainActor @objc func bringForward(_ sender: Any?) { viewModel.reorderSelection(.forward) }
    @MainActor @objc func sendBackward(_ sender: Any?) { viewModel.reorderSelection(.backward) }

    @MainActor @objc func copy(_ sender: Any?) { exporter.copyToPasteboard() }
    @MainActor @objc func saveAs(_ sender: Any?) { exporter.saveAs() }

    @MainActor @objc func shareImage(_ sender: Any?) {
        if let anchor = window?.contentView { exporter.share(relativeTo: anchor) }
    }

    @MainActor @objc func zoomIn(_ sender: Any?) {
        scrollView.setMagnification(min(scrollView.magnification * 1.25, scrollView.maxMagnification), centeredAt: visibleCenter)
    }

    @MainActor @objc func zoomOut(_ sender: Any?) {
        scrollView.setMagnification(max(scrollView.magnification / 1.25, scrollView.minMagnification), centeredAt: visibleCenter)
    }

    @MainActor @objc func zoomToFit(_ sender: Any?) {
        let available = scrollView.contentSize
        let fit = min(available.width / canvas.frame.width, available.height / canvas.frame.height)
        scrollView.magnification = min(max(fit, scrollView.minMagnification), scrollView.maxMagnification)
    }

    private var visibleCenter: NSPoint {
        let visible = scrollView.contentView.documentVisibleRect
        return NSPoint(x: visible.midX, y: visible.midY)
    }

    @MainActor
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return viewModel.canUndo && viewModel.editingTextID == nil
        case #selector(redo(_:)): return viewModel.canRedo && viewModel.editingTextID == nil
        case #selector(deleteSelection(_:)), #selector(bringToFront(_:)), #selector(sendToBack(_:)),
             #selector(bringForward(_:)), #selector(sendBackward(_:)):
            return !viewModel.selection.isEmpty
        case #selector(clearCrop(_:)): return viewModel.capture.crop != nil && viewModel.editingTextID == nil
        default: return true
        }
    }
}

/// 追蹤已開啟的編輯器：同一個擷取最多一個視窗，不同擷取可以同時開啟多個（FR-030）。
@MainActor
final class EditorWindowRegistry {
    private var controllers: [Capture.ID: EditorWindowController] = [:]
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func open(capture: Capture, image: CGImage) {
        if let existing = controllers[capture.id] {
            existing.show()
            return
        }
        let controller = EditorWindowController(capture: capture, image: image, environment: environment, registry: self)
        controllers[capture.id] = controller
        controller.show()
    }

    /// 資料庫刪除擷取時，一併關閉它開著的編輯器。
    func close(_ id: Capture.ID) {
        controllers[id]?.window?.close()
    }

    func closed(_ id: Capture.ID) {
        controllers.removeValue(forKey: id)
    }

    /// 結束應用程式前，把所有開啟中的編輯器保存完。
    func flushAll() async {
        for controller in controllers.values { await controller.flush() }
    }
}
