import AppKit

// Font lookups and trait conversions go through AppKit's font manager, which
// is slow enough to matter when every paragraph asks for its fonts. Results
// are kept per name, size and trait.
enum FontCache {
    private struct Key: Hashable {
        let name: String
        let size: CGFloat
        let trait: UInt
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var named: [Key: NSFont?] = [:]
    nonisolated(unsafe) private static var converted: [Key: NSFont] = [:]

    static func font(named name: String, size: CGFloat) -> NSFont? {
        let key = Key(name: name, size: size, trait: 0)
        lock.lock()
        defer { lock.unlock() }
        if let cached = named[key] { return cached }
        let font = NSFont(name: name, size: size)
        named[key] = .some(font)
        return font
    }

    static func font(_ font: NSFont, withTrait trait: NSFontTraitMask) -> NSFont {
        let key = Key(name: font.fontName, size: font.pointSize, trait: trait.rawValue)
        lock.lock()
        defer { lock.unlock() }
        if let cached = converted[key] { return cached }
        let result = NSFontManager.shared.convert(font, toHaveTrait: trait)
        converted[key] = result
        return result
    }

    static func font(_ font: NSFont, size: CGFloat) -> NSFont {
        let key = Key(name: font.fontName, size: size, trait: UInt.max)
        lock.lock()
        defer { lock.unlock() }
        if let cached = converted[key] { return cached }
        let result = NSFontManager.shared.convert(font, toSize: size)
        converted[key] = result
        return result
    }
}
