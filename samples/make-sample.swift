#!/usr/bin/env swift
//
// make-sample.swift — generate a synthetic, self-made (CC0 / public domain) test image.
// Not a photo and not derived from any copyrighted source — purely procedural, so it can
// be redistributed freely. Produces samples/sample.png.
//
// Usage: swift samples/make-sample.swift [out.png] [width] [height]
//
import AppKit
import Foundation

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "samples/sample.png"
let w = args.count > 2 ? (Int(args[2]) ?? 1600) : 1600
let h = args.count > 3 ? (Int(args[3]) ?? 1200) : 1200

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Diagonal gradient backdrop
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.83, green: 0.65, blue: 0.45, alpha: 1),
    CGColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])

// Scatter translucent shapes (deterministic pseudo-random, no Math.random dependency)
var seed: UInt64 = 0x5DEECE66D
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
for _ in 0..<140 {
    let r = CGFloat(20 + rnd() * 160)
    let x = CGFloat(rnd() * Double(w)), y = CGFloat(rnd() * Double(h))
    ctx.setFillColor(CGColor(red: CGFloat(rnd()), green: CGFloat(rnd()), blue: CGFloat(rnd()), alpha: 0.16))
    if rnd() < 0.5 {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    } else {
        ctx.fill(CGRect(x: x, y: y, width: r * 1.6, height: r * 1.1))
    }
}
NSGraphicsContext.restoreGraphicsState()

let dir = (outPath as NSString).deletingLastPathComponent
if !dir.isEmpty { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) (\(w)x\(h))")
