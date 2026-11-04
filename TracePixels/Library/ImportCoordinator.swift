import AppKit
import TracePixelsCore
import UniformTypeIdentifiers

/// 所有「把外部圖片帶進來」的入口共用的流程：選單列、主選單、資料庫的匯入與拖放、Finder 與 Dock。
/// 讀取、驗證與彙總規則都在核心（`LibraryImporter`、`ImportReport`）；這裡只負責畫面。
@MainActor
final class ImportCoordinator {
    private let library: LibraryStore
    private let editors: EditorWindowRegistry
    /// 批次依序處理，避免兩批同時進行、彈出多個彙總視窗。
    private var lastBatch: Task<Void, Never>?

    init(library: LibraryStore, editors: EditorWindowRegistry) {
        self.library = library
        self.editors = editors
    }

    // MARK: 入口

    /// 「開啟圖片…」：選檔 → 匯入 → 開啟編輯器（至多 5 個）。
    func openImages() {
        guard let urls = chooseFiles(title: String(localized: "開啟圖片"), prompt: String(localized: "開啟")) else { return }
        process(urls: urls, openEditors: true)
    }

    /// 「匯入…」：選檔 → 只加入資料庫，不開編輯器。
    func importImages() {
        guard let urls = chooseFiles(title: String(localized: "匯入圖片"), prompt: String(localized: "匯入")) else { return }
        process(urls: urls, openEditors: false)
    }

    /// 拖放與 Finder／Dock 使用。可以含資料夾與非檔案 URL；核心會分類並由彙總訊息說明。
    func process(urls: [URL], openEditors: Bool) {
        guard !urls.isEmpty else { return }
        let previous = lastBatch
        lastBatch = Task { @MainActor [weak self] in
            await previous?.value
            await self?.run(urls: urls, openEditors: openEditors)
        }
    }

    // MARK: 檔案選擇

    private func chooseFiles(title: String, prompt: String) -> [URL]? {
        // 選單列 App 沒有 Dock 圖示，不先啟動的話選擇視窗會出現在其他 App 後面。
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }

    // MARK: 執行

    private func run(urls: [URL], openEditors: Bool) async {
        let progressPanel = ImportProgressPanel()
        // 超過 1 秒仍未完成才顯示進度；快速匯入時不閃一下面板。
        let reveal = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { progressPanel.show(total: urls.count) }
        }

        let result = await LibraryImporter(store: library).importFiles(urls) { progress in
            Task { @MainActor in progressPanel.update(done: progress.done, total: progress.total) }
        }
        reveal.cancel()
        progressPanel.close()

        if !result.imported.isEmpty {
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }

        let report = ImportReport.make(from: result, openEditors: openEditors)
        for id in report.editorsToOpen {
            if let (capture, image) = try? await library.load(id) {
                editors.open(capture: capture, image: image.cgImage)
            }
        }
        if report.needsAlert {
            present(report, importedCount: result.imported.count)
        }
    }

    // MARK: 彙總訊息

    private func present(_ report: ImportReport, importedCount: Int) {
        let hasProblems = !report.listedFailures.isEmpty || report.unlistedFailureCount > 0 || report.skippedNonFileCount > 0
        var lines: [String] = []
        if importedCount > 0 { lines.append(String(localized: "已匯入 \(importedCount) 張圖片。")) }
        if report.onlyInLibraryCount > 0 {
            lines.append(String(localized: "其餘 \(report.onlyInLibraryCount) 張已在資料庫中，沒有自動開啟編輯器。"))
        }
        if report.skippedNonFileCount > 0 {
            lines.append(String(localized: "\(report.skippedNonFileCount) 個項目不是圖片檔（資料夾或網頁圖片），已略過。"))
        }
        for failure in report.listedFailures {
            lines.append("• \(failure.name)：\(failure.reason.localizedReason)")
        }
        if report.unlistedFailureCount > 0 {
            lines.append(String(localized: "…還有 \(report.unlistedFailureCount) 個檔案無法匯入。"))
        }

        let alert = NSAlert()
        alert.alertStyle = hasProblems ? .warning : .informational
        alert.messageText = !hasProblems
            ? String(localized: "已匯入圖片")
            : (importedCount > 0 ? String(localized: "部分項目未能匯入") : String(localized: "無法匯入"))
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: String(localized: "好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

extension ImportFailure {
    /// 給使用者看的原因（見 data-model.md）。
    var localizedReason: String {
        switch self {
        case .notAFile: String(localized: "不是圖片檔（資料夾或網頁圖片）")
        case .unreadable: String(localized: "無法讀取檔案")
        case .unsupportedFormat: String(localized: "不支援的檔案格式")
        case .corrupt: String(localized: "檔案已損毀")
        case let .tooLarge(width, height): String(localized: "圖片過大（\(width) × \(height) 像素）")
        case .storageFailed: String(localized: "無法儲存到資料庫（磁碟空間不足或位置無法寫入）")
        }
    }
}
