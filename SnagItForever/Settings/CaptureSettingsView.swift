import AppKit
import SwiftUI

/// 偏好設定的「擷取」分頁：快速鍵、擷取後行為、游標與視窗陰影、預設儲存資料夾。
struct CaptureSettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var hotKeyController: HotKeyController

    var body: some View {
        Form {
            Section {
                LabeledContent("擷取快速鍵") {
                    HotKeyRecorder(combo: $preferences.hotKey)
                }
                if hotKeyController.registrationFailed {
                    Text("這組快速鍵已被其他程式占用，請換一組。")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("擷取後") {
                Toggle("在編輯器開啟", isOn: binding(.openEditor))
                Toggle("複製到剪貼簿", isOn: binding(.copyToClipboard))
                Toggle("儲存到預設資料夾", isOn: binding(.saveToFolder))
            }

            Section("內容") {
                Toggle("包含滑鼠游標", isOn: $preferences.includeCursor)
                Toggle("擷取視窗時包含陰影", isOn: $preferences.includeWindowShadow)
            }

            Section("預設儲存資料夾") {
                LabeledContent {
                    Button("選擇…", action: chooseFolder)
                } label: {
                    Text(preferences.saveFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ action: AfterCaptureActions) -> Binding<Bool> {
        Binding(
            get: { preferences.afterCapture.contains(action) },
            set: { isOn in
                if isOn { preferences.afterCapture.insert(action) } else { preferences.afterCapture.remove(action) }
            })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.saveFolder
        if panel.runModal() == .OK, let url = panel.url { preferences.saveFolder = url }
    }
}

/// 快速鍵錄製按鈕：點擊後按下新的組合鍵（需含 ⌃⌥⌘ 之一），Esc 取消。
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? String(localized: "請按下新的快速鍵…") : combo.displayString) {
            isRecording ? stop() : start()
        }
        .accessibilityLabel(String(localized: "擷取快速鍵"))
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
            } else if let new = HotKeyCombo(event: event) {
                combo = new
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
