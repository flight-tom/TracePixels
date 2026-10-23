import SwiftUI

/// 偏好設定的「輸出」分頁：預設格式與 JPEG 品質。
struct ExportSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Picker("預設格式", selection: $preferences.saveFormat) {
                Text("PNG").tag(SaveFormat.png)
                Text("JPEG").tag(SaveFormat.jpeg)
            }
            LabeledContent("JPEG 品質") {
                Slider(value: $preferences.jpegQuality, in: 0.1...1)
                    .frame(width: 180)
                Text("\(Int((preferences.jpegQuality * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(preferences.saveFormat != .jpeg)
            Text("檔名格式為「TracePixels 年-月-日 時.分.秒」，重名時自動加上序號。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
