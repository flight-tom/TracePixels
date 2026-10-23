import AppKit
import SnagItCore

/// 一個擷取對應一個編輯器視窗。
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let captureID: Capture.ID
    private let environment: AppEnvironment
    private weak var registry: EditorWindowRegistry?
    private let canvas: CanvasView

    init(capture: Capture, image: CGImage, environment: AppEnvironment, registry: EditorWindowRegistry) {
        self.captureID = capture.id
        self.environment = environment
        self.registry = registry
        canvas = CanvasView(image: image, scale: capture.scale)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.documentView = canvas
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.drawsBackground = true

        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let content = NSSize(
            width: min(max(canvas.frame.width, 480), visible.width * 0.8),
            height: min(max(canvas.frame.height, 320), visible.height * 0.8))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentView = scroll
        window.title = Self.title(for: capture)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    private static func title(for capture: Capture) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: capture.createdAt)
    }

    func show() {
        if let window { environment.activationPolicy.track(window) }
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        registry?.closed(captureID)
    }
}

/// 追蹤已開啟的編輯器：同一個擷取最多一個視窗，不同擷取可以同時開啟多個（FR-030）。
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

    fileprivate func closed(_ id: Capture.ID) {
        controllers.removeValue(forKey: id)
    }
}
