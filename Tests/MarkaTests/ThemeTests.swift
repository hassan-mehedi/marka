import AppKit
import Foundation
import Testing
@testable import Marka

@Test func hexColorParsing() {
    let color = NSColor(hex: "#ff8000")
    #expect(color != nil)
    #expect(abs((color?.redComponent ?? 0) - 1.0) < 0.005)
    #expect(abs((color?.greenComponent ?? 0) - 0.502) < 0.005)
    #expect(abs((color?.blueComponent ?? 0) - 0.0) < 0.005)
    #expect(NSColor(hex: "abc") != nil)
    #expect(NSColor(hex: "#11223344")?.alphaComponent ?? 0 < 0.27)
    #expect(NSColor(hex: "nope") == nil)
    #expect(NSColor(hex: "#12345") == nil)
}

@Test func themeFileDecodesToTheme() throws {
    let json = """
    {
        "name": "Custom",
        "appearance": "dark",
        "fontSize": 18,
        "background": "#101010",
        "text": "#eeeeee",
        "tokens": { "keyword": "#ff0000" }
    }
    """
    let theme = try JSONDecoder().decode(ThemeFile.self, from: Data(json.utf8)).theme
    #expect(theme.name == "Custom")
    #expect(theme.appearance == .darkAqua)
    #expect(theme.baseFontSize == 18)
    #expect(theme.background != nil)
    #expect(theme.tokenColor("keyword") == NSColor(hex: "#ff0000"))
    #expect(theme.tokenColor("string") == Theme.defaultTokenColors["string"])
}

@Test func headingFontScalesWithBaseSize() {
    var theme = Theme.systemTheme
    theme.baseFontSize = 16
    #expect(theme.headingFont(level: 1).pointSize == 28)
    #expect(theme.headingFont(level: 6).pointSize == 16)
    theme.baseFontSize = 20
    #expect(theme.headingFont(level: 1).pointSize == 35)
}

@Test func defaultThemeFallsBackToSystemColors() {
    let theme = Theme.systemTheme
    #expect(theme.resolvedText == .textColor)
    #expect(theme.resolvedBackground == .textBackgroundColor)
    #expect(theme.baseFont == .systemFont(ofSize: 16))
}

@Test @MainActor func builtInThemesAreListed() {
    let names = ThemeManager.shared.themes.map(\.name)
    #expect(names.contains("Default"))
    #expect(names.contains("GitHub"))
    #expect(names.contains("Night"))
    #expect(names.contains("Newsprint"))
}

@Test func hexColorRejectsSignsAndAcceptsShortAlpha() {
    #expect(NSColor(hex: "#+fffff") == nil)
    #expect(NSColor(hex: "#12g") == nil)
    let short = NSColor(hex: "#f008")
    #expect(short != nil)
    #expect(abs((short?.alphaComponent ?? 0) - 136.0 / 255) < 0.001)
}

@Test func userThemeReplacesBuiltInWithSameName() {
    var custom = Theme.systemTheme
    custom.name = "GitHub"
    var duplicate = Theme.systemTheme
    duplicate.name = "Mine"
    let merged = ThemeManager.merge(builtIn: Theme.builtIn, user: [custom, duplicate, duplicate])
    #expect(merged.map(\.name) == Theme.builtIn.map(\.name) + ["Mine"])
    #expect(merged.first { $0.name == "GitHub" } == custom)
}
