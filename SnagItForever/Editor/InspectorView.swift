import SnagItCore
import SwiftUI

/// 右側屬性面板：顏色、填滿、線條粗細、字型與字級、遮蔽強度。
/// 有選取的標註時作用於它們；否則設定「下一個標註」的預設樣式。
struct InspectorView: View {
    @ObservedObject var viewModel: EditorViewModel

    private enum Capability { case stroke, fill, text, step, redaction }

    private var capabilities: Set<Capability> {
        guard let kind = viewModel.inspectorKind else { return [] }
        switch kind {
        case .arrow, .line, .pen, .highlighter: return [.stroke]
        case .rectangle, .ellipse: return [.stroke, .fill]
        case .text: return [.text]
        case .step: return [.step]
        case .blur, .pixelate: return [.redaction]
        }
    }

    var body: some View {
        let style = viewModel.inspectorStyle
        let caps = capabilities
        Form {
            if caps.isEmpty {
                Text("選擇工具或標註以調整樣式")
                    .foregroundStyle(.secondary)
            }

            if !caps.isDisjoint(with: [.stroke, .text, .step]) {
                ColorPicker(
                    String(localized: "顏色"),
                    selection: Binding(
                        get: { style.color.swiftUIColor },
                        set: { new in viewModel.applyStyle { $0.color = RGBAColor(new) } }),
                    supportsOpacity: true)
            }

            if caps.contains(.stroke) {
                slider(String(localized: "粗細"), value: style.lineWidth, range: Style.lineWidthRange) { value in
                    viewModel.applyStyle { $0.lineWidth = value }
                }
            }

            if caps.contains(.fill) {
                Toggle(String(localized: "填滿"), isOn: Binding(
                    get: { isFilled },
                    set: { viewModel.setFilled($0) }))
                ColorPicker(
                    String(localized: "填滿顏色"),
                    selection: Binding(
                        get: { (style.fillColor ?? style.color).swiftUIColor },
                        set: { new in viewModel.applyStyle { $0.fillColor = RGBAColor(new) } }),
                    supportsOpacity: true)
            }

            if caps.contains(.step) {
                slider(String(localized: "大小"), value: style.lineWidth, range: Style.lineWidthRange) { value in
                    viewModel.applyStyle { $0.lineWidth = value }
                }
            }

            if caps.contains(.text) {
                Picker(String(localized: "字型"), selection: Binding(
                    get: { style.fontName },
                    set: { name in viewModel.applyStyle { $0.fontName = name } })) {
                    Text("系統").tag(Style.defaultFontName)
                    Text("PingFang TC").tag("PingFangTC-Regular")
                    Text("Helvetica Neue").tag("HelveticaNeue")
                    Text("Menlo").tag("Menlo-Regular")
                    Text("Georgia").tag("Georgia")
                }
                slider(String(localized: "字級"), value: style.fontSize, range: Style.fontSizeRange) { value in
                    viewModel.applyStyle { $0.fontSize = value }
                }
            }

            if caps.contains(.redaction) {
                slider(String(localized: "強度"), value: redactionStrength, range: Annotation.minimumRedactionStrength...64) { value in
                    viewModel.setRedactionStrength(value)
                }
                Text("遮蔽在匯出時會不可逆地改變像素。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var isFilled: Bool {
        switch viewModel.selectedAnnotations.first?.kind {
        case let .rectangle(_, filled), let .ellipse(_, filled): filled
        default: false
        }
    }

    private var redactionStrength: Double {
        switch viewModel.selectedAnnotations.first?.kind {
        case let .blur(_, strength), let .pixelate(_, strength): strength
        default: DraftShape.defaultRedactionStrength
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range,
                onEditingChanged: { editing in
                    // 拖曳滑桿的整段變更合併成一次復原。
                    if editing { viewModel.beginGesture() } else { viewModel.endGesture() }
                })
            .frame(width: 110)
            Text(Int(value.rounded()).formatted())
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
