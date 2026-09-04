import AppKit

// Help > Keyboard Shortcuts: every menu shortcut, read from the main menu
// when the window opens, plus the editing keys that have no menu item.
@MainActor
final class ShortcutsWindowController: NSWindowController {
    static let shared = ShortcutsWindowController()

    struct Section: Equatable {
        let title: String
        let rows: [(name: String, keys: String)]

        static func == (lhs: Section, rhs: Section) -> Bool {
            lhs.title == rhs.title && lhs.rows.map(\.name) == rhs.rows.map(\.name) && lhs.rows.map(\.keys) == rhs.rows.map(\.keys)
        }
    }

    static let editingRows: [(name: String, keys: String)] = [
        ("Continue list on a new line", "↩"),
        ("Indent or outdent a list item", "⇥ / ⇧⇥"),
        ("Move to the next or previous table cell", "⇥ / ⇧⇥"),
        ("Add a table row from the last row", "↩"),
        ("Complete an emoji shortcode or fence language", "⎋"),
    ]

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MarkaShortcutsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        window.contentView = Self.makeContent(sections: Self.sections(from: NSApp.mainMenu))
        if !window.isVisible { window.center() }
        super.showWindow(sender)
    }

    static func sections(from mainMenu: NSMenu?) -> [Section] {
        var sections: [Section] = []
        for item in mainMenu?.items ?? [] {
            guard let submenu = item.submenu else { continue }
            let title = submenu.title.isEmpty ? "Marka" : submenu.title
            let rows = shortcutRows(in: submenu)
            if !rows.isEmpty { sections.append(Section(title: title, rows: rows)) }
        }
        sections.append(Section(title: "Editing", rows: editingRows))
        return sections
    }

    private static func shortcutRows(in menu: NSMenu) -> [(name: String, keys: String)] {
        var rows: [(name: String, keys: String)] = []
        var seen = Set<String>()
        // AppKit adds its own dictation and emoji items to the Edit menu. Keys
        // without a command, option or control modifier are not menu shortcuts
        // and are dropped; repeats of a title collapse to the first, so
        // "Emoji & Symbols" appears once.
        let required: NSEvent.ModifierFlags = [.command, .option, .control]
        for item in menu.items where !item.isSeparatorItem && !item.isHidden {
            if let submenu = item.submenu {
                rows += shortcutRows(in: submenu).map { ("\(item.title) › \($0.name)", $0.keys) }
            } else if !item.keyEquivalent.isEmpty, !item.keyEquivalentModifierMask.intersection(required).isEmpty,
                      seen.insert(item.title).inserted {
                rows.append((item.title, keys(for: item)))
            }
        }
        return rows
    }

    static func keys(for item: NSMenuItem) -> String {
        var modifiers = item.keyEquivalentModifierMask
        var key = item.keyEquivalent
        if key.count == 1, key.uppercased() != key.lowercased(), key == key.uppercased() {
            modifiers.insert(.shift)
        }
        key = key.uppercased()
        switch item.keyEquivalent {
        case "\t": key = "⇥"
        case "\r", "\n": key = "↩"
        case "\u{1b}": key = "⎋"
        case "\u{8}", "\u{7f}": key = "⌫"
        case " ": key = "Space"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): key = "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): key = "↓"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): key = "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): key = "→"
        default: break
        }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    // A read-only text view: section headers in bold, one row per shortcut
    // with the keys on a right-aligned tab stop.
    private static func makeContent(sections: [Section]) -> NSView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.textStorage?.setAttributedString(attributedText(for: sections))
        return scrollView
    }

    static func attributedText(for sections: [Section]) -> NSAttributedString {
        let rowStyle = NSMutableParagraphStyle()
        rowStyle.tabStops = [NSTextTab(textAlignment: .right, location: 440)]
        rowStyle.defaultTabInterval = 440
        rowStyle.paragraphSpacing = 3
        rowStyle.lineBreakMode = .byTruncatingTail
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.paragraphSpacingBefore = 14
        headerStyle.paragraphSpacing = 6

        let result = NSMutableAttributedString()
        for (index, section) in sections.enumerated() {
            let header = NSMutableParagraphStyle()
            header.setParagraphStyle(headerStyle)
            if index == 0 { header.paragraphSpacingBefore = 0 }
            result.append(NSAttributedString(string: section.title + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: header,
            ]))
            for row in section.rows {
                result.append(NSAttributedString(string: row.name + "\t", attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: rowStyle,
                ]))
                result.append(NSAttributedString(string: row.keys + "\n", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: rowStyle,
                ]))
            }
        }
        return result
    }
}
