import AppKit
import SwiftUI

/// 工具列上的分享按鈕：以 macOS 標準的分享選單送出合成後的影像（FR-019）。
struct ShareButton: View {
    let share: (NSView) -> Void
    @State private var anchor = AnchorBox()

    var body: some View {
        Button {
            if let view = anchor.view { share(view) }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .background(ShareAnchor(box: anchor))
        .help(String(localized: "分享…"))
        .accessibilityLabel(String(localized: "分享"))
    }

    final class AnchorBox {
        weak var view: NSView?
    }

    private struct ShareAnchor: NSViewRepresentable {
        let box: AnchorBox

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            box.view = view
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            box.view = nsView
        }
    }
}
