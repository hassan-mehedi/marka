import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {
    private var textView: NSTextView!
    private var highlighter: MarkdownHighlighter!
    private var statusLabel: NSTextField!
    private var typewriterMode = false
    var onOutlineChange: (([OutlineItem]) -> Void)?
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel = statusLabel

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        container.addSubview(scrollView)
        container.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4)
        ])
        view = container

        highlighter = MarkdownHighlighter(textView: textView)
        textView.string = Self.sampleDocument
        highlighter.highlightAll()
        updateWordCount()
        updateOutline()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowTitle()
    }

    func textDidChange(_ notification: Notification) {
        highlighter.handleEdit()
        view.window?.isDocumentEdited = true
        updateWordCount()
        updateOutline()
        recenterCaret()
    }

    @objc func toggleSourceMode(_ sender: NSMenuItem) {
        highlighter.revealAllMarkers.toggle()
        highlighter.highlightAll()
        sender.state = highlighter.revealAllMarkers ? .on : .off
    }

    @objc func toggleFocusMode(_ sender: NSMenuItem) {
        highlighter.focusMode.toggle()
        highlighter.highlightAll()
        sender.state = highlighter.focusMode ? .on : .off
    }

    @objc func toggleTypewriterMode(_ sender: NSMenuItem) {
        typewriterMode.toggle()
        sender.state = typewriterMode ? .on : .off
        recenterCaret()
    }

    private func recenterCaret() {
        guard typewriterMode, let window = view.window, let scrollView = textView.enclosingScrollView else { return }
        let selection = textView.selectedRange()
        let caret = NSRange(location: selection.location, length: 0)
        let screenRect = textView.firstRect(forCharacterRange: caret, actualRange: nil)
        guard screenRect != .zero else { return }
        let inText = textView.convert(window.convertFromScreen(screenRect), from: nil)
        let clip = scrollView.contentView
        let targetY = max(0, inText.midY - clip.bounds.height / 2)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clip)
    }

    func jump(to location: Int) {
        let length = (textView.string as NSString).length
        let target = NSRange(location: min(location, length), length: 0)
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
        view.window?.makeFirstResponder(textView)
    }

    private func updateOutline() {
        let ns = textView.string as NSString
        var items: [OutlineItem] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, _, _ in
            guard let line, case let .heading(level, marker) = MarkdownParser.blockKind(of: line) else { return }
            let title = (line as NSString).substring(from: NSMaxRange(marker)).trimmingCharacters(in: .whitespaces)
            items.append(OutlineItem(level: level, title: title, location: lineRange.location))
        }
        onOutlineChange?(items)
    }

    private func updateWordCount() {
        let text = textView.string
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        statusLabel.stringValue = "\(words) words · \(text.count) characters"
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        highlighter.handleSelectionChange()
        recenterCaret()
    }

    private static let autoPairs: [String: String] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "*": "*", "_": "_", "`": "`", "~": "~"
    ]

    func textView(_ view: NSTextView, shouldChangeTextIn affectedRange: NSRange, replacementString: String?) -> Bool {
        guard let replacement = replacementString else { return true }
        let selection = textView.selectedRange()

        if selection.length > 0, NSEqualRanges(affectedRange, selection), let closing = Self.autoPairs[replacement] {
            let selected = (textView.string as NSString).substring(with: selection)
            replace(
                selection,
                with: replacement + selected + closing,
                thenSelect: NSRange(location: selection.location + 1, length: selection.length)
            )
            return false
        }

        if selection.length == 0, replacement == "(" || replacement == "[" || replacement == "{" {
            let closing = Self.autoPairs[replacement]!
            replace(
                NSRange(location: selection.location, length: 0),
                with: replacement + closing,
                thenSelect: NSRange(location: selection.location + 1, length: 0)
            )
            return false
        }

        if selection.length == 0, replacement == ")" || replacement == "]" || replacement == "}" {
            let ns = textView.string as NSString
            if selection.location < ns.length, ns.substring(with: NSRange(location: selection.location, length: 1)) == replacement {
                textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                return false
            }
        }

        return true
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
        updateWordCount()
        updateOutline()
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
            updateWordCount()
            updateOutline()
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

    @objc func exportPDF(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let baseName = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = baseName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let printInfo = NSPrintInfo()
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        configure(printInfo)
        let operation = NSPrintOperation(view: makePrintView(for: printInfo), printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    @objc func printDocument(_ sender: Any?) {
        let printInfo = NSPrintInfo()
        configure(printInfo)
        NSPrintOperation(view: makePrintView(for: printInfo), printInfo: printInfo).run()
    }

    private func configure(_ printInfo: NSPrintInfo) {
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.leftMargin = 56
        printInfo.rightMargin = 56
        printInfo.topMargin = 56
        printInfo.bottomMargin = 56
    }

    private func makePrintView(for printInfo: NSPrintInfo) -> NSTextView {
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        printView.appearance = NSAppearance(named: .aqua)
        printView.isVerticallyResizable = true
        printView.isHorizontallyResizable = false
        printView.textContainer?.widthTracksTextView = true
        printView.textStorage?.setAttributedString(highlighter.exportAttributedString())
        printView.sizeToFit()
        return printView
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

    | Feature | State |
    | ------- | ----- |
    | Tables  | styled rows |
    | Images  | paste to insert |

    ```swift
    // Syntax highlighting via tree-sitter
    func greet(_ name: String) -> String {
        return "Hello, \\(name)! Count: \\(42)"
    }
    ```

    ---

    Open a file with Cmd+O, save with Cmd+S.
    """
}
