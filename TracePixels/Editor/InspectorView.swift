import TracePixelsCore
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
            if caps.isEmpty && viewModel.tool != .crop {
                Text("選擇工具或標註以調整樣式")
                    .foregroundStyle(.secondary)
            }

            if viewModel.tool == .crop || viewModel.capture.crop != nil {
                cropSection
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

            finishSection
            previewSection
        }
        .formStyle(.grouped)
    }

    // MARK: 裁切、修飾與預覽

    private var cropSection: some View {
        Section(String(localized: "裁切")) {
            if let crop = viewModel.capture.crop {
                Text("\(Int(crop.width.rounded())) × \(Int(crop.height.rounded())) 像素")
                    .monospacedDigit()
                Button("清除裁切") { viewModel.clearCrop() }
            } else {
                Text("在影像上拖曳出要保留的範圍。裁切不會修改原圖，可隨時復原。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var finishSection: some View {
        let finish = viewModel.capture.finish
        return Section(String(localized: "修飾")) {
            Toggle(String(localized: "邊框"), isOn: Binding(
                get: { finish.border != nil },
                set: { on in viewModel.setFinish { $0.border = on ? Finish.Border(color: .black, width: 4) : nil } }))
            if let border = finish.border {
                ColorPicker(String(localized: "邊框顏色"), selection: Binding(
                    get: { border.color.swiftUIColor },
                    set: { new in viewModel.setFinish { $0.border?.color = RGBAColor(new) } }), supportsOpacity: false)
                slider(String(localized: "邊框寬度"), value: border.width, range: 1...32) { value in
                    viewModel.setFinish { $0.border?.width = value }
                }
            }

            Toggle(String(localized: "陰影"), isOn: Binding(
                get: { finish.shadow != nil },
                set: { on in
                    viewModel.setFinish {
                        $0.shadow = on ? Finish.Shadow(blurRadius: 12, offsetX: 0, offsetY: 6, color: RGBAColor(r: 0, g: 0, b: 0, a: 0.4)) : nil
                    }
                }))
            if let shadow = finish.shadow {
                slider(String(localized: "模糊"), value: shadow.blurRadius, range: 0...40) { value in
                    viewModel.setFinish { $0.shadow?.blurRadius = value }
                }
                slider(String(localized: "垂直位移"), value: shadow.offsetY, range: -30...30) { value in
                    viewModel.setFinish { $0.shadow?.offsetY = value }
                }
            }

            slider(String(localized: "圓角"), value: finish.cornerRadius, range: 0...60) { value in
                viewModel.setFinish { $0.cornerRadius = value }
            }
        }
    }

    /// 套用裁切、縮放與修飾後的匯出預覽，與實際匯出的檔案一致。
    @ViewBuilder
    private var previewSection: some View {
        if let preview = viewModel.exportPreview {
            let size = viewModel.outputPixelSize
            Section(String(localized: "匯出預覽")) {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .accessibilityLabel(String(localized: "匯出預覽"))
                Text("\(size.width) × \(size.height) 像素")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
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
