import Foundation

public enum CaptureSource: Codable, Hashable, Sendable {
    case region
    case window(title: String, appName: String)
    case display(index: Int)

    private enum CodingKeys: String, CodingKey {
        case type, title, appName, index
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "window":
            self = .window(
                title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                appName: try c.decodeIfPresent(String.self, forKey: .appName) ?? "")
        case "display":
            self = .display(index: try c.decodeIfPresent(Int.self, forKey: .index) ?? 0)
        default:
            self = .region
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .region:
            try c.encode("region", forKey: .type)
        case let .window(title, appName):
            try c.encode("window", forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(appName, forKey: .appName)
        case let .display(index):
            try c.encode("display", forKey: .type)
            try c.encode(index, forKey: .index)
        }
    }
}

/// 匯出時套用的修飾。
public struct Finish: Codable, Hashable, Sendable {
    public struct Border: Codable, Hashable, Sendable {
        public var color: RGBAColor
        public var width: Double

        public init(color: RGBAColor, width: Double) {
            self.color = color
            self.width = width
        }
    }

    public struct Shadow: Codable, Hashable, Sendable {
        public var blurRadius: Double
        public var offsetX: Double
        public var offsetY: Double
        public var color: RGBAColor

        public init(blurRadius: Double, offsetX: Double, offsetY: Double, color: RGBAColor) {
            self.blurRadius = blurRadius
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.color = color
        }
    }

    public var border: Border?
    public var shadow: Shadow?
    public var cornerRadius: Double

    public init(border: Border? = nil, shadow: Shadow? = nil, cornerRadius: Double = 0) {
        self.border = border
        self.shadow = shadow
        self.cornerRadius = cornerRadius
    }

    public static let none = Finish()
}

public enum CaptureValidationError: Error, Equatable {
    case invalidPixelSize
    case cropOutOfBounds
    case duplicateAnnotationIDs
}

/// 某個時間點拍下的螢幕截圖，連同其標註與匯出設定。原始像素另存於 `image.png`，永不修改。
public struct Capture: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1
    public static let outputScaleRange: ClosedRange<Double> = 0.1...4.0

    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var source: CaptureSource
    public var pixelSize: PixelSize
    public var scale: Double
    public var annotations: [Annotation]
    /// 非破壞性裁切範圍；nil 表示不裁切。
    public var crop: PixelRect?
    public var finish: Finish

    /// 本版本不認得的標註，原樣保留並在儲存時寫回。
    var unknownAnnotations: [JSONValue]

    private var storedOutputScale: Double

    /// 匯出縮放比例，範圍 0.1–4.0。
    public var outputScale: Double {
        get { storedOutputScale }
        set { storedOutputScale = Capture.clampOutputScale(newValue) }
    }

    private static func clampOutputScale(_ value: Double) -> Double {
        min(max(value, outputScaleRange.lowerBound), outputScaleRange.upperBound)
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        source: CaptureSource,
        pixelSize: PixelSize,
        scale: Double,
        annotations: [Annotation] = []
    ) {
        self.schemaVersion = Capture.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.source = source
        self.pixelSize = pixelSize
        self.scale = scale
        self.annotations = annotations
        self.crop = nil
        self.finish = .none
        self.unknownAnnotations = []
        self.storedOutputScale = 1.0
    }

    /// 檢查資料模型的驗證規則。
    public func validate() throws {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            throw CaptureValidationError.invalidPixelSize
        }
        if let crop {
            let r = crop.normalized
            let inside = r.minX >= 0 && r.minY >= 0
                && r.maxX <= Double(pixelSize.width) && r.maxY <= Double(pixelSize.height)
            guard inside, r.width >= 1, r.height >= 1 else {
                throw CaptureValidationError.cropOutOfBounds
            }
        }
        guard Set(annotations.map(\.id)).count == annotations.count else {
            throw CaptureValidationError.duplicateAnnotationIDs
        }
    }

    // MARK: JSON

    /// 磁碟格式使用的編碼器：ISO 8601 日期、排序鍵、易讀排版。
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, modifiedAt, source, pixelSize, scale
        case annotations, crop, outputScale, finish
    }

    /// 解碼單一標註；不認得的類型記為 `.unknown`，其餘解碼錯誤照常丟出。
    private enum AnnotationSlot: Decodable {
        case known(Annotation)
        case unknown(JSONValue)

        init(from decoder: Decoder) throws {
            do {
                self = .known(try Annotation(from: decoder))
            } catch is UnknownAnnotationKind {
                self = .unknown(try JSONValue(from: decoder))
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        source = try c.decode(CaptureSource.self, forKey: .source)
        pixelSize = try c.decode(PixelSize.self, forKey: .pixelSize)
        scale = try c.decode(Double.self, forKey: .scale)
        crop = try c.decodeIfPresent(PixelRect.self, forKey: .crop)
        finish = try c.decodeIfPresent(Finish.self, forKey: .finish) ?? .none
        storedOutputScale = Capture.clampOutputScale(
            try c.decodeIfPresent(Double.self, forKey: .outputScale) ?? 1.0)

        var known: [Annotation] = []
        var unknown: [JSONValue] = []
        for slot in try c.decode([AnnotationSlot].self, forKey: .annotations) {
            switch slot {
            case let .known(a): known.append(a)
            case let .unknown(v): unknown.append(v)
            }
        }
        annotations = known
        unknownAnnotations = unknown
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(source, forKey: .source)
        try c.encode(pixelSize, forKey: .pixelSize)
        try c.encode(scale, forKey: .scale)
        try c.encode(crop, forKey: .crop)
        try c.encode(outputScale, forKey: .outputScale)
        try c.encode(finish, forKey: .finish)

        var list = c.nestedUnkeyedContainer(forKey: .annotations)
        for a in annotations { try list.encode(a) }
        for u in unknownAnnotations { try list.encode(u) }
    }
}
