import AppKit
import TracePixelsCore
import UniformTypeIdentifiers

/// 把編輯器目前的內容匯出：複製到剪貼簿、另存新檔、拖曳、分享。
/// 全部先經 `Renderer.flatten` 合成（標註、遮蔽、裁切與修飾），與畫面一致（SC-006）。
@MainActor
struct ExportActions {
    let viewModel: EditorViewModel
    let preferences: Preferences
    let window: () -> NSWindow?

    private var pointSize: NSSize {
        NSSize(width: Double(viewModel.original.width) / viewModel.pixelsPerPoint,
               height: Double(viewModel.original.height) / viewModel.pixelsPerPoint)
    }

    func flattened() throws -> CGImage {
        try Renderer.flatten(viewModel.capture, original: viewModel.original)
    }

    private func nsImage() throws -> NSImage {
        let image = try flattened()
        return NSImage(cgImage: image, size: NSSize(
            width: Double(image.width) / viewModel.pixelsPerPoint,
            height: Double(image.height) / viewModel.pixelsPerPoint))
    }

    // MARK: 複製

    func copyToPasteboard() {
        do {
            let image = try flattened()
            let png = try Renderer.encode(image, as: .png)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([try nsImage()])
            pasteboard.setData(png, forType: .png)
        } catch {
            present(error)
        }
    }

    // MARK: 另存新檔

    func saveAs() {
        let folder = preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let panel = NSSavePanel()
        panel.allowedContentTypes = preferences.saveFormat == .png ? [.png, .jpeg] : [.jpeg, .png]
        panel.directoryURL = folder
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = FileNamer.uniqueURL(
            in: folder, date: viewModel.capture.createdAt, ext: preferences.saveFormat.fileExtension).lastPathComponent
        panel.title = String(localized: "另存新檔")

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { write(to: url) }
        }
        if let window = window() {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private func write(to url: URL) {
        let format: ImageFormat = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
            ? .jpeg(quality: preferences.jpegQuality) : .png
        do {
            let data = try Renderer.encode(try flattened(), as: format)
            try data.write(to: url, options: .atomic)
        } catch {
            // 寫入失敗（位置不可用、磁碟已滿…）：顯示錯誤並讓使用者重新選擇位置。
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "無法儲存檔案")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "重新選擇位置…"))
            alert.addButton(withTitle: String(localized: "取消"))
            if alert.runModal() == .alertFirstButtonReturn { saveAs() }
        }
    }

    // MARK: 拖曳與分享

    /// 拖曳開始時才合成並寫出暫存 PNG，回傳給拖曳工作階段使用。
    func dragPayload() -> (item: NSPasteboardItem, preview: NSImage)? {
        do {
            let image = try flattened()
            let png = try Renderer.encode(image, as: .png)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TracePixels-drag", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = FileNamer.uniqueURL(in: folder, date: viewModel.capture.createdAt, ext: "png")
            try png.write(to: url, options: .atomic)

            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setString(url.absoluteString, forType: .fileURL)
            return (item, try nsImage())
        } catch {
            present(error)
            return nil
        }
    }

    func share(relativeTo view: NSView) {
        guard let image = try? nsImage() else { return }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
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
