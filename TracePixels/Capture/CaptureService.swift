import AppKit
import ScreenCaptureKit
import TracePixelsCore

enum CaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case windowNotFound
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: String(localized: "尚未授予螢幕擷取權限。")
        case .displayNotFound: String(localized: "找不到要擷取的顯示器。")
        case .windowNotFound: String(localized: "找不到要擷取的視窗，它可能已經關閉。")
        case let .underlying(error): error.localizedDescription
        }
    }
}

struct CaptureResult {
    let image: CGImage
    let source: CaptureSource
    /// 像素／點比例。
    let scale: Double
}

/// 以 ScreenCaptureKit 擷取單張截圖，輸出為顯示器的原生像素解析度（FR-003）。
final class CaptureService {
    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            let ns = error as NSError
            if ns.domain == SCStreamErrorDomain, ns.code == SCStreamError.userDeclined.rawValue {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.underlying(error)
        }
    }

    private func screenshot(_ filter: SCContentFilter, _ configuration: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            let ns = error as NSError
            if ns.domain == SCStreamErrorDomain, ns.code == SCStreamError.userDeclined.rawValue {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.underlying(error)
        }
    }

    private func excludedWindows(_ ids: [CGWindowID], in content: SCShareableContent) -> [SCWindow] {
        content.windows.filter { ids.contains($0.windowID) }
    }

    /// 擷取顯示器上的一塊區域。`excluding` 通常是自家的覆蓋層視窗。
    func captureRegion(
        _ selection: RegionSelection, excluding: [CGWindowID], includeCursor: Bool
    ) async throws -> CaptureResult {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows(excluding, in: content))
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(
            x: selection.sourceRect.x, y: selection.sourceRect.y,
            width: selection.sourceRect.width, height: selection.sourceRect.height)
        config.width = selection.pixelSize.width
        config.height = selection.pixelSize.height
        config.showsCursor = includeCursor
        config.captureResolution = .best
        let image = try await screenshot(filter, config)
        // 倍率直接用顯示器的值；不要用像素除以點反推（四捨五入會讓它變成 1.9996 這類不精確的數字）。
        return CaptureResult(image: image, source: .region, scale: selection.scale)
    }

    /// 擷取整個顯示器。
    func captureDisplay(
        _ info: DisplayInfo, excluding: [CGWindowID], includeCursor: Bool
    ) async throws -> CaptureResult {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == info.id }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows(excluding, in: content))
        let size = CaptureGeometry.pixelSize(of: info)
        let config = SCStreamConfiguration()
        config.width = size.width
        config.height = size.height
        config.showsCursor = includeCursor
        config.captureResolution = .best
        let image = try await screenshot(filter, config)
        let index = NSScreen.screens.firstIndex { $0.displayID == info.id } ?? 0
        return CaptureResult(image: image, source: .display(index: index), scale: info.scale)
    }

    /// 擷取單一視窗的完整內容，即使它被其他視窗遮擋。
    func captureWindow(
        _ candidate: WindowCandidate, includeShadow: Bool, includeCursor: Bool
    ) async throws -> CaptureResult {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == candidate.id }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let info = SCShareableContent.info(for: filter)
        let scale = Double(info.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((Double(info.contentRect.width) * scale).rounded()))
        config.height = max(1, Int((Double(info.contentRect.height) * scale).rounded()))
        config.showsCursor = includeCursor
        config.ignoreShadowsSingleWindow = !includeShadow
        config.captureResolution = .best
        let image = try await screenshot(filter, config)
        return CaptureResult(
            image: image,
            source: .window(title: candidate.title, appName: candidate.appName),
            scale: scale)
    }

    /// 取得顯示器的凍結畫面，供覆蓋層的放大鏡取樣。失敗時回傳 nil。
    func snapshot(displayID: CGDirectDisplayID, excluding: [CGWindowID]) async -> CGImage? {
        guard let content = try? await shareableContent(),
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows(excluding, in: content))
        let config = SCStreamConfiguration()
        let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        return try? await screenshot(filter, config)
    }
}
