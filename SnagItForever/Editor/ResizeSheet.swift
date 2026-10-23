import SwiftUI

/// 調整匯出大小：輸入寬或高（像素），另一邊依比例換算，結果存成輸出縮放比例。
struct ResizeSheet: View {
    @ObservedObject var viewModel: EditorViewModel
    let dismiss: () -> Void

    @State private var width = 0
    @State private var height = 0

    /// 縮放前（裁切後）的基準尺寸。
    private var base: (width: Double, height: Double) {
        let r = viewModel.capture.crop?.normalized ?? viewModel.capture.pixelSize.rect
        return (r.width, r.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("調整輸出大小").font(.headline)
            Text("原始大小 \(Int(base.width.rounded())) × \(Int(base.height.rounded())) 像素。縮放只影響匯出，原圖與標註不會被修改。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("寬度")
                    TextField("", value: $width, format: .number)
                        .frame(width: 90)
                        .onSubmit { fromWidth() }
                    Text("像素")
                }
                GridRow {
                    Text("高度")
                    TextField("", value: $height, format: .number)
                        .frame(width: 90)
                        .onSubmit { fromHeight() }
                    Text("像素")
                }
            }
            Text("比例為 \(String(format: "%.0f%%", viewModel.capture.outputScale * 100))（範圍 10%–400%）")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("還原 100%") {
                    viewModel.setOutputScale(1)
                    dismiss()
                }
                Spacer()
                Button("取消", action: dismiss).keyboardShortcut(.cancelAction)
                Button("套用") {
                    // 以最後編輯的欄位為準；兩欄都沒動時維持目前比例。
                    viewModel.setOutputScale(pendingScale)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            width = Int((base.width * viewModel.capture.outputScale).rounded())
            height = Int((base.height * viewModel.capture.outputScale).rounded())
        }
        .onChange(of: width) { _, _ in lastEdited = .width }
        .onChange(of: height) { _, _ in lastEdited = .height }
    }

    private enum Axis { case width, height }
    @State private var lastEdited: Axis?

    private var pendingScale: Double {
        switch lastEdited {
        case .width: Double(max(width, 1)) / base.width
        case .height: Double(max(height, 1)) / base.height
        case nil: viewModel.capture.outputScale
        }
    }

    private func fromWidth() {
        lastEdited = .width
        height = max(1, Int((base.height * Double(max(width, 1)) / base.width).rounded()))
    }

    private func fromHeight() {
        lastEdited = .height
        width = max(1, Int((base.width * Double(max(height, 1)) / base.height).rounded()))
    }
}
