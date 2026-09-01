import AppKit

@MainActor
final class OpaqueBackgroundView: NSView {
    var color: NSColor = .windowBackgroundColor {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}
