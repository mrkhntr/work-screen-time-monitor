#!/usr/bin/env swift
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: round_icon <input.png> <output.png>\n", stderr)
    exit(1)
}

guard let src = NSImage(contentsOfFile: args[1]) else {
    fputs("Failed to load: \(args[1])\n", stderr)
    exit(1)
}

let size = src.size
// Apple icon grid corner radius ≈ 22.37% of icon dimension
let radius = min(size.width, size.height) * 0.2237

let out = NSImage(size: size)
out.lockFocus()
NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: radius, yRadius: radius).addClip()
src.draw(in: NSRect(origin: .zero, size: size))
out.unlockFocus()

guard let tiff = out.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode output\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: args[2]))
} catch {
    fputs("Failed to write: \(error)\n", stderr)
    exit(1)
}
