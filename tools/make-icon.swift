#!/usr/bin/env swift
// The app icon: the menu bar's own 𝓯𝔁 (MenuBar.idleIcon), large, white, on a
// macOS-shaped rounded square — so the Dock, Finder and System Settings show
// the same mark as the menu bar (Victor, 2026-10-14). Own artwork: the glyphs
// come from the system's math font (STIX Two, OFL), rendered here.
//
//   swift tools/make-icon.swift [out.png]     (default: Sources/VictorEffects/Resources/icon_fx.png)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "Sources/VictorEffects/Resources/icon_fx.png"
let side: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's icon grid: an 824-pt rounded square centred in 1024, corner ~185.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.09, blue: 0.20, alpha: 1),
                    NSColor(srgbRed: 0.33, green: 0.12, blue: 0.45, alpha: 1),
                    NSColor(srgbRed: 0.93, green: 0.35, blue: 0.25, alpha: 1)])!
    .draw(in: tile, angle: 60)
// A soft light behind the letters.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSBezierPath(ovalIn: tile.insetBy(dx: 120, dy: 120)), relativeCenterPosition: .zero)
NSGraphicsContext.restoreGraphicsState()

let glyph = NSAttributedString(string: "𝓯𝔁", attributes: [
    .font: NSFont.systemFont(ofSize: 560),
    .foregroundColor: NSColor.white,
])
let size = glyph.size()
let glow = NSShadow()
glow.shadowColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.5, alpha: 0.55)
glow.shadowBlurRadius = 30
glow.set()
glyph.draw(at: NSPoint(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2 + 10))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
