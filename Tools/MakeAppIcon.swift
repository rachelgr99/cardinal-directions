// Renders the app icon PNG so the asset catalog doesn't need a design tool.
// Usage: swift Tools/MakeAppIcon.swift <output.png>

import AppKit

let size = 1024.0
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xE4002B), color(0x8C1515), color(0x2A0508)] as CFArray,
    locations: [0, 0.55, 1]
)!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])

// Glow behind the mark.
context.setFillColor(CGColor(red: 1, green: 0.87, blue: 0.36, alpha: 0.18))
context.fillEllipse(in: CGRect(x: size * 0.1, y: size * 0.42, width: size * 0.8, height: size * 0.8))

// Compass needle pointing north-east: "cardinal direction".
context.saveGState()
context.translateBy(x: size / 2, y: size / 2)
context.rotate(by: .pi / 4)
let needle = CGMutablePath()
needle.move(to: CGPoint(x: 0, y: size * 0.30))
needle.addLine(to: CGPoint(x: size * 0.13, y: -size * 0.06))
needle.addLine(to: CGPoint(x: 0, y: 0))
needle.addLine(to: CGPoint(x: -size * 0.13, y: -size * 0.06))
needle.closeSubpath()
context.addPath(needle)
context.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.96, alpha: 1))
context.fillPath()

let tail = CGMutablePath()
tail.move(to: CGPoint(x: 0, y: -size * 0.30))
tail.addLine(to: CGPoint(x: size * 0.13, y: size * 0.06))
tail.addLine(to: CGPoint(x: 0, y: 0))
tail.addLine(to: CGPoint(x: -size * 0.13, y: size * 0.06))
tail.closeSubpath()
context.addPath(tail)
context.setFillColor(color(0xFEDD5C))
context.fillPath()
context.restoreGState()

guard let image = context.makeImage() else { exit(1) }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outputPath))
