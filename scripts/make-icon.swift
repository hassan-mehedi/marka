import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = size * 0.08
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1),
])!
gradient.draw(in: shape, angle: -90)

let glyph = "M" as NSString
let font = NSFont.systemFont(ofSize: size * 0.52, weight: .bold)
let glyphSize = glyph.size(withAttributes: [.font: font])
glyph.draw(
    at: NSPoint(x: (size - glyphSize.width) / 2, y: size * 0.34),
    withAttributes: [.font: font, .foregroundColor: NSColor.white]
)

let bar = NSRect(x: size * 0.3, y: size * 0.26, width: size * 0.4, height: size * 0.035)
NSColor(calibratedRed: 0.29, green: 0.78, blue: 0.82, alpha: 1).setFill()
NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()

image.unlockFocus()

let png = NSBitmapImageRep(data: image.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
