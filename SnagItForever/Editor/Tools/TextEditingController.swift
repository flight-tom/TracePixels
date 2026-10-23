import AppKit
import SnagItCore

/// 文字標註的就地編輯：在畫布上疊一個透明的 NSTextView，位置與字級對齊渲染結果。
/// 完成（Esc、失去焦點）時把文字交回 `EditorViewModel`；完成前標註保持可編輯。
@MainActor
final class TextEditingController: NSObject, NSTextViewDelegate {
    private let viewModel: EditorViewModel
    private let textView: NSTextView
    private let pixelsPerPoint: Double
    private var finished = false

    init(viewModel: EditorViewModel, annotation: Annotation, in canvas: NSView) {
        self.viewModel = viewModel
        pixelsPerPoint = viewModel.pixelsPerPoint
        textView = NSTextView(frame: .zero)
        super.init()

        guard case let .text(rect, string) = annotation.kind else { return }
        let r = rect.normalized
        textView.frame = NSRect(
            x: r.x / pixelsPerPoint, y: r.y / pixelsPerPoint,
            width: r.width / pixelsPerPoint, height: max(r.height, annotation.style.fontSize * 1.5) / pixelsPerPoint)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.font = Self.font(for: annotation.style, pixelsPerPoint: pixelsPerPoint)
        textView.textColor = annotation.style.color.nsColor
        textView.insertionPointColor = annotation.style.color.nsColor
        textView.string = string
        textView.delegate = self
        textView.wantsLayer = true
        textView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        textView.layer?.borderWidth = 1

        canvas.addSubview(textView)
        canvas.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    private static func font(for style: Style, pixelsPerPoint: Double) -> NSFont {
        let size = CGFloat(style.fontSize / pixelsPerPoint)
        if style.fontName == Style.defaultFontName { return .systemFont(ofSize: size) }
        return NSFont(name: style.fontName, size: size) ?? .systemFont(ofSize: size)
    }

    /// 編輯框內文字實際占用的高度（影像像素），用來讓標註的矩形長高以容納全部文字。
    private var fittedHeight: Double {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return 0 }
        layout.ensureLayout(for: container)
        return Double(layout.usedRect(for: container).height) * pixelsPerPoint
    }

    func commit() {
        guard !finished else { return }
        finished = true
        let string = textView.string
        let height = fittedHeight
        textView.removeFromSuperview()
        viewModel.finishTextEditing(string: string, fittedHeight: height)
    }

    func textDidEndEditing(_ notification: Notification) {
        commit()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // NSTextView 把 Esc 對應到 `complete:`（自動完成），而不是 `cancelOperation:`，兩個都要接。
        if commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSTextView.complete(_:)) {
            commit()
            return true
        }
        return false
    }
}
