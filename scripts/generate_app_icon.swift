import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_app_icon.swift <output.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let temporaryDirectory = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("eduvis-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = temporaryDirectory.appendingPathComponent("EduVisAIGallery.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryDirectory) }

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let customIconCandidates = [
    projectDir.appendingPathComponent("nano_asset/app_icon.png"),
    projectDir.appendingPathComponent("nano_asset/app_icon.ico"),
    URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("nano_asset/app_icon.png"),
    URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("nano_asset/app_icon.ico"),
]
let customSourceImage: NSImage? = customIconCandidates
    .first(where: { fileManager.fileExists(atPath: $0.path) })
    .flatMap { NSImage(contentsOf: $0) }

func drawIcon(size: Int) throws -> Data {
    let dimension = CGFloat(size)
    let bounds = NSRect(x: 0, y: 0, width: dimension, height: dimension)

    if let sourceImage = customSourceImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: bitmap)
        ctx?.imageInterpolation = .high
        NSGraphicsContext.current = ctx
        sourceImage.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "EduVisIcon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not encode custom app icon PNG."
            ])
        }
        return png
    }

    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    image.lockFocus()
    defer { image.unlockFocus() }

    let inset = dimension * 0.035
    let iconRect = bounds.insetBy(dx: inset, dy: inset)
    let radius = dimension * 0.23
    let backgroundPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.43, green: 0.53, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.46, green: 0.31, blue: 0.79, alpha: 1),
    ])?.draw(in: backgroundPath, angle: -45)

    let glowRect = NSRect(
        x: dimension * 0.12,
        y: dimension * 0.43,
        width: dimension * 0.55,
        height: dimension * 0.55
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 0.79, green: 0.84, blue: 1, alpha: 0.55),
        NSColor(calibratedRed: 0.79, green: 0.84, blue: 1, alpha: 0),
    ])?.draw(in: NSBezierPath(ovalIn: glowRect), angle: -45)

    for fraction in [0.60, 0.78] {
        let diameter = dimension * fraction
        let circle = NSBezierPath(ovalIn: NSRect(
            x: (dimension - diameter) / 2,
            y: (dimension - diameter) / 2,
            width: diameter,
            height: diameter
        ))
        NSColor.white.withAlphaComponent(fraction < 0.7 ? 0.21 : 0.12).setStroke()
        circle.lineWidth = max(1, dimension * 0.008)
        circle.stroke()
    }

    let center = NSPoint(x: dimension / 2, y: dimension / 2)
    let outerRadius = dimension * 0.33
    let innerRadius = outerRadius * 0.31
    let star = NSBezierPath()
    for point in 0..<8 {
        let radius = point.isMultiple(of: 2) ? outerRadius : innerRadius
        let angle = CGFloat(point) * .pi / 4 - .pi / 2
        let location = NSPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
        if point == 0 {
            star.move(to: location)
        } else {
            star.line(to: location)
        }
    }
    star.close()
    NSColor.white.setFill()
    star.fill()

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: bounds)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "EduVisIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not encode app icon PNG."
        ])
    }
    return png
}

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, size) in iconSizes {
    try drawIcon(size: size).write(to: iconsetURL.appendingPathComponent(filename))
}

let iconutil = URL(fileURLWithPath: "/usr/bin/iconutil")
let process = Process()
process.executableURL = iconutil
process.arguments = ["-c", "icns", "-o", outputURL.path, iconsetURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "EduVisIcon", code: Int(process.terminationStatus), userInfo: [
        NSLocalizedDescriptionKey: "iconutil could not generate EduVisAIGallery.icns."
    ])
}
