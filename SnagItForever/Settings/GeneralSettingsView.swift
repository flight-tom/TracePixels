import ServiceManagement
import SwiftUI

/// 偏好設定的「一般」分頁：登入時啟動（預設關閉，FR-029）。
struct GeneralSettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var message: String?

    var body: some View {
        Form {
            Toggle("登入時啟動", isOn: Binding(
                get: { preferences.launchAtLogin },
                set: { setLaunchAtLogin($0) }))
            Text("開啟後，登入 Mac 時 SnagItForever 會自動在選單列待命。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .onAppear { syncWithSystem() }
    }

    /// 系統才是事實來源：使用者可能已在「系統設定 › 登入項目」改過。
    private func syncWithSystem() {
        preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = SMAppService.mainApp.status == .requiresApproval
                ? String(localized: "請到「系統設定 › 一般 › 登入項目與延伸功能」允許 SnagItForever。")
                : nil
        } catch {
            message = String(localized: "無法變更登入時啟動：\(error.localizedDescription)")
        }
        syncWithSystem()
    }
}
