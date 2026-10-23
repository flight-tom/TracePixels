import SnagItCore

/// 編輯器工具與單鍵快速鍵（見 contracts/commands.md）。
enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rectangle, ellipse, pen, highlighter, text, step, blur, pixelate

    var id: String { rawValue }

    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .step: "n"
        case .blur: "b"
        case .pixelate: "x"
        }
    }

    var title: String {
        switch self {
        case .select: String(localized: "選取")
        case .arrow: String(localized: "箭頭")
        case .line: String(localized: "線條")
        case .rectangle: String(localized: "矩形")
        case .ellipse: String(localized: "橢圓")
        case .pen: String(localized: "手繪筆")
        case .highlighter: String(localized: "螢光筆")
        case .text: String(localized: "文字")
        case .step: String(localized: "步驟標記")
        case .blur: String(localized: "模糊")
        case .pixelate: String(localized: "馬賽克")
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .step: "1.circle"
        case .blur: "drop"
        case .pixelate: "squareshape.split.3x3"
        }
    }

    /// 以「按下→拖曳」建立的形狀；手繪、步驟標記、選取不是。
    var draftShape: DraftShape? {
        switch self {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .blur: .blur
        case .pixelate: .pixelate
        case .text: .text
        case .select, .pen, .highlighter, .step: nil
        }
    }

    /// 該工具建立標註時的預設樣式（可被使用者上次的選擇覆蓋）。
    var factoryStyle: Style {
        switch self {
        case .highlighter: Style(color: .yellow, lineWidth: 8)
        default: Style()
        }
    }
}
