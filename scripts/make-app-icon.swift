#!/usr/bin/env swift
// 產生 App 圖示：`swift scripts/make-app-icon.swift <輸出資料夾>`
// 以 CoreGraphics 向量繪製，每個尺寸各自渲染（不是縮圖），小尺寸也銳利。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

/// macOS 圖示底板的近似連續曲率圓角（超橢圓）。
func squircle(_ rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + rect.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// 在 1024×1024 的設計座標（原點在左上）繪製，再縮放到目標尺寸。
func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = squircle(tile)

    // 底板陰影（在未翻轉的座標系，偏移向下）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.38))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(0.1, 0.12, 0.45)); ctx.fillPath()
    ctx.restoreGState()

    // 之後改用左上為原點
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)

    // 底板：由上到下的靛藍漸層
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [rgb(0.36, 0.49, 1.0), rgb(0.17, 0.17, 0.63)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // 左上角的柔光
    let glow = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 220), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 220), endRadius: 560, options: [])

    // 像素格：4×4，階梯狀的亮格是「被描摹的像素」
    let cell: CGFloat = 94, gap: CGFloat = 10, origin: CGFloat = 512 - (4 * cell + 3 * gap) / 2
    let stair: Set<[Int]> = [[3, 0], [3, 1], [2, 1], [2, 2], [1, 2], [1, 3], [0, 3]]
    for r in 0..<4 {
        for c in 0..<4 {
            let rect = CGRect(x: origin + CGFloat(c) * (cell + gap), y: origin + CGFloat(r) * (cell + gap), width: cell, height: cell)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.setFillColor(stair.contains([r, c]) ? rgb(1, 1, 1, 0.92) : rgb(1, 1, 1, 0.14))
            ctx.fillPath()
        }
    }

    // 取景框四角
    ctx.setStrokeColor(rgb(1, 1, 1, 0.96)); ctx.setLineWidth(44); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let lo: CGFloat = 196, hi: CGFloat = 828, arm: CGFloat = 150
    for (x, y, dx, dy) in [(lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0), (lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        ctx.move(to: CGPoint(x: x + dx * arm, y: y)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x, y: y + dy * arm))
        ctx.strokePath()
    }

    // 描摹線：把像素階梯描成一條平滑的 S 形線，終點是向量編輯的錨點
    let start = CGPoint(x: 356, y: 668), end = CGPoint(x: 668, y: 356)
    let coral = rgb(1.0, 0.42, 0.29)
    let line = CGMutablePath()
    line.move(to: start)
    line.addCurve(to: end, control1: CGPoint(x: 548, y: 668), control2: CGPoint(x: 476, y: 356))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: rgb(0.05, 0.05, 0.3, 0.5))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(coral); ctx.setLineWidth(40); ctx.setLineCap(.round)
    ctx.addPath(line); ctx.strokePath()
    ctx.setFillColor(rgb(1, 1, 1)); ctx.setStrokeColor(coral); ctx.setLineWidth(24)
    ctx.addEllipse(in: CGRect(x: end.x - 38, y: end.y - 38, width: 76, height: 76))
    ctx.drawPath(using: .fillStroke)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "無法寫入 \(url.path)")
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：swift scripts/make-app-icon.swift <輸出資料夾>\n".utf8)); exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    write(render(pixels: px), to: out.appendingPathComponent("icon_\(px).png"))
}
print("已輸出到 \(out.path)")
