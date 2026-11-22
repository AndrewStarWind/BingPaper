#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-icns-path>\n", stderr)
    exit(1)
}

let outputICNSURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputICNSURL.deletingLastPathComponent(), withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    let cg = context.cgContext

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = cardRect.width * 0.225
    let clipPath = CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Subtle drop shadow
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    cg.addPath(clipPath)
    cg.setFillColor(NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.28, alpha: 1).cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Clip to rounded icon container
    cg.saveGState()
    cg.addPath(clipPath)
    cg.clip()

    // Sky gradient (deep twilight blue -> luminous cyan -> warm sunrise amber)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let skyColors = [
        NSColor(calibratedRed: 0.07, green: 0.14, blue: 0.34, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.13, green: 0.42, blue: 0.68, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.96, green: 0.68, blue: 0.36, alpha: 1).cgColor
    ] as CFArray
    if let skyGradient = CGGradient(colorsSpace: colorSpace, colors: skyColors, locations: [0.0, 0.58, 1.0]) {
        cg.drawLinearGradient(
            skyGradient,
            start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.midX, y: cardRect.minY + cardRect.height * 0.22),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Glowing sun
    let sunCenter = CGPoint(x: cardRect.minX + cardRect.width * 0.68, y: cardRect.minY + cardRect.height * 0.63)
    let glowColors = [
        NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.80, alpha: 0.95).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.48, alpha: 0.40).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.35, alpha: 0.0).cgColor
    ] as CFArray
    if let sunGlow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.35, 1.0]) {
        cg.drawRadialGradient(
            sunGlow,
            startCenter: sunCenter,
            startRadius: 0,
            endCenter: sunCenter,
            endRadius: cardRect.width * 0.28,
            options: []
        )
    }
    let sunRadius = cardRect.width * 0.085
    cg.setFillColor(NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.88, alpha: 1).cgColor)
    cg.fillEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))

    // Back mountain ridge
    let backRidge = CGMutablePath()
    backRidge.move(to: CGPoint(x: cardRect.minX, y: cardRect.minY))
    backRidge.addLine(to: CGPoint(x: cardRect.minX, y: cardRect.minY + cardRect.height * 0.42))
    backRidge.addLine(to: CGPoint(x: cardRect.minX + cardRect.width * 0.28, y: cardRect.minY + cardRect.height * 0.56))
    backRidge.addLine(to: CGPoint(x: cardRect.minX + cardRect.width * 0.55, y: cardRect.minY + cardRect.height * 0.38))
    backRidge.addLine(to: CGPoint(x: cardRect.minX + cardRect.width * 0.80, y: cardRect.minY + cardRect.height * 0.52))
    backRidge.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.minY + cardRect.height * 0.40))
    backRidge.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.minY))
    backRidge.closeSubpath()

    cg.saveGState()
    cg.addPath(backRidge)
    cg.clip()
    let backColors = [
        NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.48, alpha: 0.92).cgColor,
        NSColor(calibratedRed: 0.09, green: 0.16, blue: 0.30, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: backColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            grad,
            start: CGPoint(x: cardRect.midX, y: cardRect.minY + cardRect.height * 0.58),
            end: CGPoint(x: cardRect.midX, y: cardRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Foreground mountain peak
    let frontRidge = CGMutablePath()
    frontRidge.move(to: CGPoint(x: cardRect.minX, y: cardRect.minY))
    frontRidge.addLine(to: CGPoint(x: cardRect.minX, y: cardRect.minY + cardRect.height * 0.26))
    frontRidge.addLine(to: CGPoint(x: cardRect.minX + cardRect.width * 0.40, y: cardRect.minY + cardRect.height * 0.46))
    frontRidge.addLine(to: CGPoint(x: cardRect.minX + cardRect.width * 0.72, y: cardRect.minY + cardRect.height * 0.25))
    frontRidge.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.minY + cardRect.height * 0.34))
    frontRidge.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.minY))
    frontRidge.closeSubpath()

    cg.saveGState()
    cg.addPath(frontRidge)
    cg.clip()
    let frontColors = [
        NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.14, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: frontColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            grad,
            start: CGPoint(x: cardRect.midX, y: cardRect.minY + cardRect.height * 0.46),
            end: CGPoint(x: cardRect.midX, y: cardRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Liquid Glass top sheen highlight
    let sheenRect = CGRect(x: cardRect.minX, y: cardRect.midY, width: cardRect.width, height: cardRect.height * 0.5)
    let sheenColors = [
        NSColor.white.withAlphaComponent(0.24).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let sheen = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            sheen,
            start: CGPoint(x: sheenRect.midX, y: sheenRect.maxY),
            end: CGPoint(x: sheenRect.midX, y: sheenRect.minY),
            options: []
        )
    }

    cg.restoreGState()

    // Specular border stroke
    cg.addPath(clipPath)
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
    cg.setLineWidth(max(1, size * 0.012))
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(String, Int)] = [
    ("icp4", 16),   // 16x16
    ("ic11", 32),   // 16x16@2x
    ("icp5", 32),   // 32x32
    ("ic12", 64),   // 32x32@2x
    ("ic07", 128),  // 128x128
    ("ic13", 256),  // 128x128@2x
    ("ic08", 256),  // 256x256
    ("ic14", 512),  // 256x256@2x
    ("ic09", 512),  // 512x512
    ("ic10", 1024)  // 512x512@2x
]

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var big = value.bigEndian
    withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
}

var body = Data()
for (osType, pixels) in entries {
    guard let pngData = renderIcon(pixelSize: pixels) else {
        fputs("Failed to render \(osType) (\(pixels)px)\n", stderr)
        exit(1)
    }
    body.append(contentsOf: osType.utf8)
    appendBigEndian(UInt32(8 + pngData.count), to: &body)
    body.append(pngData)
}

var icnsData = Data("icns".utf8)
appendBigEndian(UInt32(8 + body.count), to: &icnsData)
icnsData.append(body)

try icnsData.write(to: outputICNSURL, options: .atomic)
