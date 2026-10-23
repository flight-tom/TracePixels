import AppKit
import Combine
import SnagItCore
import SwiftUI

/// 擷取覆蓋層：每個顯示器一個無邊框視窗，負責模式切換（`R`／`W`／`F`）、取消（`Esc`）
/// 與把使用者的選擇回報給 `CaptureCoordinator`。依 contracts/commands.md。
final class CaptureOverlayController {
    enum Mode { case region, window, fullScreen }

    enum Request {
        case region(RegionSelection)
        case window(WindowCandidate)
        case display(DisplayInfo)
    }

    /// 覆蓋層視窗共用的狀態，視圖與模式列都從這裡讀取。
    final class State: ObservableObject {
        @Published var mode: Mode
        var hoverPoint: PixelPoint?
        var hoveredWindow: WindowCandidate?
        var dragStart: PixelPoint?
        var dragCurrent: PixelPoint?

        init(mode: Mode) { self.mode = mode }

        /// 目前拖曳中的選取（已夾限到起點所在的顯示器）。
        func currentSelection(displays: [DisplayInfo]) -> RegionSelection? {
            guard let dragStart, let dragCurrent else { return nil }
            return CaptureGeometry.selection(from: dragStart, to: dragCurrent, displays: displays)
        }
    }

    let state: State
    private var windows: [OverlayWindow] = []
    private var views: [CaptureOverlayView] = []
    private var finished = false

    /// 使用者完成選擇（非 nil）或取消（nil）。第二個參數是覆蓋層自己的視窗 ID，擷取時必須排除。
    var onFinish: ((Request?, [CGWindowID]) -> Void)?

    init(mode: Mode) {
        state = State(mode: mode)
    }

    var overlayWindowIDs: [CGWindowID] {
        windows.map { CGWindowID($0.windowNumber) }
    }

    // MARK: 顯示與關閉

    func begin() {
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = CaptureOverlayView(controller: self, screen: screen)
            window.contentView = view
            windows.append(window)
            views.append(view)
            installModeBar(in: view, screen: screen, showsBar: NSMouseInRect(mouse, screen.frame, false))
        }
        // 先全部顯示，再讓游標所在的螢幕成為 key window，才能收到 Esc 與模式快速鍵。
        for window in windows { window.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
        let key = zip(windows, NSScreen.screens).first { NSMouseInRect(mouse, $0.1.frame, false) }?.0 ?? windows.first
        key?.makeKeyAndOrderFront(nil)
        if let view = key?.contentView { key?.makeFirstResponder(view) }
        NSCursor.crosshair.set()
    }

    func end() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
    }

    func attachFreezeFrame(_ image: CGImage, forDisplay id: CGDirectDisplayID) {
        for view in views where view.screen.displayID == id { view.freezeImage = image }
    }

    private func installModeBar(in view: CaptureOverlayView, screen: NSScreen, showsBar: Bool) {
        guard showsBar else { return }
        let bar = NSHostingView(rootView: CaptureModeBar(state: state) { [weak self] in self?.setMode($0) })
        let size = bar.fittingSize
        bar.frame = NSRect(x: (screen.frame.width - size.width) / 2, y: 48, width: size.width, height: size.height)
        view.addSubview(bar)
    }

    // MARK: 輸入

    func setMode(_ mode: Mode) {
        guard state.mode != mode else { return }
        state.mode = mode
        state.dragStart = nil
        state.dragCurrent = nil
        state.hoveredWindow = nil
        refresh()
    }

    func refresh() {
        for view in views {
            view.needsDisplay = true
            view.window?.invalidateCursorRects(for: view)
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        onFinish?(nil, overlayWindowIDs)
    }

    func finish(with request: Request) {
        guard !finished else { return }
        finished = true
        // 之後的滑鼠事件不再處理；視窗保留到擷取完成（擷取時以視窗 ID 排除）。
        for window in windows { window.ignoresMouseEvents = true }
        onFinish?(request, overlayWindowIDs)
    }

    func pointerMoved(to point: PixelPoint) {
        state.hoverPoint = point
        if state.mode == .window {
            state.hoveredWindow = WindowPicker.topmost(
                at: CGPoint(x: point.x, y: point.y), excluding: Set(overlayWindowIDs))
        }
        refresh()
    }

    func keyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:  // Esc
            cancel()
            return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r": setMode(.region); return true
        case "w": setMode(.window); return true
        case "f": setMode(.fullScreen); return true
        default: return false
        }
    }
}

/// 可成為 key window 的無邊框覆蓋層視窗。
private final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 覆蓋層上方的模式列：區域／視窗／全螢幕。
private struct CaptureModeBar: View {
    @ObservedObject var state: CaptureOverlayController.State
    let onSelect: (CaptureOverlayController.Mode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            button(.region, symbol: "rectangle.dashed", title: String(localized: "區域"), key: "R")
            button(.window, symbol: "macwindow", title: String(localized: "視窗"), key: "W")
            button(.fullScreen, symbol: "display", title: String(localized: "全螢幕"), key: "F")
            Divider().frame(height: 18)
            Text("Esc " + String(localized: "取消"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func button(_ mode: CaptureOverlayController.Mode, symbol: String, title: String, key: String) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Label("\(title) (\(key))", systemImage: symbol)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(state.mode == mode ? Color.accentColor.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(state.mode == mode ? .isSelected : [])
    }
}
