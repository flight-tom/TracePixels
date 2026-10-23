import CoreGraphics

/// 跨 actor 傳遞 `CGImage` 的包裝。`CGImage` 建立後不可變，因此這樣做是安全的。
public struct SendableImage: @unchecked Sendable {
    public let cgImage: CGImage

    public init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }
}
