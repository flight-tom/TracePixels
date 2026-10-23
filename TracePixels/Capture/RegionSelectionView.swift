import AppKit
import TracePixelsCore

/// 覆蓋層的繪製與滑鼠處理，涵蓋三種模式。座標：視圖為左上原點，
/// 與全域「點」座標（左上原點）只差該顯示器 frame 的原點。
final class CaptureOverlayView: NSView {
    unowned let controller: CaptureOverlayController
    let screen: NSScreen
    /// 凍結畫面，僅用於放大鏡取樣；尚未取得時不顯示放大鏡。
    var freezeImage: CGImage? { didSet { needsDisplay = true } }

    private var origin: PixelPoint { screen.displayInfo.frame.originPoint }
    private var state: CaptureOverlayController.State { controller.state }

    init(controller: CaptureOverlayController, screen: NSScreen) {
        self.controller = controller
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: state.mode == .region ? .crosshair : .pointingHand)
    }

    // MARK: 座標

    private func globalPoint(_ event: NSEvent) -> PixelPoint {
        let local = convert(event.locationInWindow, from: nil)
        return PixelPoint(x: origin.x + local.x, y: origin.y + local.y)
    }

    private func localRect(fromGlobal rect: PixelRect) -> NSRect {
        NSRect(x: rect.x - origin.x, y: rect.y - origin.y, width: rect.width, height: rect.height)
    }

    // MARK: 滑鼠與鍵盤

    override func keyDown(with event: NSEvent) {
        if !controller.keyDown(event) { super.keyDown(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        controller.pointerMoved(to: globalPoint(event))
    }

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(event)
        switch state.mode {
        case .region:
            state.dragStart = point
            state.dragCurrent = point
            controller.refresh()
        case .window:
            controller.pointerMoved(to: point)
            if let window = state.hoveredWindow { controller.finish(with: .window(window)) }
        case .fullScreen:
            if let display = CaptureGeometry.display(containing: point, in: ScreenGeometry.displays) {
                controller.finish(with: .display(display))
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard state.mode == .region else { return }
        let point = globalPoint(event)
        state.dragCurrent = point
        state.hoverPoint = point
        controller.refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard state.mode == .region, state.dragStart != nil else { return }
        state.dragCurrent = globalPoint(event)
        if let selection = state.currentSelection(displays: ScreenGeometry.displays) {
            controller.finish(with: .region(selection))
        } else {
            // 太小的選取視為點擊，清掉後讓使用者重新拖曳。
            state.dragStart = nil
            state.dragCurrent = nil
            controller.refresh()
        }
    }

    // MARK: 繪製

    override func draw(_ dirtyRect: NSRect) {
        let hole = highlightRect()
        drawDim(excluding: hole)
        if let hole {
            let path = NSBezierPath(rect: hole.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = state.mode == .region ? 1.5 : 3
            (state.mode == .region ? NSColor.white : NSColor.controlAccentColor).setStroke()
            path.stroke()
        }
        drawReadout()
        drawMagnifier()
    }

    /// 此顯示器上要「挖洞」（不加暗）的區域。
    private func highlightRect() -> NSRect? {
        switch state.mode {
        case .region:
            guard let selection = state.currentSelection(displays: ScreenGeometry.displays),
                  selection.displayID == screen.displayID else { return nil }
            return NSRect(
                x: selection.sourceRect.x, y: selection.sourceRect.y,
                width: selection.sourceRect.width, height: selection.sourceRect.height)
        case .window:
            guard let frame = state.hoveredWindow?.frame else { return nil }
            let local = NSRect(x: frame.minX - origin.x, y: frame.minY - origin.y, width: frame.width, height: frame.height)
            let clipped = local.intersection(bounds)
            return clipped.isEmpty ? nil : clipped
        case .fullScreen:
            guard let hover = state.hoverPoint,
                  CaptureGeometry.display(containing: hover, in: ScreenGeometry.displays)?.id == screen.displayID
            else { return nil }
            return bounds.insetBy(dx: 2, dy: 2)
        }
    }

    private func drawDim(excluding hole: NSRect?) {
        let path = NSBezierPath(rect: bounds)
        if let hole { path.append(NSBezierPath(rect: hole)) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        path.fill()
    }

    /// 游標旁的讀數：座標與選取寬高（點）。
    private func drawReadout() {
        guard let hover = state.hoverPoint, bounds.contains(NSPoint(x: hover.x - origin.x, y: hover.y - origin.y)) else { return }
        var text = "\(Int(hover.x)), \(Int(hover.y))"
        switch state.mode {
        case .region:
            if let selection = state.currentSelection(displays: ScreenGeometry.displays) {
                text += "   \(Int(selection.sourceRect.width.rounded())) × \(Int(selection.sourceRect.height.rounded()))"
            }
        case .window:
            if let window = state.hoveredWindow {
                text = "\(window.appName)  \(window.title)   \(Int(window.frame.width)) × \(Int(window.frame.height))"
            }
        case .fullScreen:
            text = "\(Int(bounds.width)) × \(Int(bounds.height))"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var box = NSRect(
            x: hover.x - origin.x + 18, y: hover.y - origin.y + 18,
            width: size.width + 14, height: size.height + 8)
        if box.maxX > bounds.maxX { box.origin.x = hover.x - origin.x - 18 - box.width }
        if box.maxY > bounds.maxY { box.origin.y = hover.y - origin.y - 18 - box.height }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: box.minX + 7, y: box.minY + 4))
    }

    /// 區域模式的放大鏡：以凍結畫面取樣游標周圍 25×25 點，放大顯示。
    private func drawMagnifier() {
        guard state.mode == .region, let image = freezeImage, let hover = state.hoverPoint else { return }
        let local = NSPoint(x: hover.x - origin.x, y: hover.y - origin.y)
        guard bounds.contains(local) else { return }

        let scale = screen.backingScaleFactor
        let span: CGFloat = 25
        let crop = CGRect(
            x: (local.x - span / 2) * scale, y: (local.y - span / 2) * scale,
            width: span * scale, height: span * scale)
        guard let sample = image.cropping(to: crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)))
        else { return }

        let size: CGFloat = 125
        var box = NSRect(x: local.x + 24, y: local.y - 24 - size, width: size, height: size)
        if box.maxX > bounds.maxX { box.origin.x = local.x - 24 - size }
        if box.minY < bounds.minY { box.origin.y = local.y + 56 }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).addClip()
        context.interpolationQuality = .none
        // 視圖是翻轉座標，CGImage 需要再翻回來才不會上下顛倒。
        context.translateBy(x: box.minX, y: box.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(sample, in: CGRect(x: 0, y: 0, width: size, height: size))
        context.restoreGState()

        NSColor.white.setStroke()
        let ring = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        ring.lineWidth = 2
        ring.stroke()
        let cell = size / span
        let center = NSRect(x: box.midX - cell / 2, y: box.midY - cell / 2, width: cell, height: cell)
        NSColor.systemRed.setStroke()
        NSBezierPath(rect: center).stroke()
    }
}

private extension PixelRect {
    var originPoint: PixelPoint { PixelPoint(x: x, y: y) }
}
