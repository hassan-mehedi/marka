import AppKit

@main
@MainActor
final class MarkaApp: NSObject, NSApplicationDelegate {
    // Instantiating our controller first makes it NSDocumentController.shared,
    // which is what supplies document types when running without an app bundle.
    private let documentController = MarkaDocumentController()

    static func main() {
        let app = NSApplication.shared
        let delegate = MarkaApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        NSApp.activate(ignoringOtherApps: true)

        let environment = ProcessInfo.processInfo.environment
        guard let snapshotPath = environment["MARKA_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [documentController] in
            if environment["MARKA_SNAPSHOT_TABS"] != nil {
                let front = NSApp.keyWindow
                documentController.newDocument(nil)
                front?.makeKeyAndOrderFront(nil)
            }
            if let caret = environment["MARKA_SNAPSHOT_CARET"].flatMap(Int.init),
               let split = NSApp.keyWindow?.contentViewController as? NSSplitViewController,
               let editor = split.splitViewItems.last?.viewController as? EditorViewController {
                editor.jump(to: caret)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentViewController != nil }) {
                    Self.writeSnapshot(of: window, to: snapshotPath, wholeWindow: environment["MARKA_SNAPSHOT_FRAME"] != nil)
                }
                NSApp.terminate(nil)
            }
        }
    }

    private static func writeSnapshot(of window: NSWindow, to path: String, wholeWindow: Bool) {
        guard let content = window.contentView,
              let view = wholeWindow ? content.superview : content,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        do {
            try documentController.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Marka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        let recentItem = fileMenu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        // AppKit fills this submenu in by identifier.
        recentMenu.identifier = NSUserInterfaceItemIdentifier("NSRecentDocumentsMenu")
        recentMenu.addItem(
            withTitle: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        recentItem.submenu = recentMenu
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(.separator())
        let exportItem = fileMenu.addItem(withTitle: "Export", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "Export")
        exportMenu.addItem(withTitle: "PDF…", action: #selector(EditorViewController.exportPDF(_:)), keyEquivalent: "")
        exportMenu.addItem(withTitle: "HTML…", action: #selector(EditorViewController.exportHTML(_:)), keyEquivalent: "")
        exportMenu.addItem(withTitle: "Word (.docx)…", action: #selector(EditorViewController.exportDocx(_:)), keyEquivalent: "")
        exportMenu.addItem(withTitle: "epub…", action: #selector(EditorViewController.exportEpub(_:)), keyEquivalent: "")
        exportMenu.addItem(withTitle: "LaTeX…", action: #selector(EditorViewController.exportLaTeX(_:)), keyEquivalent: "")
        exportItem.submenu = exportMenu
        fileMenu.addItem(withTitle: "Print…", action: #selector(EditorViewController.printMarkdown(_:)), keyEquivalent: "p")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        let findActions: [(String, String, NSEvent.ModifierFlags, NSTextFinder.Action)] = [
            ("Find…", "f", [.command], .showFindInterface),
            ("Find and Replace…", "f", [.command, .option], .showReplaceInterface),
            ("Find Next", "g", [.command], .nextMatch),
            ("Find Previous", "g", [.command, .shift], .previousMatch),
            ("Use Selection for Find", "e", [.command], .setSearchString),
        ]
        for (title, key, modifiers, action) in findActions {
            let item = findMenu.addItem(
                withTitle: title,
                action: #selector(NSTextView.performTextFinderAction(_:)),
                keyEquivalent: key
            )
            item.keyEquivalentModifierMask = modifiers
            item.tag = action.rawValue
        }
        findItem.submenu = findMenu
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Source Mode", action: #selector(EditorViewController.toggleSourceMode(_:)), keyEquivalent: "/")
        let outlineToggle = viewMenu.addItem(withTitle: "Toggle Outline", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "o")
        outlineToggle.keyEquivalentModifierMask = [.command, .shift]
        let focusToggle = viewMenu.addItem(withTitle: "Focus Mode", action: #selector(EditorViewController.toggleFocusMode(_:)), keyEquivalent: "f")
        focusToggle.keyEquivalentModifierMask = [.command, .shift]
        let typewriterToggle = viewMenu.addItem(withTitle: "Typewriter Mode", action: #selector(EditorViewController.toggleTypewriterMode(_:)), keyEquivalent: "t")
        typewriterToggle.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        let zoomIn = viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "=")
        zoomIn.keyEquivalentModifierMask = [.command, .shift]
        let zoomOut = viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        zoomOut.keyEquivalentModifierMask = [.command, .shift]
        let actualSize = viewMenu.addItem(withTitle: "Actual Size", action: #selector(actualSize(_:)), keyEquivalent: "0")
        actualSize.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        let themeItem = viewMenu.addItem(withTitle: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = makeThemeMenu()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let formatMenuItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(withTitle: "Bold", action: #selector(EditorViewController.toggleBold(_:)), keyEquivalent: "b")
        formatMenu.addItem(withTitle: "Italic", action: #selector(EditorViewController.toggleItalic(_:)), keyEquivalent: "i")
        let strike = formatMenu.addItem(withTitle: "Strikethrough", action: #selector(EditorViewController.toggleStrikethrough(_:)), keyEquivalent: "x")
        strike.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(withTitle: "Inline Code", action: #selector(EditorViewController.toggleInlineCode(_:)), keyEquivalent: "e")
        formatMenu.addItem(withTitle: "Link", action: #selector(EditorViewController.insertLink(_:)), keyEquivalent: "k")
        formatMenu.addItem(.separator())
        for level in 1...6 {
            let item = formatMenu.addItem(
                withTitle: "Heading \(level)",
                action: #selector(EditorViewController.applyHeading(_:)),
                keyEquivalent: "\(level)"
            )
            item.tag = level
        }
        let paragraphItem = formatMenu.addItem(withTitle: "Paragraph", action: #selector(EditorViewController.applyHeading(_:)), keyEquivalent: "0")
        paragraphItem.tag = 0
        formatMenu.addItem(.separator())
        let blockItems: [(String, Selector, String)] = [
            ("Bullet List", #selector(EditorViewController.toggleBulletList(_:)), "u"),
            ("Numbered List", #selector(EditorViewController.toggleOrderedList(_:)), "o"),
            ("Task List", #selector(EditorViewController.toggleTaskList(_:)), "x"),
            ("Blockquote", #selector(EditorViewController.toggleBlockquote(_:)), "q"),
        ]
        for (title, action, key) in blockItems {
            formatMenu.addItem(withTitle: title, action: action, keyEquivalent: key).keyEquivalentModifierMask = [.command, .option]
        }
        formatMenu.addItem(.separator())
        let insertItems: [(String, Selector, String)] = [
            ("Code Fence", #selector(EditorViewController.insertCodeFence(_:)), "c"),
            ("Math Block", #selector(EditorViewController.insertMathBlock(_:)), "b"),
            ("Table…", #selector(EditorViewController.insertTable(_:)), "t"),
            ("Image…", #selector(EditorViewController.insertImage(_:)), "i"),
            ("Footnote", #selector(EditorViewController.insertFootnote(_:)), ""),
            ("Horizontal Rule", #selector(EditorViewController.insertHorizontalRule(_:)), ""),
        ]
        for (title, action, key) in insertItems {
            formatMenu.addItem(withTitle: title, action: action, keyEquivalent: key).keyEquivalentModifierMask = [.command, .option]
        }
        formatMenu.addItem(.separator())
        let smartItem = formatMenu.addItem(
            withTitle: "Smart Punctuation",
            action: #selector(EditorViewController.toggleSmartPunctuation(_:)),
            keyEquivalent: ""
        )
        smartItem.state = UserDefaults.standard.bool(forKey: "MarkaSmartPunctuation") ? .on : .off
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        return mainMenu
    }

    private static func makeThemeMenu() -> NSMenu {
        let menu = NSMenu(title: "Theme")
        for theme in ThemeManager.shared.themes {
            let item = menu.addItem(withTitle: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.name
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Themes Folder", action: #selector(openThemesFolder(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ThemeManager.shared.select(named: name)
    }

    @objc private func zoomIn(_ sender: Any?) {
        ThemeManager.shared.setFontScale(ThemeManager.shared.fontScale + 0.1)
    }

    @objc private func zoomOut(_ sender: Any?) {
        ThemeManager.shared.setFontScale(ThemeManager.shared.fontScale - 0.1)
    }

    @objc private func actualSize(_ sender: Any?) {
        ThemeManager.shared.setFontScale(1)
    }

    @objc private func openThemesFolder(_ sender: NSMenuItem) {
        let directory = ThemeManager.userThemesDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

extension MarkaApp: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectTheme(_:)), let name = menuItem.representedObject as? String {
            menuItem.state = name == ThemeManager.shared.baseTheme.name ? .on : .off
        }
        return true
    }
}
