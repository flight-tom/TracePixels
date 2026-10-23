import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment.shared
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }
}
