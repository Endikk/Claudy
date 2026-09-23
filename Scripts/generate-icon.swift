#!/usr/bin/env swift
//
// Generates Claudy/Assets.xcassets/AppIcon.appiconset from the vector Claude
// mark (the app icon; the widget itself shows the pixel mascot, ClaudyTyping).
//
//   swift Scripts/generate-icon.swift
//
// Re-run only when the mark or the icon style changes: the generated PNGs
// are committed, so nobody else needs to run this script.

import AppKit

// Rays of the mark: (angle in degrees, relative length, relative half-width).
let rays: [(angle: Double, length: Double, width: Double)] = [
    (0, 1.00, 0.150), (33, 0.76, 0.120), (72, 0.94, 0.140),
    (104, 0.68, 0.112), (145, 1.00, 0.150), (180, 0.80, 0.128),
    (212, 0.94, 0.140), (250, 0.70, 0.112), (288, 1.00, 0.150),
    (320, 0.78, 0.126), (350, 0.66, 0.108),
]

func markPath(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let innerRadius = radius * 0.06

    for ray in rays {
        let radians = ray.angle * .pi / 180
        let direction = CGVector(dx: cos(radians), dy: sin(radians))
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)

        let outerRadius = radius * ray.length
        let baseHalf = radius * ray.width
        let tipHalf = baseHalf * 0.34

        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + direction.dx * along + normal.dx * across,
                y: center.y + direction.dy * along + normal.dy * across
            )
        }

        path.move(to: point(innerRadius, baseHalf))
        path.addLine(to: point(outerRadius - tipHalf, tipHalf))
        path.addQuadCurve(
            to: point(outerRadius - tipHalf, -tipHalf),
            control: point(outerRadius + tipHalf * 0.6, 0)
        )
        path.addLine(to: point(innerRadius, -baseHalf))
        path.closeSubpath()
    }
    return path
}

let coral = NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.341, alpha: 1) // #D97757

func render(pixels: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("bitmap context unavailable")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let side = CGFloat(pixels)

    // macOS icon grid: centred 824/1024 square, ~185/1024 corners.
    let inset = side * (100.0 / 1024.0)
    let square = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let corner = side * (185.0 / 1024.0)
    cg.addPath(CGPath(roundedRect: square, cornerWidth: corner, cornerHeight: corner, transform: nil))
    cg.clip()

    // Background: dark gradient, same family as the widget card.
    let space = CGColorSpaceCreateDeviceRGB()
    let background = CGGradient(
        colorsSpace: space,
        colors: [
            NSColor(calibratedRed: 0.165, green: 0.153, blue: 0.147, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.071, green: 0.063, blue: 0.059, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    cg.drawLinearGradient(
        background,
        start: CGPoint(x: square.minX, y: square.maxY),
        end: CGPoint(x: square.maxX, y: square.minY),
        options: []
    )

    // Coral halo behind the mark.
    let halo = CGGradient(
        colorsSpace: space,
        colors: [coral.withAlphaComponent(0.32).cgColor, coral.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    let middle = CGPoint(x: side / 2, y: side / 2)
    cg.drawRadialGradient(halo, startCenter: middle, startRadius: 0,
                          endCenter: middle, endRadius: square.width * 0.55, options: [])

    // Sunburst.
    cg.setFillColor(coral.cgColor)
    cg.addPath(markPath(center: middle, radius: square.width * 0.31))
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Writing the catalog

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Claudy/Assets.xcassets")
let iconset = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

try #"{"info":{"author":"xcode","version":1}}"#
    .write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let sizes = [16, 32, 128, 256, 512]
var images: [[String: String]] = []

for size in sizes {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let rep = render(pixels: size * scale)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("PNG export failed for \(name)")
        }
        try png.write(to: iconset.appendingPathComponent(name))
        images.append([
            "filename": name,
            "idiom": "mac",
            "scale": "\(scale)x",
            "size": "\(size)x\(size)",
        ])
        print("▸ \(name)")
    }
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconset.appendingPathComponent("Contents.json"))
print("▸ \(iconset.path)")
