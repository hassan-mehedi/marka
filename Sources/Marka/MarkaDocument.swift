import AppKit
import UniformTypeIdentifiers

@MainActor
final class MarkaDocument: NSDocument {
    nonisolated static let markdownType = "net.daringfireball.markdown"
    nonisolated static let plainTextType = "public.plain-text"

    private var loadedText = ""
    private var usesCRLF = false
    private weak var editor: EditorViewController?
    private weak var sidebar: SidebarViewController?

    // AppKit sets fileURL on the main thread for documents without async IO.
    nonisolated override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                sidebar?.rootURL = fileURL?.deletingLastPathComponent()
            }
        }
    }

    override init() {
        super.init()
        // The text view keeps its own undo stack; NSDocument's would fight it.
        hasUndoManager = false
    }

    nonisolated override class var readableTypes: [String] { [markdownType, plainTextType] }
    nonisolated override class var writableTypes: [String] { [markdownType, plainTextType] }
    nonisolated override class func isNativeType(_ type: String) -> Bool { true }
    nonisolated override class var autosavesInPlace: Bool { Preferences.autosaveEnabled }

    var text: String {
        editor?.text ?? loadedText
    }

    override func makeWindowControllers() {
        let editor = EditorViewController()
        editor.document = self
        if loadedText.isEmpty, fileURL == nil, ProcessInfo.processInfo.environment["MARKA_SAMPLE"] != nil {
            loadedText = EditorViewController.sampleDocument
        }
        editor.text = loadedText
        self.editor = editor

        let sidebar = SidebarViewController()
        sidebar.outline.onSelect = { [weak editor] location in editor?.jump(to: location) }
        editor.onOutlineChange = { [weak sidebar] items in sidebar?.outline.update(items) }
        sidebar.rootURL = fileURL?.deletingLastPathComponent()
        sidebar.search.onSelect = { match in
            MarkaDocument.reveal(match)
        }
        self.sidebar = sidebar

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: editor))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = DocumentContentViewController(split: split)
        let restoredFrame = window.setFrameUsingName("MarkaDocumentWindow")
        window.setFrameAutosaveName("MarkaDocumentWindow")
        window.tabbingMode = .preferred
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ThemeManager.shared.current.resolvedBackground

        let controller = NSWindowController(window: window)
        addWindowController(controller)
        if !restoredFrame { window.center() }
    }

    var folderURL: URL? { fileURL?.deletingLastPathComponent() }

    func replaceText(with text: String) {
        loadedText = text
        editor?.text = text
        updateChangeCount(.changeDone)
    }

    // Undo back to the saved text clears the edited state, because the text
    // view owns the undo stack and NSDocument cannot count its groups.
    func noteTextChanged(byUndo: Bool) {
        if byUndo, text == savedText {
            updateChangeCount(.changeCleared)
        } else {
            updateChangeCount(.changeDone)
        }
    }

    private var savedText = ""

    func jump(to offset: Int) {
        editor?.jump(to: offset)
    }

    @objc func quickOpen(_ sender: Any?) {
        QuickOpenController.shared.show(root: folderURL)
    }

    @objc func findInFolder(_ sender: Any?) {
        guard let split = (windowControllers.first?.window?.contentViewController as? DocumentContentViewController)?.split,
              let sidebarItem = split.splitViewItems.first else { return }
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
        sidebar?.showSearch()
    }

    func sidebarSearch(_ query: String) {
        sidebar?.search.search(query)
    }

    // Opens the matched file (reusing its window when already open) and moves
    // the caret to the match.
    static func reveal(_ match: ProjectFiles.Match) {
        NSDocumentController.shared.openDocument(withContentsOf: match.url, display: true) { document, _, _ in
            (document as? MarkaDocument)?.jump(to: match.offset)
        }
    }

    // AppKit reads and writes documents on the main thread unless the document
    // opts into asynchronous IO, which this one does not.
    nonisolated override func data(ofType typeName: String) throws -> Data {
        MainActor.assumeIsolated {
            savedText = text
            let output = usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
            return Data(output.utf8)
        }
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadCorruptFileError,
                userInfo: [NSLocalizedDescriptionKey: "The file is not valid UTF-8 text."]
            )
        }
        // The editor works on LF only; files that arrived with CRLF are
        // written back the same way.
        let usesCRLF = string.contains("\r\n")
        let normalized = usesCRLF ? string.replacingOccurrences(of: "\r\n", with: "\n") : string
        MainActor.assumeIsolated {
            self.usesCRLF = usesCRLF
            loadedText = normalized
            savedText = normalized
            editor?.text = normalized
        }
    }

    nonisolated override func fileNameExtension(
        forType typeName: String,
        saveOperation: NSDocument.SaveOperationType
    ) -> String? {
        typeName == Self.plainTextType ? "txt" : "md"
    }
}

@MainActor
final class MarkaDocumentController: NSDocumentController {
    nonisolated override var defaultType: String? { MarkaDocument.markdownType }

    // File > Import: converts a docx, html, epub, or similar file through
    // pandoc and opens the Markdown as a new untitled document.
    @objc func importDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PandocExporter.importFormats.keys.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a document to convert to Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let markdown = try await Task.detached { try PandocExporter.importMarkdown(from: url) }.value
                let document = try openUntitledDocumentAndDisplay(true) as? MarkaDocument
                document?.replaceText(with: markdown)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    nonisolated override func documentClass(forType typeName: String) -> AnyClass? {
        MarkaDocument.self
    }

    nonisolated override func typeForContents(of url: URL) throws -> String {
        url.pathExtension.lowercased() == "txt" ? MarkaDocument.plainTextType : MarkaDocument.markdownType
    }
}
