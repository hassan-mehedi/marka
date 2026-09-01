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

    func textView(_ view: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            return continueListOnNewline()
        case #selector(NSResponder.insertTab(_:)):
            return shiftListIndent(outward: false)
        case #selector(NSResponder.insertBacktab(_:)):
            return shiftListIndent(outward: true)
        default:
            return false
        }
    }

    private func currentParagraph() -> (range: NSRange, line: String)? {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound else { return nil }
        let range = ns.paragraphRange(for: selection)
        var line = ns.substring(with: range)
        if line.hasSuffix("\n") { line.removeLast() }
        return (range, line)
    }

    private func continueListOnNewline() -> Bool {
        guard let (range, line) = currentParagraph(),
              let marker = MarkdownParser.continuationMarker(afterLine: line)
        else { return false }

        if MarkdownParser.isEmptyListItem(line) {
            replaceKeepingCaret(NSRange(location: range.location, length: (line as NSString).length), with: "")
            return true
        }
        textView.insertText("\n" + marker, replacementRange: textView.selectedRange())
        return true
    }

    private func shiftListIndent(outward: Bool) -> Bool {
        guard let (range, line) = currentParagraph() else { return false }
        switch MarkdownParser.blockKind(of: line) {
        case .listItem, .taskListItem:
            break
        default:
            return false
        }

        if outward {
            let ns = line as NSString
            var remove = 0
            while remove < 2, remove < ns.length, ns.character(at: remove) == 0x20 { remove += 1 }
            if remove > 0 {
                replaceKeepingCaret(NSRange(location: range.location, length: remove), with: "")
            }
        } else {
            replaceKeepingCaret(NSRange(location: range.location, length: 0), with: "  ")
        }
        return true
    }

    @objc func toggleBold(_ sender: Any?) { toggleWrap("**") }
    @objc func toggleItalic(_ sender: Any?) { toggleWrap("*") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleWrap("~~") }
    @objc func toggleInlineCode(_ sender: Any?) { toggleWrap("`") }

    @objc func applyHeading(_ sender: NSMenuItem) {
        guard let (range, line) = currentParagraph() else { return }
        var markerLength = 0
        if case let .heading(_, marker) = MarkdownParser.blockKind(of: line) {
            markerLength = marker.length
        }
        let prefix = sender.tag > 0 ? String(repeating: "#", count: sender.tag) + " " : ""
        replaceKeepingCaret(NSRange(location: range.location, length: markerLength), with: prefix)
    }

    @objc func insertLink(_ sender: Any?) {
        let selection = effectiveSelection()
        let text = (textView.string as NSString).substring(with: selection)
        let replacement = "[\(text)](url)"
        let urlStart = selection.location + 1 + (text as NSString).length + 2
        replace(selection, with: replacement, thenSelect: NSRange(location: urlStart, length: 3))
    }

    private func toggleWrap(_ marker: String) {
        let ns = textView.string as NSString
        let markerLength = (marker as NSString).length
        let selection = effectiveSelection()
        let selected = ns.substring(with: selection)

        if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let caret = textView.selectedRange()
            replace(
                NSRange(location: caret.location, length: 0),
                with: marker + marker,
                thenSelect: NSRange(location: caret.location + markerLength, length: 0)
            )
            return
        }

        if selected.hasPrefix(marker), selected.hasSuffix(marker), selection.length >= 2 * markerLength {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            replace(selection, with: inner, thenSelect: NSRange(location: selection.location, length: selection.length - 2 * markerLength))
            return
        }

        let before = NSRange(location: selection.location - markerLength, length: markerLength)
        let after = NSRange(location: NSMaxRange(selection), length: markerLength)
        if before.location >= 0, NSMaxRange(after) <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker {
            let whole = NSRange(location: before.location, length: 2 * markerLength + selection.length)
            replace(whole, with: selected, thenSelect: NSRange(location: before.location, length: selection.length))
            return
        }

        replace(
            selection,
            with: marker + selected + marker,
            thenSelect: NSRange(location: selection.location + markerLength, length: selection.length)
        )
    }

    private func effectiveSelection() -> NSRange {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return selection }
        return textView.selectionRange(forProposedRange: selection, granularity: .selectByWord)
    }

    private func replace(_ range: NSRange, with string: String, thenSelect newSelection: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        textView.setSelectedRange(newSelection)
    }

    private func replaceKeepingCaret(_ range: NSRange, with string: String) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        let selection = textView.selectedRange()
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        let delta = (string as NSString).length - range.length
        textView.setSelectedRange(NSRange(location: max(selection.location + delta, 0), length: selection.length))
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

    - [ ] open task
    - [x] finished task

    > A blockquote line.

    ```
    let code = "fenced code block"
    ```

    ---

    Open a file with Cmd+O, save with Cmd+S.
    """
}
