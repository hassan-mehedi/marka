import AppKit
import SwiftMath

@MainActor
final class MathRenderer {
    static let shared = MathRenderer()

    private struct Key: Hashable {
        let latex: String
        let fontSize: CGFloat
        let display: Bool
        let color: String
    }

    private var cache: [Key: NSImage] = [:]

    func image(latex: String, fontSize: CGFloat, display: Bool, color: NSColor) -> NSImage? {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        let key = Key(latex: latex, fontSize: fontSize, display: display, color: resolved.description)
        if let cached = cache[key] {
            return cached
        }

        let renderer = MTMathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: resolved,
            labelMode: display ? .display : .text
        )
        let (error, image) = renderer.asImage()
        guard error == nil, let image else { return nil }
        cache[key] = image
        return image
    }

    func clearCache() {
        cache.removeAll()
    }
}
