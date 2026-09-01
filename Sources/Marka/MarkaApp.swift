import AppKit

@main
@MainActor
final class MarkaApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = MarkaApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Marka"

        let editor = EditorViewController()
        let outline = OutlineViewController()
        outline.onSelect = { [weak editor] location in editor?.jump(to: location) }
        editor.onOutlineChange = { [weak outline] items in outline?.update(items) }

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: outline)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: editor))
        window.contentViewController = split
        window.setFrameAutosaveName("MarkaMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
        fileMenu.addItem(withTitle: "New", action: #selector(EditorViewController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(EditorViewController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(EditorViewController.saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(EditorViewController.saveDocumentAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as PDF…", action: #selector(EditorViewController.exportPDF(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Print…", action: #selector(EditorViewController.printDocument(_:)), keyEquivalent: "p")
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
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Source Mode", action: #selector(EditorViewController.toggleSourceMode(_:)), keyEquivalent: "/")
        let outlineToggle = viewMenu.addItem(withTitle: "Toggle Outline", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "o")
        outlineToggle.keyEquivalentModifierMask = [.command, .shift]
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
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        return mainMenu
    }
}
