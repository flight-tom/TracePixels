import Foundation

/// 放在擷取上的單一標記。幾何一律使用影像像素座標。
public struct Annotation: Codable, Hashable, Sendable, Identifiable {
    /// 模糊與馬賽克的最小磁磚大小；低於此值一律提升，確保輸出不可還原。
    public static let minimumRedactionStrength: Double = 8

    public enum Kind: Hashable, Sendable {
        case arrow(start: PixelPoint, end: PixelPoint)
        case line(start: PixelPoint, end: PixelPoint)
        case rectangle(rect: PixelRect, filled: Bool)
        case ellipse(rect: PixelRect, filled: Bool)
        case pen(points: [PixelPoint])
        case highlighter(points: [PixelPoint])
        case text(rect: PixelRect, string: String)
        case step(center: PixelPoint, number: Int)
        case blur(rect: PixelRect, strength: Double)
        case pixelate(rect: PixelRect, strength: Double)

        /// 契約中的 `kind.type` 名稱。
        public var typeName: String {
            switch self {
            case .arrow: "arrow"
            case .line: "line"
            case .rectangle: "rectangle"
            case .ellipse: "ellipse"
            case .pen: "pen"
            case .highlighter: "highlighter"
            case .text: "text"
            case .step: "step"
            case .blur: "blur"
            case .pixelate: "pixelate"
            }
        }

        /// 套用驗證規則後的版本（遮蔽強度下限）。
        func normalized() -> Kind {
            switch self {
            case let .blur(rect, strength):
                .blur(rect: rect, strength: max(strength, Annotation.minimumRedactionStrength))
            case let .pixelate(rect, strength):
                .pixelate(rect: rect, strength: max(strength, Annotation.minimumRedactionStrength))
            default:
                self
            }
        }
    }

    public var id: UUID
    public var zIndex: Int
    public var style: Style

    private var storedKind: Kind

    public var kind: Kind {
        get { storedKind }
        set { storedKind = newValue.normalized() }
    }

    public init(id: UUID = UUID(), zIndex: Int, kind: Kind, style: Style = Style()) {
        self.id = id
        self.zIndex = zIndex
        self.style = style
        self.storedKind = kind.normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case id, zIndex, kind, style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            zIndex: try c.decode(Int.self, forKey: .zIndex),
            kind: try c.decode(Kind.self, forKey: .kind),
            style: try c.decode(Style.self, forKey: .style))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(zIndex, forKey: .zIndex)
        try c.encode(kind, forKey: .kind)
        try c.encode(style, forKey: .style)
    }
}

/// 遇到本版本不認得的 `kind.type` 時丟出，讓呼叫端可略過該標註並保留原始 JSON。
struct UnknownAnnotationKind: Error {
    let typeName: String
}

extension Annotation.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, start, end, rect, filled, points, string, center, number, strength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "arrow":
            self = .arrow(start: try c.decode(PixelPoint.self, forKey: .start), end: try c.decode(PixelPoint.self, forKey: .end))
        case "line":
            self = .line(start: try c.decode(PixelPoint.self, forKey: .start), end: try c.decode(PixelPoint.self, forKey: .end))
        case "rectangle":
            self = .rectangle(rect: try c.decode(PixelRect.self, forKey: .rect), filled: try c.decodeIfPresent(Bool.self, forKey: .filled) ?? false)
        case "ellipse":
            self = .ellipse(rect: try c.decode(PixelRect.self, forKey: .rect), filled: try c.decodeIfPresent(Bool.self, forKey: .filled) ?? false)
        case "pen":
            self = .pen(points: try c.decode([PixelPoint].self, forKey: .points))
        case "highlighter":
            self = .highlighter(points: try c.decode([PixelPoint].self, forKey: .points))
        case "text":
            self = .text(rect: try c.decode(PixelRect.self, forKey: .rect), string: try c.decode(String.self, forKey: .string))
        case "step":
            self = .step(center: try c.decode(PixelPoint.self, forKey: .center), number: try c.decode(Int.self, forKey: .number))
        case "blur":
            self = .blur(rect: try c.decode(PixelRect.self, forKey: .rect), strength: try c.decode(Double.self, forKey: .strength))
        case "pixelate":
            self = .pixelate(rect: try c.decode(PixelRect.self, forKey: .rect), strength: try c.decode(Double.self, forKey: .strength))
        default:
            throw UnknownAnnotationKind(typeName: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case let .arrow(start, end), let .line(start, end):
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        case let .rectangle(rect, filled), let .ellipse(rect, filled):
            try c.encode(rect, forKey: .rect)
            try c.encode(filled, forKey: .filled)
        case let .pen(points), let .highlighter(points):
            try c.encode(points, forKey: .points)
        case let .text(rect, string):
            try c.encode(rect, forKey: .rect)
            try c.encode(string, forKey: .string)
        case let .step(center, number):
            try c.encode(center, forKey: .center)
            try c.encode(number, forKey: .number)
        case let .blur(rect, strength), let .pixelate(rect, strength):
            try c.encode(rect, forKey: .rect)
            try c.encode(strength, forKey: .strength)
        }
    }
}
