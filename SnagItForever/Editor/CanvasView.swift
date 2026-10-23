import AppKit
import SnagItCore

/// 編輯器畫布。座標：左上原點（翻轉），大小為影像的「點」尺寸（像素尺寸除以擷取時的縮放比例）。
final class CanvasView: NSView {
    private(set) var image: CGImage
    private let imageScale: Double

    init(image: CGImage, scale: Double) {
        self.image = image
        self.imageScale = max(scale, 1)
        let size = NSSize(width: Double(image.width) / max(scale, 1), height: Double(image.height) / max(scale, 1))
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
}
