#!/usr/bin/env swift
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.dropFirst().first ?? "Icon-1024.png"
let size: CGFloat = 1024

let bmp = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// Full-bleed squircle background path
let cornerR: CGFloat = size * 0.2237
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerR, yRadius: cornerR).cgPath

ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()

// Diagonal deep gradient — indigo-600 → slate-950
let bgGrad = CGGradient(
    colorsSpace: cs,
    colors: [
        rgb(0.31, 0.27, 0.90),  // #4F46E5 indigo-600
        rgb(0.12, 0.11, 0.30),  // #1E1B4B indigo-950
        rgb(0.02, 0.04, 0.10),  // #05090F near-black slate
    ] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(bgGrad,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: [])

// Subtle top spotlight — mimics ambient overhead light
let spot = CGGradient(colorsSpace: cs,
    colors: [rgb(1, 1, 1, 0.14), rgb(1, 1, 1, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(spot,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.92), startRadius: 0,
    endCenter: CGPoint(x: size * 0.5, y: size * 0.92), endRadius: size * 0.7,
    options: [])

// Soft ambient behind C
let ambient = CGGradient(colorsSpace: cs,
    colors: [rgb(0.55, 0.75, 1, 0.30), rgb(0.55, 0.75, 1, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawRadialGradient(ambient,
    startCenter: CGPoint(x: size * 0.45, y: size * 0.52), startRadius: 0,
    endCenter: CGPoint(x: size * 0.45, y: size * 0.52), endRadius: size * 0.55,
    options: [])

// --- Build C letterform as thick stroked arc, converted to fill path ---
let cCenter = CGPoint(x: size * 0.44, y: size * 0.5)
let midR: CGFloat = size * 0.26
let thickness: CGFloat = size * 0.115
let gap: CGFloat = .pi * 0.30  // ~54° gap
let startA = gap
let endA = 2 * .pi - gap

let arc = CGMutablePath()
arc.addArc(center: cCenter, radius: midR, startAngle: startA, endAngle: endA, clockwise: false)

// Convert stroke to filled path
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineWidth(thickness)
ctx.setLineJoin(.round)
ctx.addPath(arc)
ctx.replacePathWithStrokedPath()
let cPath = ctx.path!.copy()!
ctx.restoreGState()

// Drop shadow layer behind C
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 44,
    color: rgb(0.02, 0.04, 0.10, 0.55)
)
ctx.addPath(cPath)
ctx.setFillColor(rgb(1, 1, 1))
ctx.fillPath()
ctx.restoreGState()

// C body with vertical white gradient for depth
ctx.saveGState()
ctx.addPath(cPath); ctx.clip()
let cGrad = CGGradient(colorsSpace: cs,
    colors: [
        rgb(1.00, 1.00, 1.00),
        rgb(0.94, 0.96, 1.00),
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(cGrad,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: [])
ctx.restoreGState()

// Subtle inner top rim highlight on C
ctx.saveGState()
ctx.addPath(cPath); ctx.clip()
let rim = CGGradient(colorsSpace: cs,
    colors: [rgb(1, 1, 1, 0.8), rgb(1, 1, 1, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(rim,
    start: CGPoint(x: 0, y: size * 0.78),
    end: CGPoint(x: 0, y: size * 0.60),
    options: [])
ctx.restoreGState()

// --- Beat dot: amber, inside the C's opening ---
let dotR: CGFloat = size * 0.062
let dotCenter = CGPoint(x: cCenter.x + midR + 4, y: cCenter.y)

// outer glow
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: rgb(0.98, 0.65, 0.20, 0.85))
ctx.setFillColor(rgb(0.98, 0.75, 0.30))
ctx.addEllipse(in: CGRect(
    x: dotCenter.x - dotR, y: dotCenter.y - dotR,
    width: dotR * 2, height: dotR * 2
))
ctx.fillPath()
ctx.restoreGState()

// dot with radial gradient (bright center → amber)
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: dotCenter.x - dotR, y: dotCenter.y - dotR,
    width: dotR * 2, height: dotR * 2
))
ctx.clip()
let dotGrad = CGGradient(colorsSpace: cs,
    colors: [
        rgb(1.00, 0.95, 0.75),  // near-white warm
        rgb(0.99, 0.75, 0.30),  // amber
        rgb(0.90, 0.55, 0.12),  // deeper amber edge
    ] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawRadialGradient(dotGrad,
    startCenter: CGPoint(x: dotCenter.x - dotR * 0.2, y: dotCenter.y + dotR * 0.2),
    startRadius: 0,
    endCenter: dotCenter,
    endRadius: dotR,
    options: [])
ctx.restoreGState()

// Bright specular pin on dot
ctx.saveGState()
let pinR = dotR * 0.28
ctx.setFillColor(rgb(1, 1, 1, 0.85))
ctx.addEllipse(in: CGRect(
    x: dotCenter.x - pinR - dotR * 0.25,
    y: dotCenter.y + dotR * 0.30,
    width: pinR * 2, height: pinR * 2
))
ctx.fillPath()
ctx.restoreGState()

// Top-left glass sheen over bg
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let sheen = CGGradient(colorsSpace: cs,
    colors: [rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(sheen,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size * 0.6, y: size * 0.6),
    options: [])
ctx.restoreGState()

// Bottom inner shadow for depth
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let botShadow = CGGradient(colorsSpace: cs,
    colors: [rgb(0, 0, 0, 0.30), rgb(0, 0, 0, 0)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(botShadow,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: 0, y: size * 0.28),
    options: [])
ctx.restoreGState()

ctx.restoreGState()  // pop squircle clip

// Fine inner border for polish
ctx.setLineWidth(1.5)
ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
ctx.addPath(bgPath)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

let data = bmp.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
