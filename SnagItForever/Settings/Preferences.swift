import AppKit
import Carbon.HIToolbox
import Combine
import SnagItCore

/// 全域快速鍵：虛擬鍵碼加上 Carbon 修飾鍵旗標。
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// 預設 ⌃⇧4（不與 macOS 內建的 ⌘⇧4 衝突）。
    static let `default` = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(controlKey | shiftKey))
}

/// 擷取後的行為，可複選。
struct AfterCaptureActions: OptionSet, Codable {
    let rawValue: Int
    static let openEditor = AfterCaptureActions(rawValue: 1 << 0)
    static let copyToClipboard = AfterCaptureActions(rawValue: 1 << 1)
    static let saveToFolder = AfterCaptureActions(rawValue: 1 << 2)
}

enum SaveFormat: String, Codable, CaseIterable {
    case png
    case jpeg

    var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// 使用者偏好設定，存於 `UserDefaults`。預設值見 data-model.md。
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var hotKey: HotKeyCombo { didSet { store(hotKey, for: Key.hotKey) } }
    @Published var afterCapture: AfterCaptureActions { didSet { defaults.set(afterCapture.rawValue, forKey: Key.afterCapture) } }
    @Published var saveFolder: URL { didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) } }
    @Published var saveFormat: SaveFormat { didSet { defaults.set(saveFormat.rawValue, forKey: Key.saveFormat) } }
    @Published var jpegQuality: Double { didSet { defaults.set(jpegQuality, forKey: Key.jpegQuality) } }
    @Published var includeCursor: Bool { didSet { defaults.set(includeCursor, forKey: Key.includeCursor) } }
    @Published var includeWindowShadow: Bool { didSet { defaults.set(includeWindowShadow, forKey: Key.includeWindowShadow) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    /// 各工具上次使用的樣式，鍵為工具名稱（例如 "arrow"）。
    @Published var defaultStyles: [String: Style] { didSet { store(defaultStyles, for: Key.defaultStyles) } }

    private enum Key {
        static let hotKey = "hotKey"
        static let afterCapture = "afterCapture"
        static let saveFolder = "saveFolder"
        static let saveFormat = "saveFormat"
        static let jpegQuality = "jpegQuality"
        static let includeCursor = "includeCursor"
        static let includeWindowShadow = "includeWindowShadow"
        static let launchAtLogin = "launchAtLogin"
        static let defaultStyles = "defaultStyles"
    }

    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SnagItForever", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = Self.load(HotKeyCombo.self, from: defaults, key: Key.hotKey) ?? .default
        afterCapture = defaults.object(forKey: Key.afterCapture) == nil
            ? [.openEditor]
            : AfterCaptureActions(rawValue: defaults.integer(forKey: Key.afterCapture))
        saveFolder = defaults.string(forKey: Key.saveFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultSaveFolder
        saveFormat = defaults.string(forKey: Key.saveFormat).flatMap(SaveFormat.init(rawValue:)) ?? .png
        jpegQuality = defaults.object(forKey: Key.jpegQuality) == nil ? 0.9 : defaults.double(forKey: Key.jpegQuality)
        includeCursor = defaults.bool(forKey: Key.includeCursor)
        includeWindowShadow = defaults.bool(forKey: Key.includeWindowShadow)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        defaultStyles = Self.load([String: Style].self, from: defaults, key: Key.defaultStyles) ?? [:]
    }

    func defaultStyle(for tool: String) -> Style {
        defaultStyles[tool] ?? Style()
    }

    private func store<T: Encodable>(_ value: T, for key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
