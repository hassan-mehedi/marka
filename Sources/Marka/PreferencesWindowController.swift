import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let preferences = Preferences.shared
    private var themePopup: NSPopUpButton!
    private var editorFontPopup: NSPopUpButton!
    private var editorSizeField: NSTextField!
    private var codeFontPopup: NSPopUpButton!
    private var codeSizeField: NSTextField!
    private var lineWidthField: NSTextField!
    private var imageFolderField: NSTextField!
    private var spellCheckBox: NSButton!
    private var autocorrectBox: NSButton!
    private var autosaveBox: NSButton!
    private var smartPunctuationBox: NSButton!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = makeContent()
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: ThemeManager.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func makeContent() -> NSView {
        themePopup = NSPopUpButton()
        themePopup.target = self
        themePopup.action = #selector(themeChanged)

        editorFontPopup = makeFontPopup(action: #selector(editorFontChanged))
        codeFontPopup = makeFontPopup(action: #selector(codeFontChanged), monospacedOnly: true)
        editorSizeField = makeNumberField(action: #selector(editorSizeChanged), placeholder: "theme")
        codeSizeField = makeNumberField(action: #selector(codeSizeChanged), placeholder: "theme")
        lineWidthField = makeNumberField(action: #selector(lineWidthChanged), placeholder: "full width")
        imageFolderField = NSTextField(string: "")
        imageFolderField.placeholderString = "assets"
        imageFolderField.target = self
        imageFolderField.action = #selector(imageFolderChanged)

        spellCheckBox = NSButton(checkboxWithTitle: "Check spelling while typing", target: self, action: #selector(toggleChanged(_:)))
        autocorrectBox = NSButton(checkboxWithTitle: "Correct spelling automatically", target: self, action: #selector(toggleChanged(_:)))
        autosaveBox = NSButton(checkboxWithTitle: "Autosave documents in place", target: self, action: #selector(toggleChanged(_:)))
        smartPunctuationBox = NSButton(checkboxWithTitle: "Smart quotes and dashes", target: self, action: #selector(toggleChanged(_:)))

        let editorFontRow = row(editorFontPopup, editorSizeField)
        let codeFontRow = row(codeFontPopup, codeSizeField)
        let lineWidthRow = row(lineWidthField, NSTextField(labelWithString: "points"))

        let grid = NSGridView(views: [
            [label("Theme"), themePopup],
            [label("Editor font"), editorFontRow],
            [label("Code font"), codeFontRow],
            [label("Line width"), lineWidthRow],
            [label("Image folder"), imageFolderField],
            [NSGridCell.emptyContentView, spellCheckBox],
            [NSGridCell.emptyContentView, autocorrectBox],
            [NSGridCell.emptyContentView, smartPunctuationBox],
            [NSGridCell.emptyContentView, autosaveBox],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 300
        grid.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(wrappingLabelWithString: "Leave a size empty to use the theme's size. Image folder is relative to the document.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        content.addSubview(note)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            note.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            note.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        return content
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func makeNumberField(action: Selector, placeholder: String) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.alignment = .right
        field.target = self
        field.action = action
        field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 4000
        formatter.allowsFloats = false
        field.formatter = formatter
        return field
    }

    private func makeFontPopup(action: Selector, monospacedOnly: Bool = false) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItem(withTitle: "Theme Default")
        popup.menu?.addItem(.separator())
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        for family in families where !monospacedOnly || Self.isMonospaced(family) {
            popup.addItem(withTitle: family)
        }
        popup.target = self
        popup.action = action
        return popup
    }

    private static func isMonospaced(_ family: String) -> Bool {
        guard let font = NSFont(name: family, size: 12) ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) else {
            return false
        }
        return font.isFixedPitch
    }

    @objc private func refresh() {
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: ThemeManager.shared.themes.map(\.name))
        themePopup.selectItem(withTitle: ThemeManager.shared.baseTheme.name)
        select(editorFontPopup, family: preferences.editorFontName)
        select(codeFontPopup, family: preferences.codeFontName)
        editorSizeField.stringValue = preferences.editorFontSize > 0 ? "\(Int(preferences.editorFontSize))" : ""
        codeSizeField.stringValue = preferences.codeFontSize > 0 ? "\(Int(preferences.codeFontSize))" : ""
        lineWidthField.stringValue = preferences.lineWidth > 0 ? "\(Int(preferences.lineWidth))" : ""
        imageFolderField.stringValue = preferences.imageFolder
        spellCheckBox.state = preferences.spellCheck ? .on : .off
        autocorrectBox.state = preferences.autocorrect ? .on : .off
        autosaveBox.state = preferences.autosave ? .on : .off
        smartPunctuationBox.state = preferences.smartPunctuation ? .on : .off
    }

    private func select(_ popup: NSPopUpButton, family: String?) {
        if let family, popup.item(withTitle: family) != nil {
            popup.selectItem(withTitle: family)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func chosenFamily(_ popup: NSPopUpButton) -> String? {
        popup.indexOfSelectedItem == 0 ? nil : popup.titleOfSelectedItem
    }

    @objc private func themeChanged() {
        guard let name = themePopup.titleOfSelectedItem else { return }
        ThemeManager.shared.select(named: name)
    }

    @objc private func editorFontChanged() { preferences.editorFontName = chosenFamily(editorFontPopup) }
    @objc private func codeFontChanged() { preferences.codeFontName = chosenFamily(codeFontPopup) }
    @objc private func editorSizeChanged() { preferences.editorFontSize = CGFloat(editorSizeField.doubleValue) }
    @objc private func codeSizeChanged() { preferences.codeFontSize = CGFloat(codeSizeField.doubleValue) }
    @objc private func lineWidthChanged() { preferences.lineWidth = CGFloat(lineWidthField.doubleValue) }
    @objc private func imageFolderChanged() { preferences.imageFolder = imageFolderField.stringValue }

    @objc private func toggleChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case spellCheckBox: preferences.spellCheck = on
        case autocorrectBox: preferences.autocorrect = on
        case autosaveBox: preferences.autosave = on
        case smartPunctuationBox: preferences.smartPunctuation = on
        default: break
        }
    }
}
