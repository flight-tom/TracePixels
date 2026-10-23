import AppKit
import SwiftUI

/// 工具列上的「拖曳匯出」把手：按住拖到其他 App，就會交出合成後的影像（FR-018）。
struct DragExportHandle: NSViewRepresentable {
    let payload: () -> (item: NSPasteboardItem, preview: NSImage)?

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.payload = payload
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.payload = payload
    }
}

final class DragSourceNSView: NSView, NSDraggingSource {
    var payload: (() -> (item: NSPasteboardItem, preview: NSImage)?)?
    private let icon = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: String(localized: "拖曳匯出"))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = String(localized: "拖曳到其他 App 以匯出影像")
        setAccessibilityLabel(String(localized: "拖曳匯出"))
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        guard let icon else { return }
        let size = icon.size
        icon.draw(
            in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 0.85)
    }

    override func mouseDown(with event: NSEvent) {
        guard let (item, preview) = payload?() else { return }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        // 拖曳影像最長邊縮到 160 點，避免蓋住整個畫面。
        let scale = min(1, 160 / max(preview.size.width, preview.size.height))
        let size = NSSize(width: preview.size.width * scale, height: preview.size.height * scale)
        let frame = NSRect(origin: NSPoint(x: -size.width / 2 + bounds.midX, y: -size.height / 2 + bounds.midY), size: size)
        dragging.setDraggingFrame(frame, contents: preview)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
