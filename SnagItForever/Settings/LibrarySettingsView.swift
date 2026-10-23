import SnagItCore
import SwiftUI

/// 偏好設定的「資料庫」分頁：顯示佔用空間，並提供手動「清除 N 天前的擷取」。
/// 資料庫不會自動刪除任何東西（FR-020）。
struct LibrarySettingsView: View {
    let library: LibraryStore

    @State private var count = 0
    @State private var bytes: Int64 = 0
    @State private var days = 30
    @State private var pendingCount: Int?
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section("目前使用量") {
                LabeledContent("擷取數量", value: "\(count)")
                LabeledContent("佔用空間", value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
            Section("手動清除") {
                Stepper(value: $days, in: 1...3650) {
                    Text("清除 \(days) 天前的擷取")
                }
                Button("清除…") { Task { await prepareClear() } }
                Text("資料庫不會自動刪除任何擷取，只有你在這裡確認後才會刪除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let resultMessage {
                    Text(resultMessage).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
            Task { await refresh() }
        }
        .confirmationDialog(
            String(localized: "要永久刪除 \(pendingCount ?? 0) 個擷取嗎？"),
            isPresented: Binding(get: { pendingCount != nil }, set: { if !$0 { pendingCount = nil } }),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) { Task { await clear() } }
            Button("取消", role: .cancel) { pendingCount = nil }
        } message: {
            Text("這些擷取與它們的標註會被刪除，無法復原。")
        }
    }

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func refresh() async {
        count = await library.list().count
        bytes = await library.totalSize()
    }

    private func prepareClear() async {
        resultMessage = nil
        let cutoff = cutoff
        let matching = await library.list().filter { $0.isUsable && $0.createdAt < cutoff }.count
        if matching == 0 {
            resultMessage = String(localized: "沒有符合的擷取。")
        } else {
            pendingCount = matching
        }
    }

    private func clear() async {
        pendingCount = nil
        do {
            let removed = try await library.deleteOlder(than: cutoff)
            resultMessage = String(localized: "已刪除 \(removed) 個擷取。")
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}
