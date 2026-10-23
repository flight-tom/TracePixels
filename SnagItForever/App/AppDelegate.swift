import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment.shared
    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private var coordinator: CaptureCoordinator?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let editors = EditorWindowRegistry(environment: environment)
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
            statusItemController = StatusItemController(actions: actions)
        }
    }

    private func showSettings() {
        guard let hotKeyController else { return }
        let controller = settingsWindow ?? SettingsWindowController(environment: environment, hotKeyController: hotKeyController)
        settingsWindow = controller
        controller.show()
    }
}
