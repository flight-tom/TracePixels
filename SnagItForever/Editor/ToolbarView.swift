import SwiftUI

/// 編輯器上方的工具列。每個按鈕都有說明文字與 VoiceOver 標籤；工具的單鍵快速鍵見 contracts/commands.md。
struct ToolbarView: View {
    @ObservedObject var viewModel: EditorViewModel
    var actions: EditorWindowActions

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    viewModel.setTool(tool)
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 22)
                        .background(
                            viewModel.tool == tool ? Color.accentColor.opacity(0.3) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(tool.key.uppercased()))")
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(viewModel.tool == tool ? .isSelected : [])
            }

            Divider().frame(height: 18).padding(.horizontal, 4)

            iconButton("arrow.uturn.backward", String(localized: "復原"), enabled: viewModel.canUndo) { viewModel.undo() }
            iconButton("arrow.uturn.forward", String(localized: "重做"), enabled: viewModel.canRedo) { viewModel.redo() }

            Divider().frame(height: 18).padding(.horizontal, 4)

            iconButton("minus.magnifyingglass", String(localized: "縮小")) { actions.zoomOut() }
            iconButton("plus.magnifyingglass", String(localized: "放大")) { actions.zoomIn() }
            iconButton("arrow.up.left.and.down.right.magnifyingglass", String(localized: "符合視窗")) { actions.zoomToFit() }

            Divider().frame(height: 18).padding(.horizontal, 4)

            iconButton("doc.on.doc", String(localized: "複製影像")) { actions.copyImage() }
            iconButton("square.and.arrow.down", String(localized: "另存新檔…")) { actions.saveAs() }
            ShareButton(share: actions.share)
            DragExportHandle(payload: actions.dragPayload)
                .frame(width: 26, height: 22)

            Spacer()

            if let warning = viewModel.saveWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(warning)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func iconButton(_ symbol: String, _ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(title)
        .accessibilityLabel(title)
    }
}
