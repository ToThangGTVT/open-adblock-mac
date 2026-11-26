#!/usr/bin/env swift
// Renders the app icon from the Android app's design (open-adblock: design/blockads-icon.svg)
// into App/Assets.xcassets/AppIcon.appiconset: the same shield, card and lime background, laid
// out on the macOS icon grid (824 pt rounded square centred on a 1024 pt canvas, with a shadow).
//
//   swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")

// Paths and colours copied from the Android design (512 × 512 artboard).
let card = "M191.014 216H417.986C429.995 216 436 221.646 436 232.939V365.061C436 376.354 429.995 382 417.986 382H191.014C179.005 382 173 376.354 173 365.061V232.939C173 221.646 179.005 216 191.014 216Z"
let shield = "M190.8 97C160.2 116.55 127.05 127.6 99 132.7V203.25C99 256.8 130.45 296.75 184 323.95C188.25 326.5 193.35 326.5 197.6 323.95C251.15 296.75 282.6 256.8 282.6 203.25V132.7C254.55 127.6 221.4 116.55 190.8 97Z"
let lime = CGColor(srgbRed: 0xCC / 255, green: 0xF6 / 255, blue: 0x6B / 255, alpha: 1)
let green = CGColor(srgbRed: 0x80 / 255, green: 0xB9 / 255, blue: 0x4D / 255, alpha: 1)
let highlight = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2)
let ink = CGColor(srgbRed: 0x0B / 255, green: 0x3D / 255, blue: 0x2E / 255, alpha: 1)

/// Parses the absolute M/H/V/C/Z commands the design uses.
func path(_ data: String) -> CGPath {
    let path = CGMutablePath()
    var numbers: [CGFloat] = []
    var command: Character = " "
    var current = CGPoint.zero
    func flush() {
        switch command {
        case "M":
            current = CGPoint(x: numbers[0], y: numbers[1])
            path.move(to: current)
        case "H":
            current.x = numbers[0]
            path.addLine(to: current)
        case "V":
            current.y = numbers[0]
            path.addLine(to: current)
        case "C":
            for i in stride(from: 0, to: numbers.count, by: 6) {
                current = CGPoint(x: numbers[i + 4], y: numbers[i + 5])
                path.addCurve(
                    to: current, control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                    control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
            }
        case "Z":
            path.closeSubpath()
        default:
            break
        }
        numbers = []
    }
    var token = ""
    for character in data + " " {
        if character.isLetter {
            if let value = Double(token) { numbers.append(value) }
            token = ""
            flush()
            command = character
        } else if character == " " || character == "," {
            if let value = Double(token) { numbers.append(value) }
            token = ""
        } else {
            token.append(character)
        }
    }
    flush()
    return path
}

func render(pixels: Int) -> Data {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    // SVG coordinates grow downwards.
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)

    // macOS grid: 824 × 824 body at (100, 100), corner radius as in the design (116 / 512).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius = 116 * 824 / 512.0
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: 10), blur: 28,
        color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(lime)
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    context.translateBy(x: 100, y: 100)
    context.scaleBy(x: 824 / 512.0, y: 824 / 512.0)
    for colour in [green, highlight] {
        context.addPath(path(card))
        context.setFillColor(colour)
        context.fillPath()
    }
    context.addPath(path(shield))
    context.setStrokeColor(ink)
    context.setLineWidth(27.2)
    context.setLineJoin(.round)
    context.strokePath()

    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    return image.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append([
            "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name,
        ])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) images to \(output.path)")
