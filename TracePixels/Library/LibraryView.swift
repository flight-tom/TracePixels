import AppKit
import TracePixelsCore
import SwiftUI

/// 資料庫視窗：最近的擷取以縮圖列出，最新的在前。雙擊重新開啟，刪除前先確認。
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    /// 有檔案拖曳經過視窗時為真，用來顯示「可以放下」的強調邊框。
    @State private var isDropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    String(localized: "資料庫是空的"),
                    systemImage: "photo.on.rectangle",
                    description: Text("擷取的影像會自動出現在這裡，之後可以隨時重新開啟並繼續編輯。也可以按「匯入…」或把圖片拖曳到這個視窗。"))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(viewModel.entries) { entry in
                            LibraryCell(entry: entry, isSelected: viewModel.selection == entry.id)
                                .onTapGesture(count: 2) { viewModel.open(entry) }
                                .onTapGesture { viewModel.selection = entry.id }
                                .contextMenu {
                                    Button("開啟") { viewModel.open(entry) }.disabled(!entry.isUsable)
                                    Button("刪除…", role: .destructive) { viewModel.pendingDeletion = entry }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction(named: String(localized: "開啟")) { viewModel.open(entry) }
                                .accessibilityAction(named: String(localized: "刪除")) { viewModel.pendingDeletion = entry }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            HStack {
                Text("\(viewModel.entries.count) 個擷取")
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: viewModel.totalBytes, countStyle: .file))
                Spacer()
                Button("匯入…") { viewModel.importImages() }
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "匯入圖片"))
                    .help(String(localized: "把電腦上的圖片加入資料庫（⇧⌘I）"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 560, minHeight: 380)
        // 從 Finder 或其他 App 拖進圖片檔；只收檔案 URL，網頁圖片的 http(s) URL 交給核心分類並拒絕，不下載（FR-042、FR-044）。
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            viewModel.importDropped(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .task { await viewModel.reload() }
        // ⌫ 刪除目前選取的項目（會先跳出確認）。
        .onDeleteCommand {
            if let id = viewModel.selection, let entry = viewModel.entries.first(where: { $0.id == id }) {
                viewModel.pendingDeletion = entry
            }
        }
        .confirmationDialog(
            String(localized: "要永久刪除這個擷取嗎？"),
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) { viewModel.confirmDeletion() }
            Button("取消", role: .cancel) { viewModel.pendingDeletion = nil }
        } message: {
            Text("擷取與它的所有標註都會被刪除，無法復原。")
        }
    }
}

private struct LibraryCell: View {
    let entry: LibraryEntry
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    private var dateText: String {
        entry.createdAt.formatted(date: .abbreviated, time: .standard)
    }

    private var accessibilityText: String {
        guard entry.isUsable else { return String(localized: "無法讀取的擷取，\(dateText)") }
        if let name = entry.sourceFileName { return String(localized: "\(dateText)，匯入自 \(name)") }
        return dateText
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .underPageBackgroundColor))
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit().padding(6)
                } else if !entry.isUsable {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text("無法讀取").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))

            HStack(spacing: 4) {
                Text(dateText).font(.caption).lineLimit(1)
                if entry.sourceFileName != nil {
                    // 匯入的項目：小圖示標示來源，提示文字顯示原始檔名（FR-039）。
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .help(entry.sourceFileName ?? "")
        .task(id: entry.thumbnailURL) {
            guard let url = entry.thumbnailURL else { return }
            thumbnail = NSImage(contentsOf: url)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
