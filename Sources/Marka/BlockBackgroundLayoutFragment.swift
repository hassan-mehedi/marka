import AppKit

// Paints a full-width block behind a paragraph, so consecutive code lines
// read as one box instead of per-line highlights.
final class BlockBackgroundLayoutFragment: NSTextLayoutFragment {
    var color: NSColor = .clear
    var roundsTop = false
    var roundsBottom = false
    var containerWidth: CGFloat = 0

    private static let radius: CGFloat = 6

    // When the closing fence is the document's last paragraph, TextKit appends
    // the trailing empty line to this fragment; leave that line unpainted.
    private var backgroundRect: CGRect {
        var height = layoutFragmentFrame.height
        if roundsBottom, textLineFragments.count > 1, let last = textLineFragments.last {
            height -= last.typographicBounds.height
        }
        return CGRect(x: -layoutFragmentFrame.minX, y: 0, width: containerWidth, height: height)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(backgroundRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let rect = backgroundRect.offsetBy(dx: point.x, dy: point.y)
        context.saveGState()
        context.addPath(Self.path(for: rect, top: roundsTop, bottom: roundsBottom))
        context.setFillColor(color.cgColor)
        context.fillPath()
        context.restoreGState()
        super.draw(at: point, in: context)
    }

    private static func path(for rect: CGRect, top: Bool, bottom: Bool) -> CGPath {
        let r = radius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.midX, y: rect.minY), radius: top ? r : 0)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.midY), radius: top ? r : 0)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.midX, y: rect.maxY), radius: bottom ? r : 0)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.midY), radius: bottom ? r : 0)
        path.closeSubpath()
        return path
    }
}
