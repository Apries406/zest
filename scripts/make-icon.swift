// Draws the app icon: a citrus slice ("zest") next to a shell prompt, in One Dark colors.
// Usage: swift scripts/make-icon.swift  → writes assets/AppIcon.icns
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS icon grid: 824×824 rounded square centered in 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x2C313A), ending: color(0x1E2227))!.draw(in: shape, angle: -90)
    color(0x181A1F).setStroke()
    shape.lineWidth = 6 * s
    shape.stroke()

    // Citrus slice.
    let center = NSPoint(x: 590 * s, y: 590 * s)
    let radius: CGFloat = 220 * s
    color(0xD18F52).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    color(0xF5D9A8).setFill()
    let pith = radius * 0.86
    NSBezierPath(ovalIn: NSRect(x: center.x - pith, y: center.y - pith, width: pith * 2, height: pith * 2)).fill()
    let segments = 8
    for i in 0..<segments {
        let a0 = CGFloat(i) / CGFloat(segments) * 2 * .pi + 0.07
        let a1 = CGFloat(i + 1) / CGFloat(segments) * 2 * .pi - 0.07
        let path = NSBezierPath()
        let inner = radius * 0.12
        let outer = radius * 0.78
        path.move(to: NSPoint(x: center.x + cos((a0 + a1) / 2) * inner, y: center.y + sin((a0 + a1) / 2) * inner))
        path.appendArc(withCenter: center, radius: outer, startAngle: a0 * 180 / .pi, endAngle: a1 * 180 / .pi)
        path.close()
        color(0xE5A45F).setFill()
        path.fill()
    }

    // Prompt.
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Menlo-Bold", size: 300 * s) ?? NSFont.monospacedSystemFont(ofSize: 300 * s, weight: .bold),
        .foregroundColor: color(0x8CC265),
    ]
    NSAttributedString(string: "›", attributes: attrs).draw(at: NSPoint(x: 170 * s, y: 150 * s))
    color(0xABB2BF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 360 * s, y: 215 * s, width: 170 * s, height: 34 * s), xRadius: 8 * s, yRadius: 8 * s).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try draw(size: 512).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("assets/icon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("assets/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
print("Wrote assets/AppIcon.icns and assets/icon.png")
