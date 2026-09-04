import AppKit

struct Theme: Equatable {
    var name: String
    var appearance: NSAppearance.Name?
    var baseFontName: String?
    var baseFontSize: CGFloat = 16
    var codeFontName: String?
    var codeFontSize: CGFloat = 14
    var background: NSColor?
    var textColor: NSColor?
    var secondaryText: NSColor?
    var marker: NSColor?
    var accent: NSColor?
    var link: NSColor?
    var codeBackground: NSColor?
    var tokenColors: [String: NSColor] = [:]

    var baseFont: NSFont {
        font(named: baseFontName, size: baseFontSize) ?? .systemFont(ofSize: baseFontSize)
    }

    var codeFont: NSFont {
        font(named: codeFontName, size: codeFontSize) ?? .monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
    }

    func headingFont(level: Int) -> NSFont {
        let scales: [CGFloat] = [1.75, 1.5, 1.3, 1.2, 1.05, 1.0]
        let size = (baseFontSize * scales[min(max(level, 1), 6) - 1]).rounded()
        let bold = FontCache.font(baseFont, withTrait: .boldFontMask)
        return FontCache.font(bold, size: size)
    }

    var resolvedText: NSColor { textColor ?? .textColor }
    var resolvedSecondary: NSColor { secondaryText ?? .secondaryLabelColor }
    var resolvedMarker: NSColor { marker ?? .tertiaryLabelColor }
    var resolvedAccent: NSColor { accent ?? .controlAccentColor }
    var resolvedLink: NSColor { link ?? .linkColor }
    var resolvedBackground: NSColor { background ?? .textBackgroundColor }
    var resolvedCodeBackground: NSColor { codeBackground ?? NSColor.systemGray.withAlphaComponent(0.15) }

    func tokenColor(_ name: String) -> NSColor? {
        tokenColors[name] ?? Self.defaultTokenColors[name]
    }

    private func font(named name: String?, size: CGFloat) -> NSFont? {
        guard let name else { return nil }
        return FontCache.font(named: name, size: size)
    }

    static let defaultTokenColors: [String: NSColor] = [
        "keyword": .systemPurple,
        "string": .systemGreen,
        "comment": .secondaryLabelColor,
        "number": .systemBlue,
        "function": .systemTeal,
        "type": .systemIndigo,
        "constant": .systemBlue,
        "constructor": .systemIndigo,
        "operator": .systemOrange,
        "attribute": .systemBrown,
        "boolean": .systemBlue,
        "property": .systemTeal,
        "label": .systemBrown,
        "escape": .systemOrange,
    ]
}

extension Theme {
    static let builtIn: [Theme] = [.systemTheme, .github, .githubDark, .dracula, .oneDarkPro, .night, .newsprint]

    static let systemTheme = Theme(name: "Default")

    static let github = Theme(
        name: "GitHub",
        appearance: .aqua,
        background: NSColor(hex: "#ffffff"),
        textColor: NSColor(hex: "#24292f"),
        secondaryText: NSColor(hex: "#57606a"),
        marker: NSColor(hex: "#8c959f"),
        accent: NSColor(hex: "#0969da"),
        link: NSColor(hex: "#0969da"),
        codeBackground: NSColor(hex: "#f6f8fa"),
        tokenColors: [
            "keyword": "#cf222e", "string": "#0a3069", "comment": "#6e7781",
            "number": "#0550ae", "function": "#8250df", "type": "#953800",
            "constant": "#0550ae", "constructor": "#953800", "operator": "#cf222e",
            "attribute": "#116329", "boolean": "#0550ae", "property": "#0550ae",
            "label": "#953800", "escape": "#cf222e",
        ].compactMapValues(NSColor.init(hex:))
    )

    static let githubDark = Theme(
        name: "GitHub Dark",
        appearance: .darkAqua,
        background: NSColor(hex: "#0d1117"),
        textColor: NSColor(hex: "#e6edf3"),
        secondaryText: NSColor(hex: "#8b949e"),
        marker: NSColor(hex: "#6e7681"),
        accent: NSColor(hex: "#58a6ff"),
        link: NSColor(hex: "#58a6ff"),
        codeBackground: NSColor(hex: "#161b22"),
        tokenColors: [
            "keyword": "#ff7b72", "string": "#a5d6ff", "comment": "#8b949e",
            "number": "#79c0ff", "function": "#d2a8ff", "type": "#ffa657",
            "constant": "#79c0ff", "constructor": "#ffa657", "operator": "#ff7b72",
            "attribute": "#7ee787", "boolean": "#79c0ff", "property": "#79c0ff",
            "label": "#ffa657", "escape": "#ff7b72",
        ].compactMapValues(NSColor.init(hex:))
    )

    static let dracula = Theme(
        name: "Dracula",
        appearance: .darkAqua,
        background: NSColor(hex: "#282a36"),
        textColor: NSColor(hex: "#f8f8f2"),
        secondaryText: NSColor(hex: "#9aa3c7"),
        marker: NSColor(hex: "#6272a4"),
        accent: NSColor(hex: "#bd93f9"),
        link: NSColor(hex: "#8be9fd"),
        codeBackground: NSColor(hex: "#21222c"),
        tokenColors: [
            "keyword": "#ff79c6", "string": "#f1fa8c", "comment": "#6272a4",
            "number": "#bd93f9", "function": "#50fa7b", "type": "#8be9fd",
            "constant": "#bd93f9", "constructor": "#8be9fd", "operator": "#ff79c6",
            "attribute": "#50fa7b", "boolean": "#bd93f9", "property": "#8be9fd",
            "label": "#ffb86c", "escape": "#ff79c6",
        ].compactMapValues(NSColor.init(hex:))
    )

    static let oneDarkPro = Theme(
        name: "One Dark Pro",
        appearance: .darkAqua,
        background: NSColor(hex: "#282c34"),
        textColor: NSColor(hex: "#abb2bf"),
        secondaryText: NSColor(hex: "#828997"),
        marker: NSColor(hex: "#5c6370"),
        accent: NSColor(hex: "#61afef"),
        link: NSColor(hex: "#61afef"),
        codeBackground: NSColor(hex: "#21252b"),
        tokenColors: [
            "keyword": "#c678dd", "string": "#98c379", "comment": "#5c6370",
            "number": "#d19a66", "function": "#61afef", "type": "#e5c07b",
            "constant": "#d19a66", "constructor": "#e5c07b", "operator": "#56b6c2",
            "attribute": "#d19a66", "boolean": "#d19a66", "property": "#e06c75",
            "label": "#d19a66", "escape": "#56b6c2",
        ].compactMapValues(NSColor.init(hex:))
    )

    static let night = Theme(
        name: "Night",
        appearance: .darkAqua,
        background: NSColor(hex: "#363b40"),
        textColor: NSColor(hex: "#dedede"),
        secondaryText: NSColor(hex: "#9da2a6"),
        marker: NSColor(hex: "#6b7075"),
        accent: NSColor(hex: "#61afef"),
        link: NSColor(hex: "#61afef"),
        codeBackground: NSColor(hex: "#2e3338"),
        tokenColors: [
            "keyword": "#c678dd", "string": "#98c379", "comment": "#7f848e",
            "number": "#d19a66", "function": "#61afef", "type": "#e5c07b",
            "constant": "#d19a66", "constructor": "#e5c07b", "operator": "#56b6c2",
            "attribute": "#d19a66", "boolean": "#d19a66", "property": "#e06c75",
            "label": "#d19a66", "escape": "#56b6c2",
        ].compactMapValues(NSColor.init(hex:))
    )

    static let newsprint = Theme(
        name: "Newsprint",
        appearance: .aqua,
        baseFontName: "Georgia",
        baseFontSize: 16,
        background: NSColor(hex: "#f3f2ee"),
        textColor: NSColor(hex: "#1f0909"),
        secondaryText: NSColor(hex: "#5a4a42"),
        marker: NSColor(hex: "#a89f94"),
        accent: NSColor(hex: "#065588"),
        link: NSColor(hex: "#065588"),
        codeBackground: NSColor(hex: "#e8e6df"),
        tokenColors: [
            "keyword": "#8b3e2f", "string": "#3e6b48", "comment": "#8d8579",
            "number": "#065588", "function": "#5b4a8a", "type": "#7a5901",
        ].compactMapValues(NSColor.init(hex:))
    )
}

struct ThemeFile: Codable {
    var name: String
    var appearance: String?
    var font: String?
    var fontSize: CGFloat?
    var codeFont: String?
    var codeFontSize: CGFloat?
    var background: String?
    var text: String?
    var secondaryText: String?
    var marker: String?
    var accent: String?
    var link: String?
    var codeBackground: String?
    var tokens: [String: String]?

    var theme: Theme {
        Theme(
            name: name,
            appearance: appearance.flatMap {
                switch $0.lowercased() {
                case "dark": .darkAqua
                case "light": .aqua
                default: nil
                }
            },
            baseFontName: font,
            baseFontSize: fontSize ?? 16,
            codeFontName: codeFont,
            codeFontSize: codeFontSize ?? 14,
            background: background.flatMap(NSColor.init(hex:)),
            textColor: text.flatMap(NSColor.init(hex:)),
            secondaryText: secondaryText.flatMap(NSColor.init(hex:)),
            marker: marker.flatMap(NSColor.init(hex:)),
            accent: accent.flatMap(NSColor.init(hex:)),
            link: link.flatMap(NSColor.init(hex:)),
            codeBackground: codeBackground.flatMap(NSColor.init(hex:)),
            tokenColors: (tokens ?? [:]).compactMapValues(NSColor.init(hex:))
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3, 4:
            digits = digits.map { "\($0)\($0)" }.joined()
            if digits.count == 6 { digits += "ff" }
        case 6:
            digits += "ff"
        case 8:
            break
        default:
            return nil
        }
        guard let value = UInt64(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 24) & 0xff) / 255,
            green: CGFloat((value >> 16) & 0xff) / 255,
            blue: CGFloat((value >> 8) & 0xff) / 255,
            alpha: CGFloat(value & 0xff) / 255
        )
    }
}
