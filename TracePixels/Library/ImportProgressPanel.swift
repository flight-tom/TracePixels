import AppKit

/// 匯入超過 1 秒才出現的小型進度面板。非模態、不搶焦點，也不阻擋其他視窗。
@MainActor
final class ImportProgressPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let indicator = NSProgressIndicator()
    private var total = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 84),
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel, .hudWindow],
            backing: .buffered, defer: true)
        panel.title = String(localized: "匯入圖片")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false

        indicator.style = .bar
        indicator.minValue = 0
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [label, indicator])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        indicator.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            indicator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
    }

    /// 單一檔案時沒有可量化的進度，用不定長度的進度條。
    func show(total: Int, done: Int = 0) {
        self.total = total
        indicator.maxValue = Double(max(total, 1))
        indicator.isIndeterminate = total <= 1
        if indicator.isIndeterminate { indicator.startAnimation(nil) }
        update(done: done, total: total)
        panel.center()
        panel.orderFrontRegardless()
    }

    func update(done: Int, total: Int) {
        indicator.doubleValue = Double(done)
        label.stringValue = total <= 1
            ? String(localized: "正在匯入圖片…")
            : String(localized: "正在匯入 \(min(done + 1, total))／\(total)")
    }

    func close() {
        indicator.stopAnimation(nil)
        panel.orderOut(nil)
    }
}
