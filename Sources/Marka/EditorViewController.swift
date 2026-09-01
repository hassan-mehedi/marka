import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {
    private var textView: NSTextView!
    private var highlighter: MarkdownHighlighter!
    private var fileURL: URL? {
        didSet { updateWindowTitle() }
    }

    override func loadView() {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = MarkdownHighlighter.baseFont
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        self.textView = textView

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        view = scrollView

        highlighter = MarkdownHighlighter(textView: textView)
        textView.string = Self.sampleDocument
        highlighter.highlightAll()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowTitle()
    }

    func textDidChange(_ notification: Notification) {
        highlighter.handleEdit()
        view.window?.isDocumentEdited = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        highlighter.handleSelectionChange()
    }

    @objc func newDocument(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        textView.string = ""
        fileURL = nil
        highlighter.highlightAll()
        view.window?.isDocumentEdited = false
    }

    @objc func openDocument(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = markdownTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            textView.string = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            highlighter.highlightAll()
            view.window?.isDocumentEdited = false
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let url = fileURL else {
            saveDocumentAs(sender)
            return
        }
        write(to: url)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = markdownTypes
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            try textView.string.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            view.window?.isDocumentEdited = false
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private var markdownTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return types
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard view.window?.isDocumentEdited == true else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "The current document has unsaved changes."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func updateWindowTitle() {
        view.window?.title = fileURL?.lastPathComponent ?? "Untitled"
        view.window?.representedURL = fileURL
    }

    private static let sampleDocument = """
    # Marka

    A native Markdown editor for macOS. Type anywhere to try the live styling.

    ## Inline styles

    Text in **bold**, in *italic*, in ***both***, ~~struck~~, and `inline code`. \
    A [link to the repo](https://example.com) opens on click. Move the caret into \
    a styled span and the syntax markers reveal themselves.

    ## Blocks

    - unordered list item
    - another item with **bold**

    1. ordered item
    2. second item

    > A blockquote line.

    ```
    let code = "fenced code block"
    ```

    ---

    Open a file with Cmd+O, save with Cmd+S.
    """
}
