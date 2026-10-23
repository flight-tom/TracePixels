import AppKit

/// 螢幕上可擷取的視窗。`frame` 為全域「點」座標、左上為原點。
struct WindowCandidate {
    let id: CGWindowID
    let frame: CGRect
    let title: String
    let appName: String
}

enum WindowPicker {
    /// 目前螢幕上的一般視窗，由前到後排序（`CGWindowListCopyWindowInfo` 只讀中繼資料，不擷取像素）。
    static func candidates(excluding excluded: Set<CGWindowID> = []) -> [WindowCandidate] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID, !excluded.contains(id),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width >= 40, frame.height >= 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }
            return WindowCandidate(
                id: id, frame: frame,
                title: info[kCGWindowName as String] as? String ?? "",
                appName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    /// 游標下最上層的視窗。
    static func topmost(at point: CGPoint, excluding excluded: Set<CGWindowID> = []) -> WindowCandidate? {
        candidates(excluding: excluded).first { $0.frame.contains(point) }
    }
}
