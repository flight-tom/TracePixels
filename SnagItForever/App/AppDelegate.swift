import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment.shared
    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private var coordinator: CaptureCoordinator?
    private var editors: EditorWindowRegistry?
    private var settingsWindow: SettingsWindowController?
    private var libraryWindow: LibraryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let editors = EditorWindowRegistry(environment: environment)
            self.editors = editors
            NSApp.mainMenu = MainMenuBuilder.build(settingsTarget: self, settingsAction: #selector(openSettings(_:)))
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
            actions.openLibrary = { [weak self] in MainActor.assumeIsolated { self?.showLibrary() } }
            statusItemController = StatusItemController(actions: actions)
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        showSettings()
    }

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
        guard let editors else { return }
        let controller = libraryWindow ?? LibraryWindowController(environment: environment, editors: editors)
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
