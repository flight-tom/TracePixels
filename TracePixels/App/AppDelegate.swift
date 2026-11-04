import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, AppMenuActions {
    private let environment = AppEnvironment.shared
    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private var coordinator: CaptureCoordinator?
    private var editors: EditorWindowRegistry?
    private var importCoordinator: ImportCoordinator?
    /// 冷啟動時 Finder 的「打開方式」可能比啟動完成更早送來檔案；先存起來，啟動完成後再處理。
    private var pendingOpenURLs: [URL] = []
    private var settingsWindow: SettingsWindowController?
    private var libraryWindow: LibraryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 單元測試以本 App 為宿主：不要在測試時註冊全域快速鍵、選單列圖示與主選單。
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        MainActor.assumeIsolated {
            let editors = EditorWindowRegistry(environment: environment)
            self.editors = editors
            self.importCoordinator = ImportCoordinator(library: environment.library, editors: editors)
            // 清除上次異常結束殘留的匯入暫存目錄（從未成為項目的半成品）。
            Task { await environment.library.removeStaleStaging() }
            NSApp.mainMenu = MainMenuBuilder.build(appTarget: self)
            let coordinator = CaptureCoordinator(environment: environment, editors: editors)
            self.coordinator = coordinator

            let hotKeys = HotKeyController(preferences: environment.preferences) {
                MainActor.assumeIsolated { coordinator.start(mode: .region) }
            }
            hotKeyController = hotKeys

            var actions = StatusItemController.Actions()
            actions.captureRegion = { coordinator.start(mode: .region) }
            actions.captureWindow = { coordinator.start(mode: .window) }
            actions.captureFullScreen = { coordinator.start(mode: .fullScreen) }
            actions.openSettings = { [weak self] in self?.showSettings() }
            actions.openImage = { [weak self] in MainActor.assumeIsolated { self?.importCoordinator?.openImages() } }
            actions.openLibrary = { [weak self] in MainActor.assumeIsolated { self?.showLibrary() } }
            statusItemController = StatusItemController(actions: actions)

            if !pendingOpenURLs.isEmpty {
                let urls = pendingOpenURLs
                pendingOpenURLs = []
                importCoordinator?.process(urls: urls, openEditors: true)
            }
        }
    }

    /// Finder 的「打開方式」與拖到 Dock／應用程式圖示的圖片：與「開啟圖片…」選好檔案之後相同（FR-047）。
    func application(_ sender: NSApplication, open urls: [URL]) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        MainActor.assumeIsolated {
            if let importCoordinator {
                importCoordinator.process(urls: urls, openEditors: true)
            } else {
                pendingOpenURLs += urls
            }
        }
    }

    // 主選單的 App 層動作（與選單列圖示相同）。
    @objc func openSettings(_ sender: Any?) { showSettings() }
    @objc func openLibrary(_ sender: Any?) { MainActor.assumeIsolated { showLibrary() } }
    @objc func openImage(_ sender: Any?) { MainActor.assumeIsolated { importCoordinator?.openImages() } }
    @objc func importImages(_ sender: Any?) { MainActor.assumeIsolated { importCoordinator?.importImages() } }
    @objc func captureRegion(_ sender: Any?) { MainActor.assumeIsolated { coordinator?.start(mode: .region) } }
    @objc func captureWindow(_ sender: Any?) { MainActor.assumeIsolated { coordinator?.start(mode: .window) } }
    @objc func captureFullScreen(_ sender: Any?) { MainActor.assumeIsolated { coordinator?.start(mode: .fullScreen) } }

    /// 結束前把所有開啟中的編輯器保存完，避免遺失最後 0.5 秒內的編輯。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editors else { return .terminateNow }
        Task { @MainActor in
            await editors.flushAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @MainActor private func showLibrary() {
        guard let editors, let importCoordinator else { return }
        let controller = libraryWindow ?? LibraryWindowController(
            environment: environment, editors: editors, importer: importCoordinator)
        libraryWindow = controller
        controller.show()
    }

    private func showSettings() {
        guard let hotKeyController else { return }
        let controller = settingsWindow ?? SettingsWindowController(environment: environment, hotKeyController: hotKeyController)
        settingsWindow = controller
        controller.show()
    }
}
