import AppKit
import Testing
@testable import Marka

@Test @MainActor func preferencesOverrideThemeFonts() {
    let suite = "marka-prefs-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = Preferences(defaults: defaults)

    #expect(preferences.spellCheck)
    #expect(preferences.imageFolder == "assets")
    #expect(preferences.apply(to: .github).baseFontSize == 16)

    preferences.editorFontSize = 20
    preferences.codeFontName = "Menlo"
    preferences.imageFolder = " images "
    let themed = preferences.apply(to: .github)
    #expect(themed.baseFontSize == 20)
    #expect(themed.codeFontName == "Menlo")
    #expect(themed.codeFont.fontName.hasPrefix("Menlo"))
    #expect(preferences.imageFolder == "images")

    preferences.editorFontSize = 0
    #expect(preferences.apply(to: .github).baseFontSize == 16)
}

@Test @MainActor func lineWidthCentersTextColumn() {
    let editor = EditorViewController()
    editor.loadView()
    editor.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
    editor.view.layoutSubtreeIfNeeded()
    editor.viewDidLayout()
    #expect(editor.textView.textContainerInset.width == 28)

    let saved = Preferences.shared.lineWidth
    defer { Preferences.shared.lineWidth = saved }
    Preferences.shared.lineWidth = 600
    editor.viewDidLayout()
    #expect(editor.textView.textContainerInset.width == 200)

    Preferences.shared.lineWidth = 2000
    editor.viewDidLayout()
    #expect(editor.textView.textContainerInset.width == 28)
}
