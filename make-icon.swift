#!/usr/bin/env swift
// Generates AppIcon.icns programmatically: a mooring bollard with a looped
// line, standing over water — Berth's mark.
// Usage: swift make-icon.swift  (run from the berth dir)

import AppKit
import Foundation

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: harbor blue, dusk sky into deep water.
    let radius = pf * 0.225
    let squircle = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: pf, height: pf),
        xRadius: radius, yRadius: radius)
    squircle.addClip()
    let grad = NSGradient(colors: [
        NSColor(red: 0.16, green: 0.42, blue: 0.62, alpha: 1),
        NSColor(red: 0.05, green: 0.16, blue: 0.30, alpha: 1),
    ])!
    grad.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -90)

    let rope = NSColor(red: 0.95, green: 0.88, blue: 0.72, alpha: 1)
    let bollardDark = NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
    let bollardLight = NSColor(red: 0.22, green: 0.26, blue: 0.32, alpha: 1)

    // --- Bollard: tapered post with a mushroom cap, centered.
    let cx = pf / 2
    let baseY = pf * 0.22
    let bodyW = pf * 0.26
    let topY = pf * 0.70

    let body = NSBezierPath()
    body.move(to: NSPoint(x: cx - bodyW * 0.62, y: baseY))
    body.line(to: NSPoint(x: cx - bodyW * 0.5, y: topY))
    body.line(to: NSPoint(x: cx + bodyW * 0.5, y: topY))
    body.line(to: NSPoint(x: cx + bodyW * 0.62, y: baseY))
    body.close()
    // subtle vertical sheen: fill with gradient
    NSGradient(colors: [bollardLight, bollardDark])!.draw(in: body, angle: 0)

    // Cap: wide rounded slab + dome on top.
    let capW = pf * 0.40
    let capH = pf * 0.085
    let cap = NSBezierPath(
        roundedRect: NSRect(x: cx - capW / 2, y: topY - capH * 0.25, width: capW, height: capH),
        xRadius: capH / 2, yRadius: capH / 2)
    NSGradient(colors: [bollardLight, bollardDark])!.draw(in: cap, angle: 0)
    let domeW = capW * 0.62
    let domeH = pf * 0.055
    let dome = NSBezierPath(
        roundedRect: NSRect(x: cx - domeW / 2, y: topY + capH * 0.55, width: domeW, height: domeH),
        xRadius: domeH / 2, yRadius: domeH / 2)
    bollardLight.setFill()
    dome.fill()

    // --- Rope: a looped line around the post, tail running off to the right.
    let ropeWidth = max(2, pf * 0.052)
    let loopCY = pf * 0.50
    let loopRX = pf * 0.225
    let loopRY = pf * 0.085

    // Back half of the loop (drawn dimmer, "behind" the post).
    let backLoop = NSBezierPath(ovalIn: NSRect(
        x: cx - loopRX, y: loopCY - loopRY, width: loopRX * 2, height: loopRY * 2))
    backLoop.lineWidth = ropeWidth
    backLoop.lineCapStyle = .round
    rope.withAlphaComponent(0.55).setStroke()
    backLoop.stroke()

    // Redraw post's center strip over the back rope so it reads as behind.
    NSGraphicsContext.current?.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [bollardLight, bollardDark])!.draw(
        in: NSRect(x: cx - bodyW * 0.62, y: loopCY - loopRY - ropeWidth,
                   width: bodyW * 1.24, height: loopRY + ropeWidth),
        angle: 0)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Front (lower) arc of the loop, full-strength rope color.
    // Built as a unit-circle arc scaled into an ellipse.
    let frontArc = NSBezierPath()
    frontArc.appendArc(
        withCenter: .zero, radius: 1, startAngle: 175, endAngle: 365, clockwise: false)
    var xform = AffineTransform(translationByX: cx, byY: loopCY)
    xform.scale(x: loopRX, y: loopRY)
    frontArc.transform(using: xform)
    frontArc.lineWidth = ropeWidth
    frontArc.lineCapStyle = .round
    rope.setStroke()
    frontArc.stroke()

    // Tail: from the loop's right edge, sweeping down toward the water.
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: cx + loopRX * 0.99, y: loopCY + loopRY * 0.10))
    tail.curve(
        to: NSPoint(x: pf * 0.865, y: pf * 0.255),
        controlPoint1: NSPoint(x: cx + loopRX * 1.22, y: loopCY - pf * 0.055),
        controlPoint2: NSPoint(x: pf * 0.88, y: pf * 0.38))
    tail.curve(
        to: NSPoint(x: pf * 0.78, y: pf * 0.155),
        controlPoint1: NSPoint(x: pf * 0.85, y: pf * 0.17),
        controlPoint2: NSPoint(x: pf * 0.82, y: pf * 0.15))
    tail.lineWidth = ropeWidth
    tail.lineCapStyle = .round
    rope.setStroke()
    tail.stroke()

    // --- Water: two gentle wave lines across the bottom.
    let wave = NSColor(red: 0.45, green: 0.72, blue: 0.88, alpha: 0.75)
    for (yy, alpha) in [(pf * 0.155, 0.85), (pf * 0.095, 0.55)] {
        let w = NSBezierPath()
        let amp = pf * 0.022
        w.move(to: NSPoint(x: pf * 0.06, y: yy))
        var x = pf * 0.06
        let seg = pf * 0.115
        var up = true
        while x < pf * 0.94 {
            let nx = min(x + seg, pf * 0.94)
            w.curve(
                to: NSPoint(x: nx, y: yy),
                controlPoint1: NSPoint(x: x + seg * 0.33, y: yy + (up ? amp : -amp)),
                controlPoint2: NSPoint(x: nx - seg * 0.33, y: yy + (up ? amp : -amp)))
            up.toggle()
            x = nx
        }
        w.lineWidth = max(1.5, pf * 0.030)
        w.lineCapStyle = .round
        wave.withAlphaComponent(alpha).setStroke()
        w.stroke()
    }

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path,
                  "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")
