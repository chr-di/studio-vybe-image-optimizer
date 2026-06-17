#!/usr/bin/env swift
//
// make-appicon.swift — render a Studio Vybe logo SVG into a macOS .iconset.
//
// Draws the (cream) brand monogram centered on a warm-dark squircle, at every
// size macOS expects, then leaves iconutil (called by the wrapper) to assemble
// AppIcon.icns. No external rasterizer needed — NSImage renders the SVG.
//
// Usage: swift make-appicon.swift <svg-path> <iconset-dir> [logoFraction]
//
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make-appicon.swift <svg> <iconset-dir> [logoFraction]\n".data(using: .utf8)!)
    exit(64)
}
let svgPath = args[1]
let iconsetDir = args[2]
let logoFraction = args.count > 3 ? (Double(args[3]) ?? 0.6) : 0.6

guard let logo = NSImage(contentsOfFile: svgPath), logo.size.width > 1 else {
    FileHandle.standardError.write("Failed to load SVG (NSImage): \(svgPath)\n".data(using: .utf8)!)
    exit(2)
}

// Warm-dark brand background (#352f36)
let bg = NSColor(srgbRed: 0x35 / 255.0, green: 0x2f / 255.0, blue: 0x36 / 255.0, alpha: 1)

func renderIcon(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let f = CGFloat(px)
    let margin = f * 0.085                      // slight inset, like native app icons
    let body = NSRect(x: margin, y: margin, width: f - 2 * margin, height: f - 2 * margin)
    let radius = body.width * 0.2237            // macOS squircle corner ratio
    let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    bg.setFill()
    squircle.fill()

    let logoSize = body.width * CGFloat(logoFraction)
    let logoRect = NSRect(
        x: body.midX - logoSize / 2,
        y: body.midY - logoSize / 2,
        width: logoSize, height: logoSize
    )
    logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("PNG encode failed for \(path)\n".data(using: .utf8)!)
        exit(3)
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    writePNG(renderIcon(px), "\(iconsetDir)/\(name).png")
}

// Also drop a standalone 256 preview next to the iconset for quick inspection.
let previewDir = (iconsetDir as NSString).deletingLastPathComponent
writePNG(renderIcon(256), "\(previewDir)/icon-preview-256.png")

print("Wrote \(sizes.count) PNGs to \(iconsetDir)")
