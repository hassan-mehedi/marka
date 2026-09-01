import AppKit

@MainActor
final class MarkaDocument: NSDocument {
    nonisolated static let markdownType = "net.daringfireball.markdown"
    nonisolated static let plainTextType = "public.plain-text"

    private var loadedText = ""
    private weak var editor: EditorViewController?
    private weak var sidebar: SidebarViewController?

    // AppKit sets fileURL on the main thread for documents without async IO.
    nonisolated override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                sidebar?.fileTree.rootURL = fileURL?.deletingLastPathComponent()
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
    nonisolated override class var autosavesInPlace: Bool { false }

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
        sidebar.fileTree.rootURL = fileURL?.deletingLastPathComponent()
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
        window.contentViewController = split
        window.setFrameAutosaveName("MarkaDocumentWindow")
        window.tabbingMode = .preferred

        let controller = NSWindowController(window: window)
        addWindowController(controller)
        window.center()
    }

    // AppKit reads and writes documents on the main thread unless the document
    // opts into asynchronous IO, which this one does not.
    nonisolated override func data(ofType typeName: String) throws -> Data {
        try MainActor.assumeIsolated { Data(text.utf8) }
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadCorruptFileError,
                userInfo: [NSLocalizedDescriptionKey: "The file is not valid UTF-8 text."]
            )
        }
        try MainActor.assumeIsolated {
            loadedText = string
            editor?.text = string
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

    nonisolated override func documentClass(forType typeName: String) -> AnyClass? {
        MarkaDocument.self
    }

    nonisolated override func typeForContents(of url: URL) throws -> String {
        url.pathExtension.lowercased() == "txt" ? MarkaDocument.plainTextType : MarkaDocument.markdownType
    }
}
