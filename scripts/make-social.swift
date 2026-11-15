// Draws assets/social-preview.png (1280×640), the image GitHub shows for links to the repo.
// Usage: swift scripts/make-social.swift   (after `make demo`, which renders docs/images/hero.png)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let size = NSSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
color(0x15171B).setFill()
NSRect(origin: .zero, size: size).fill()

// Left: icon, name, tagline.
let icon = NSImage(contentsOf: root.appendingPathComponent("assets/icon.png"))!
icon.draw(in: NSRect(x: 58, y: 380, width: 160, height: 160))
func text(_ s: String, _ font: NSFont, _ c: NSColor, _ x: CGFloat, _ y: CGFloat, width: CGFloat = 470) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 6
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .paragraphStyle: style])
        .draw(in: NSRect(x: x, y: y, width: width, height: 200))
}
text("zest", NSFont.systemFont(ofSize: 80, weight: .bold), color(0xD7DAE0), 232, 300)
text("Autocomplete popup for zsh on macOS", NSFont.systemFont(ofSize: 36, weight: .semibold), color(0xABB2BF), 70, 150)
text("1,500 commands · native Swift · ~20 MB\nTerminal.app, VS Code, Cursor", NSFont.systemFont(ofSize: 25), color(0x7F848E), 70, 40)

// Right: the popup, cropped from the README hero image.
if let hero = NSImage(contentsOf: root.appendingPathComponent("docs/images/hero.png")) {
    let px = hero.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? hero.size
    // The hero is 2x; crop the terminal area with the prompt and the popup.
    // The window's title bar, the prompt and the popup (measured on the 936×456 pt hero).
    let crop = NSRect(x: px.width * 28 / 936, y: px.height * 151 / 456, width: px.width * 640 / 936, height: px.height * 277 / 456)
    let width: CGFloat = 660
    let height = width * crop.height / crop.width
    let target = NSRect(x: 570, y: (size.height - height) / 2, width: width, height: height)
    let clip = NSBezierPath(roundedRect: target, xRadius: 14, yRadius: 14)
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    let scale = hero.size.width / px.width
    hero.draw(in: target, from: NSRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale),
              operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    color(0x3E4452).setStroke()
    clip.lineWidth = 2
    clip.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("assets/social-preview.png"))
print("Wrote assets/social-preview.png")
