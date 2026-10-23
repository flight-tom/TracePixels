import Foundation
import SnagItCore

/// 整個 App 共用的服務：偏好設定、資料庫、Dock 圖示策略。
final class AppEnvironment {
    static let shared = AppEnvironment()

    let preferences = Preferences()
    let library: LibraryStore
    let activationPolicy = ActivationPolicyManager()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support
            .appendingPathComponent("SnagItForever", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        library = LibraryStore(directory: directory)
    }
}
