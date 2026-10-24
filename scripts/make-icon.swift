#!/usr/bin/env swift
// Renders the app icon: the awake sheep art centred on fog #ECEDEB, 1024×1024, no alpha.
// Usage (from repo root): swift scripts/make-icon.swift
// Not part of the app target.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svg = root.appendingPathComponent("Sheep/Assets.xcassets/Sheep/sheep-awake.imageset/sheep-awake.svg")
let out = root.appendingPathComponent("Sheep/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

guard let art = NSImage(contentsOf: svg) else { fatalError("can't load \(svg.path)") }

let side = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("no context")
}

// Fog background.
ctx.setFillColor(CGColor(srgbRed: 0xEC / 255, green: 0xED / 255, blue: 0xEB / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

// Art: its visible bounds sit roughly centred in the 88×88 viewBox; draw at 74% of the icon,
// nudged slightly so the body (not the frame) is optically centred.
let artSide = CGFloat(side) * 0.74
let artRect = CGRect(x: (CGFloat(side) - artSide) / 2 - CGFloat(side) * 0.01,
                     y: (CGFloat(side) - artSide) / 2,
                     width: artSide, height: artSide)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
art.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("encode failed")
}
try png.write(to: out)
print("wrote \(out.path)")
