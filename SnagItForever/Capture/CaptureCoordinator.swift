import AppKit
import os
import SnagItCore

/// 串起整個擷取流程：快速鍵或選單 → 權限檢查 → 覆蓋層 → 擷取 → 存入資料庫 → 擷取後行為。
@MainActor
final class CaptureCoordinator {
    private let environment: AppEnvironment
    private let editors: EditorWindowRegistry
    private let service = CaptureService()
    private let log = Logger(subsystem: "com.snagitforever.app", category: "capture")

    private var overlay: CaptureOverlayController?
    private var permissionGuide: PermissionGuideWindowController?
    private var startedAt: Date?

    init(environment: AppEnvironment, editors: EditorWindowRegistry) {
        self.environment = environment
        self.editors = editors
    }

    func start(mode: CaptureOverlayController.Mode = .region) {
        guard overlay == nil else { return }
        // 每次擷取都重新檢查；執行期間權限被撤銷時一樣改顯示說明視窗（FR-005）。
        guard ScreenCapturePermission.isGranted else {
            ScreenCapturePermission.request()
            showPermissionGuide()
            return
        }

        startedAt = Date()
        let overlay = CaptureOverlayController(mode: mode)
        overlay.onFinish = { [weak self] request, ids in
            Task { @MainActor in await self?.finish(request: request, overlayWindowIDs: ids) }
        }
        self.overlay = overlay
        overlay.begin()
        logElapsed("快速鍵到覆蓋層顯示")

        // 放大鏡用的凍結畫面；取得前放大鏡不顯示，不影響覆蓋層出現的速度。
        let ids = overlay.overlayWindowIDs
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            Task { @MainActor in
                if let image = await service.snapshot(displayID: displayID, excluding: ids) {
                    self.overlay?.attachFreezeFrame(image, forDisplay: displayID)
                }
            }
        }
    }

    // MARK: 擷取

    private func finish(request: CaptureOverlayController.Request?, overlayWindowIDs ids: [CGWindowID]) async {
        guard let request else {
            closeOverlay()  // 取消：不儲存也不複製
            return
        }
        let preferences = environment.preferences
        do {
            let result: CaptureResult
            switch request {
            case let .region(selection):
                result = try await service.captureRegion(selection, excluding: ids, includeCursor: preferences.includeCursor)
            case let .window(candidate):
                result = try await service.captureWindow(
                    candidate, includeShadow: preferences.includeWindowShadow, includeCursor: preferences.includeCursor)
            case let .display(info):
                result = try await service.captureDisplay(info, excluding: ids, includeCursor: preferences.includeCursor)
            }
            closeOverlay()
            await handle(result)
        } catch {
            closeOverlay()
            present(error)
        }
    }

    private func closeOverlay() {
        overlay?.end()
        overlay = nil
    }

    /// 存入資料庫並執行擷取後行為。儲存或複製失敗不影響擷取本身，它已經在資料庫裡。
    private func handle(_ result: CaptureResult) async {
        do {
            let capture = try await environment.library.create(
                image: SendableImage(result.image), source: result.source, scale: result.scale)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            let actions = environment.preferences.afterCapture

            if actions.contains(.copyToClipboard) {
                let size = NSSize(width: Double(result.image.width) / result.scale, height: Double(result.image.height) / result.scale)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([NSImage(cgImage: result.image, size: size)])
            }
            if actions.contains(.openEditor) {
                editors.open(capture: capture, image: result.image)
                logElapsed("確認擷取到編輯器開啟")
            }
            if actions.contains(.saveToFolder) {
                do {
                    try saveToFolder(result.image)
                } catch {
                    present(error)
                }
            }
        } catch {
            present(error)
        }
    }

    /// 儲存到預設資料夾：檔名與格式依偏好設定（FR-007、FR-017）。
    private func saveToFolder(_ image: CGImage) throws {
        let preferences = environment.preferences
        let format: ImageFormat = preferences.saveFormat == .png ? .png : .jpeg(quality: preferences.jpegQuality)
        let folder = preferences.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = FileNamer.uniqueURL(in: folder, date: Date(), ext: format.fileExtension)
        try Renderer.encode(image, as: format).write(to: url, options: .atomic)
    }

    // MARK: 錯誤與權限

    private func showPermissionGuide() {
        let guide = permissionGuide ?? PermissionGuideWindowController()
        permissionGuide = guide
        guide.show()
    }

    private func present(_ error: Error) {
        if case CaptureError.permissionDenied = error {
            showPermissionGuide()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "無法完成這個動作")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func logElapsed(_ label: String) {
        guard let startedAt else { return }
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        log.info("\(label, privacy: .public)：\(ms) ms")
    }
}
