import AppKit

// 以明確的進入點啟動，避免依賴 Storyboard 或 SwiftUI App 生命週期。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
