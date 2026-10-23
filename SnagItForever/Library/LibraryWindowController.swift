import AppKit
import SwiftUI

final class LibraryWindowController: NSWindowController {
    private let environment: AppEnvironment

    @MainActor
    init(environment: AppEnvironment, editors: EditorWindowRegistry) {
        self.environment = environment
        let viewModel = LibraryViewModel(library: environment.library, editors: editors)
        let hosting = NSHostingController(rootView: LibraryView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "資料庫")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未實作") }

    func show() {
        if let window { environment.activationPolicy.track(window) }
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }
}
