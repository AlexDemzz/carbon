// Usage: swift background.swift out-dir
// Draws the DMG window's background at 1x and 2x: a hairline arrow from the app to Applications
// over a caption, in the site's warm neutrals. Layout constants match settings.py.
import AppKit

// Taller than the window's content so a different title bar height never shows an edge.
let size = CGSize(width: 600, height: 420)
let appCenter = CGPoint(x: 160, y: 140)
let applicationsCenter = CGPoint(x: 440, y: 140)
let captionBottom: CGFloat = 300

// alexandrejoly.me theme: background, subtle-foreground and muted-foreground (oklch, hue 70).
let background = NSColor(srgbRed: 0.984, green: 0.980, blue: 0.973, alpha: 1)
let arrowColor = NSColor(srgbRed: 0.553, green: 0.537, blue: 0.522, alpha: 1)
let captionColor = NSColor(srgbRed: 0.459, green: 0.443, blue: 0.427, alpha: 1)

func render(scale: CGFloat, to url: URL) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // Finder's icon positions count from the top; AppKit's from the bottom.
    func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: size.height - point.y) }

    background.setFill()
    CGRect(origin: .zero, size: size).fill()

    let y = flipped(appCenter).y
    let start = CGPoint(x: appCenter.x + 88, y: y)
    let end = CGPoint(x: applicationsCenter.x - 88, y: y)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.line(to: end)
    arrow.move(to: CGPoint(x: end.x - 9, y: y + 9))
    arrow.line(to: end)
    arrow.line(to: CGPoint(x: end.x - 9, y: y - 9))
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrowColor.setStroke()
    arrow.stroke()

    let caption = NSAttributedString(
        string: "Drag Carbon to Applications",
        attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: captionColor])
    let captionSize = caption.size()
    caption.draw(at: CGPoint(x: (size.width - captionSize.width) / 2, y: flipped(CGPoint(x: 0, y: captionBottom)).y))

    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try render(scale: 1, to: outDir.appendingPathComponent("background.png"))
try render(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
