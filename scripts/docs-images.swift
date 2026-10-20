// Turns raw window snapshots into README images: rounded corners, soft shadow,
// and a gradient hero shot. Usage: swift scripts/docs-images.swift <snapshots-dir> <output-dir>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: docs-images.swift <snapshots-dir> <output-dir>")
    exit(1)
}
let inputDir = URL(fileURLWithPath: arguments[1])
let outputDir = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let brandStart = NSColor(calibratedRed: 0.27, green: 0.33, blue: 0.95, alpha: 1)
let brandEnd = NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.75, alpha: 1)

func loadImage(_ name: String) -> NSBitmapImageRep {
    let url = inputDir.appendingPathComponent("\(name).png")
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
        fatalError("missing snapshot \(url.path)")
    }
    return rep
}

func render(width: Int, height: Int, draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Draws the screenshot as a floating window: rounded corners, hairline border, drop shadow.
func drawWindow(_ shot: NSBitmapImageRep, in rect: NSRect) {
    let radius = rect.width * 0.012
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = rect.width * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.008)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    shot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.12).setStroke()
    path.lineWidth = 2
    path.stroke()
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = outputDir.appendingPathComponent("\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("  \(url.lastPathComponent)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

/// Screens scaled to `targetWidth` with transparent padding for the shadow.
let targetWidth: CGFloat = 1600
for name in ["overview", "disks", "cleaner", "processes"] {
    let shot = loadImage(name)
    let scale = targetWidth / CGFloat(shot.pixelsWide)
    let size = NSSize(width: targetWidth, height: CGFloat(shot.pixelsHigh) * scale)
    let padding: CGFloat = 60
    let image = render(width: Int(size.width + padding * 2), height: Int(size.height + padding * 2)) { _ in
        drawWindow(shot, in: NSRect(x: padding, y: padding * 1.2, width: size.width, height: size.height))
    }
    write(image, name)
}

/// Hero: the overview floating on the brand gradient.
let hero = loadImage("overview")
let heroWidth = 2000
let heroHeight = 1240
let heroImage = render(width: heroWidth, height: heroHeight) { bounds in
    let background = NSBezierPath(roundedRect: bounds, xRadius: 48, yRadius: 48)
    NSGradient(colors: [brandStart, brandEnd])!.draw(in: background, angle: -35)

    // Soft light blobs for depth.
    for (center, radius, alpha) in [
        (NSPoint(x: bounds.width * 0.15, y: bounds.height * 0.9), bounds.width * 0.35, 0.18),
        (NSPoint(x: bounds.width * 0.9, y: bounds.height * 0.1), bounds.width * 0.3, 0.12),
    ] {
        let blob = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        NSGradient(colors: [NSColor.white.withAlphaComponent(alpha), .clear])!
            .draw(in: NSBezierPath(ovalIn: blob), relativeCenterPosition: .zero)
    }

    let windowWidth = bounds.width * 0.86
    let windowHeight = windowWidth * CGFloat(hero.pixelsHigh) / CGFloat(hero.pixelsWide)
    let windowRect = NSRect(
        x: (bounds.width - windowWidth) / 2,
        y: (bounds.height - windowHeight) / 2,
        width: windowWidth,
        height: windowHeight
    )
    drawWindow(hero, in: windowRect)
}
write(heroImage, "hero")
