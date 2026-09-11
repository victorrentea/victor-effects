#!/usr/bin/env swift
// Render the app's emoji into Sources/VictorEffects/Resources/icon_explosion.png.
// Run once (or after changing the emoji); build-app.sh turns the PNG into .icns.
//
//   swift tools/make-icon.swift [emoji] [out.png]

import AppKit

let emoji = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "💥"
let out = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "Sources/VictorEffects/Resources/icon_explosion.png"

let side = 1024
// An explicit 1024×1024 rep, not `NSImage.lockFocus()`: focusing an NSImage on a
// retina Mac allocates a 2048² backing store, and the PNG that falls out of it
// is 4 MB of icon nobody asked for.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// 0.8 of the canvas leaves the rounded-rect margin macOS expects around an icon.
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: CGFloat(side) * 0.8)]
let str = NSAttributedString(string: emoji, attributes: attrs)
let s = str.size()
str.draw(at: NSPoint(x: (CGFloat(side) - s.width) / 2, y: (CGFloat(side) - s.height) / 2))
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("could not render \(emoji)\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
