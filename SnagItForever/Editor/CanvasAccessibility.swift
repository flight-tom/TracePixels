import AppKit
import SnagItCore

/// 畫布的 VoiceOver 支援：把每個標註公開成一個可導覽的項目，按下（VO-Space）即選取它。
final class AnnotationAccessibilityElement: NSAccessibilityElement {
    var onSelect: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}

extension Annotation {
    /// 給 VoiceOver 唸的描述：類型、內容與位置（影像像素座標）。
    var accessibilityDescription: String {
        let center = bounds.center
        let position = String(localized: "位置 \(Int(center.x)), \(Int(center.y))")
        let name: String
        switch kind {
        case .arrow: name = String(localized: "箭頭")
        case .line: name = String(localized: "線條")
        case .rectangle: name = String(localized: "矩形")
        case .ellipse: name = String(localized: "橢圓")
        case .pen: name = String(localized: "手繪線")
        case .highlighter: name = String(localized: "螢光標示")
        case let .text(_, string): name = String(localized: "文字：\(string)")
        case let .step(_, number): name = String(localized: "步驟標記 \(number)")
        case .blur: name = String(localized: "模糊遮蔽")
        case .pixelate: name = String(localized: "馬賽克遮蔽")
        }
        return "\(name)，\(position)"
    }
}

extension CanvasView {
    func configureAccessibility() {
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "影像畫布"))
    }

    /// 標註清單，由上到下（最上層的先唸）。
    func makeAccessibilityElements() -> [NSAccessibilityElement] {
        viewModel.capture.annotations.sorted { $0.zIndex > $1.zIndex }.map { annotation in
            let element = AnnotationAccessibilityElement()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(annotation.accessibilityDescription)
            element.setAccessibilitySelected(viewModel.selection.contains(annotation.id))
            element.setAccessibilityFrameInParentSpace(viewRect(annotation.bounds))
            let id = annotation.id
            element.onSelect = { [weak self] in
                MainActor.assumeIsolated {
                    self?.viewModel.setTool(.select)
                    self?.viewModel.selection = [id]
                }
            }
            return element
        }
    }
}
