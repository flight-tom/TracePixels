import Foundation

public struct RGBAColor: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let red = RGBAColor(r: 1, g: 0, b: 0)
    public static let black = RGBAColor(r: 0, g: 0, b: 0)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)
    public static let yellow = RGBAColor(r: 1, g: 0.9, b: 0)
}

/// 標註的外觀。`lineWidth` 與 `fontSize` 一律夾限在允許範圍內。
public struct Style: Codable, Hashable, Sendable {
    public static let lineWidthRange: ClosedRange<Double> = 1...64
    public static let fontSizeRange: ClosedRange<Double> = 8...400
    public static let defaultFontName = ".AppleSystemUIFont"

    public var color: RGBAColor
    public var fillColor: RGBAColor?
    public var fontName: String

    private var storedLineWidth: Double
    private var storedFontSize: Double

    /// 像素，範圍 1–64。
    public var lineWidth: Double {
        get { storedLineWidth }
        set { storedLineWidth = Style.clamp(newValue, to: Style.lineWidthRange) }
    }

    /// 像素，範圍 8–400。
    public var fontSize: Double {
        get { storedFontSize }
        set { storedFontSize = Style.clamp(newValue, to: Style.fontSizeRange) }
    }

    public init(
        color: RGBAColor = .red,
        fillColor: RGBAColor? = nil,
        lineWidth: Double = 4,
        fontName: String = Style.defaultFontName,
        fontSize: Double = 24
    ) {
        self.color = color
        self.fillColor = fillColor
        self.fontName = fontName
        self.storedLineWidth = Style.clamp(lineWidth, to: Style.lineWidthRange)
        self.storedFontSize = Style.clamp(fontSize, to: Style.fontSizeRange)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case color, fillColor, lineWidth, fontName, fontSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            color: try c.decode(RGBAColor.self, forKey: .color),
            fillColor: try c.decodeIfPresent(RGBAColor.self, forKey: .fillColor),
            lineWidth: try c.decode(Double.self, forKey: .lineWidth),
            fontName: try c.decodeIfPresent(String.self, forKey: .fontName) ?? Style.defaultFontName,
            fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 24)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color, forKey: .color)
        try c.encode(fillColor, forKey: .fillColor)
        try c.encode(lineWidth, forKey: .lineWidth)
        try c.encode(fontName, forKey: .fontName)
        try c.encode(fontSize, forKey: .fontSize)
    }
}
