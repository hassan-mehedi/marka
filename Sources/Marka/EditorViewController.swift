import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, @MainActor NSTextContentStorageDelegate {
    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage else { return nil }
        return displayParagraph(for: range, in: storage)
    }

    private(set) var textView: MarkaTextView!
    private var imageCache: [String: NSImage] = [:]
    private var highlighter: MarkdownHighlighter!
    private var statusLabel: NSTextField!
    private var typewriterMode = false
    var onOutlineChange: (([OutlineItem]) -> Void)?
    weak var document: MarkaDocument?

    private var fileURL: URL? { document?.fileURL }

    var text: String {
        get { textView?.string ?? pendingText }
        set {
            pendingText = newValue
            guard isViewLoaded else { return }
            textView.string = newValue
            imageCache.removeAll()
            reloadDerivedState()
        }
    }

    private var pendingText = ""

    override func loadView() {
        let textView = MarkaTextView(usingTextLayoutManager: true)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = ThemeManager.shared.current.baseFont
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.textContentStorage?.delegate = self
        textView.onPasteImage = { [weak self] data in
            self?.insertPastedImage(data) ?? false
        }
        self.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(statusLabelClicked)))
        self.statusLabel = statusLabel

        let container = OpaqueBackgroundView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
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
        textView.string = pendingText
        applyTheme()
        reloadDerivedState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.didChange,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.appearance = ThemeManager.shared.current.appearance.flatMap(NSAppearance.init(named:))
    }

    @objc private func themeDidChange() {
        applyTheme()
        reloadDerivedState()
        refreshDisplayParagraphs()
    }

    private var themeIsDark: Bool {
        if let appearance = ThemeManager.shared.current.appearance {
            return appearance == .darkAqua
        }
        return view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var mathColor: NSColor {
        ThemeManager.shared.current.textColor ?? (themeIsDark ? .white : .black)
    }

    private func applyTheme() {
        let theme = ThemeManager.shared.current
        textView.font = theme.baseFont
        textView.backgroundColor = theme.resolvedBackground
        (view as? OpaqueBackgroundView)?.color = theme.resolvedBackground
        textView.insertionPointColor = theme.resolvedText
        view.window?.appearance = theme.appearance.flatMap(NSAppearance.init(named:))
        MathRenderer.shared.clearCache()
    }

    private func reloadDerivedState() {
        highlighter.highlightAll()
        updateWordCount()
        updateOutline()
    }

    func textDidChange(_ notification: Notification) {
        highlighter.handleEdit()
        document?.updateChangeCount(.changeDone)
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

    private var lastOutline: [OutlineItem] = []

    private func updateOutline() {
        let items = MarkdownParser.outline(in: textView.string)
        let changed = items != lastOutline
        lastOutline = items
        onOutlineChange?(items)
        if changed, textView.string.contains("[TOC]") || textView.string.contains("[toc]") {
            refreshDisplayParagraphs()
        }
    }

    @objc private func statusLabelClicked() {
        let text = textView.string
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let characters = text.count
        let withoutSpaces = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        let minutes = words == 0 ? 0 : max(1, Int((Double(words) / 200).rounded(.up)))

        let rows: [(String, String)] = [
            ("Words", "\(words)"),
            ("Characters", "\(characters)"),
            ("Characters (no spaces)", "\(withoutSpaces)"),
            ("Lines", "\(lines)"),
            ("Reading time", minutes == 0 ? "\u{2014}" : "~\(minutes) min"),
        ]

        let grid = NSGridView(views: rows.map { row in
            let name = NSTextField(labelWithString: row.0)
            name.font = .systemFont(ofSize: 12)
            name.textColor = .secondaryLabelColor
            let value = NSTextField(labelWithString: row.1)
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            value.alignment = .right
            return [name, value]
        })
        grid.columnSpacing = 24
        grid.rowSpacing = 5
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSViewController()
        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        content.view = container

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = content
        popover.show(relativeTo: statusLabel.bounds, of: statusLabel, preferredEdge: .maxY)
    }

    private func updateWordCount() {
        let text = textView.string
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        statusLabel.stringValue = "\(words) words · \(text.count) characters"
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, url.scheme == "marka-jump" else { return false }
        if let location = Int(url.lastPathComponent) {
            jump(to: location)
        }
        return true
    }

    private var lastSelection = NSRange(location: 0, length: 0)
    private var correctingSelection = false

    func textViewDidChangeSelection(_ notification: Notification) {
        if !correctingSelection {
            correctCaretAfterReveal()
        }
        lastSelection = textView.selectedRange()
        highlighter.handleSelectionChange()
        recenterCaret()
    }

    // A collapsed paragraph lays out fewer characters than the source holds,
    // so a click into it lands the caret short by the hidden width. Remap the
    // display column back to a source offset the moment the caret enters.
    private func correctCaretAfterReveal() {
        let selection = textView.selectedRange()
        guard selection.length == 0, !highlighter.revealAllMarkers else { return }
        let ns = textView.string as NSString
        guard selection.location <= ns.length else { return }
        let paragraph = ns.paragraphRange(for: selection)
        guard paragraph.length > 0, !isLiteralParagraph(paragraph) else { return }
        guard !selectionTouches(paragraph, lastSelection) else { return }

        let column = selection.location - paragraph.location
        guard column > 0 else { return }
        var line = ns.substring(with: paragraph)
        if line.hasSuffix("\n") { line.removeLast() }
        let source = min(Self.sourceOffset(forDisplayColumn: column, in: line), (line as NSString).length)
        guard source != column else { return }

        correctingSelection = true
        textView.setSelectedRange(NSRange(location: paragraph.location + source, length: 0))
        correctingSelection = false
    }

    private static let autoPairs: [String: String] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "*": "*", "_": "_", "`": "`", "~": "~"
    ]

    func textView(_ view: NSTextView, shouldChangeTextIn affectedRange: NSRange, replacementString: String?) -> Bool {
        guard let replacement = replacementString else { return true }
        let selection = textView.selectedRange()

        if smartPunctuation, selection.length == 0, NSEqualRanges(affectedRange, selection),
           let smart = smartReplacement(for: replacement, at: selection.location) {
            replace(
                smart.range,
                with: smart.text,
                thenSelect: NSRange(location: smart.range.location + (smart.text as NSString).length, length: 0)
            )
            return false
        }

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

    private static let smartPunctuationKey = "MarkaSmartPunctuation"
    private var smartPunctuation = UserDefaults.standard.bool(forKey: smartPunctuationKey)

    @objc func toggleSmartPunctuation(_ sender: NSMenuItem) {
        smartPunctuation.toggle()
        UserDefaults.standard.set(smartPunctuation, forKey: Self.smartPunctuationKey)
        sender.state = smartPunctuation ? .on : .off
    }

    private func smartReplacement(for typed: String, at location: Int) -> (range: NSRange, text: String)? {
        guard typed == "\"" || typed == "'" || typed == "-" else { return nil }
        guard !isLiteralContext(at: location) else { return nil }

        let ns = textView.string as NSString
        let lineRange = ns.paragraphRange(for: NSRange(location: location, length: 0))
        let lineBeforeCaret = ns.substring(with: NSRange(location: lineRange.location, length: location - lineRange.location))
        let previous: Character? = lineBeforeCaret.last

        switch typed {
        case "\"", "'":
            let opens = previous == nil || previous!.isWhitespace || "([{".contains(previous!)
            let text: String
            if typed == "\"" {
                text = opens ? "\u{201C}" : "\u{201D}"
            } else {
                text = opens ? "\u{2018}" : "\u{2019}"
            }
            return (NSRange(location: location, length: 0), text)
        default:
            guard previous == "-" else { return nil }
            // Leave horizontal rules, front matter fences, and table separators alone.
            let hyphensOnly = lineBeforeCaret.trimmingCharacters(in: .whitespaces).allSatisfy { $0 == "-" }
            guard !hyphensOnly, !lineBeforeCaret.contains("|") else { return nil }
            let beforePair = lineBeforeCaret.dropLast().last
            guard beforePair == nil || beforePair!.isWhitespace || beforePair!.isLetter || beforePair!.isNumber else {
                return nil
            }
            return (NSRange(location: location - 1, length: 1), "\u{2014}")
        }
    }

    private func isLiteralContext(at location: Int) -> Bool {
        if highlighter.fences.blocks.contains(where: { NSLocationInRange(location, $0.fullRange) }) { return true }
        if highlighter.mathBlocks.contains(where: { NSLocationInRange(location, $0.fullRange) }) { return true }
        if let frontMatter = highlighter.frontMatter, NSLocationInRange(location, frontMatter) { return true }

        let ns = textView.string as NSString
        let lineRange = ns.paragraphRange(for: NSRange(location: location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        if case .fenceDelimiter = MarkdownParser.blockKind(of: line) { return true }
        let column = location - lineRange.location
        for span in MarkdownParser.inlineSpans(in: line) where span.kind == .code {
            if column > span.range.location, column < NSMaxRange(span.range) { return true }
        }
        for math in MarkdownParser.inlineMathSpans(in: line) {
            if column > math.range.location, column < NSMaxRange(math.range) { return true }
        }
        return false
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

    private func insertPastedImage(_ data: Data) -> Bool {
        let directory: URL
        let markdownPath: String
        let stamp = Self.imageStamp.string(from: Date())
        let name = "image-\(stamp).png"

        if let fileURL {
            directory = fileURL.deletingLastPathComponent().appendingPathComponent("assets")
            markdownPath = "assets/\(name)"
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MarkaImages")
            markdownPath = directory.appendingPathComponent(name).path
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name))
        } catch {
            NSAlert(error: error).runModal()
            return false
        }

        textView.insertText("![](\(markdownPath))", replacementRange: textView.selectedRange())
        return true
    }

    private static let imageStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    func resolvedImage(at path: String) -> NSImage? {
        if let cached = imageCache[path] {
            return cached
        }
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if let fileURL {
            url = fileURL.deletingLastPathComponent().appendingPathComponent(path)
        } else {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[path] = image
        return image
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let url = runExportPanel(extension: "html", type: .html) else { return }
        let title = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let html = HTMLExporter.document(from: textView.string, title: title)
        do {
            try Data(html.utf8).write(to: url)
        } catch {
            presentError(error)
        }
    }

    @objc func exportDocx(_ sender: Any?) {
        guard let url = runExportPanel(
            extension: "docx",
            type: UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        ) else { return }
        let fragment = HTMLExporter.fragment(from: textView.string)
        do {
            let attributed = try NSAttributedString(
                data: Data(fragment.utf8),
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
            try data.write(to: url)
        } catch {
            presentError(error)
        }
    }

    @objc func exportEpub(_ sender: Any?) {
        exportWithPandoc(extension: "epub", type: UTType("org.idpf.epub-container") ?? .data, format: "epub")
    }

    @objc func exportLaTeX(_ sender: Any?) {
        exportWithPandoc(extension: "tex", type: UTType(filenameExtension: "tex") ?? .plainText, format: "latex")
    }

    private func exportWithPandoc(extension ext: String, type: UTType, format: String) {
        guard let url = runExportPanel(extension: ext, type: type) else { return }
        let title = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        do {
            try PandocExporter.export(
                markdown: textView.string,
                to: url,
                format: format,
                title: title,
                workingDirectory: fileURL?.deletingLastPathComponent()
            )
        } catch {
            presentError(error)
        }
    }

    private func runExportPanel(extension ext: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let baseName = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = baseName + "." + ext
        guard panel.runModal() == .OK else { return nil }
        return panel.url
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

    @objc func printMarkdown(_ sender: Any?) {
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

    fileprivate func displayParagraph(for range: NSRange, in storage: NSTextStorage) -> NSTextParagraph? {
        let ns = storage.string as NSString
        var line = ns.substring(with: range)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }
        let selection = textView.selectedRange()

        if let mermaid = mermaidParagraph(for: range, selection: selection) {
            return mermaid
        }

        if let math = mathBlockParagraph(for: range, selection: selection) {
            return math
        }

        if MarkdownParser.isTOCLine(line), !selectionTouches(range, selection),
           let toc = tocParagraph(newline: hadNewline) {
            return toc
        }

        if !selectionTouches(range, selection) {
            if let path = MarkdownParser.imageLinePath(in: line), let image = resolvedImage(at: path) {
                return blockParagraph(with: image, centered: false, newline: hadNewline)
            }
            if let latex = MarkdownParser.displayMathContent(in: line),
               let image = MathRenderer.shared.image(
                   latex: latex,
                   fontSize: ThemeManager.shared.current.baseFont.pointSize * 1.2,
                   display: true,
                   color: mathColor
               ) {
                return blockParagraph(with: image, centered: true, newline: hadNewline)
            }
        }

        return styledParagraph(for: range, line: line, storage: storage, selection: selection)
    }

    // Source ranges that render with a different length: markers vanish,
    // an inline math span becomes a single attachment character.
    nonisolated static func displayReplacements(in line: String) -> [(range: NSRange, displayLength: Int)] {
        var replacements: [(NSRange, Int)] = []
        if case let .heading(_, marker) = MarkdownParser.blockKind(of: line) {
            replacements.append((marker, 0))
        }
        for span in MarkdownParser.inlineSpans(in: line) {
            replacements.append((span.openMarker, 0))
            replacements.append((span.closeMarker, 0))
        }
        replacements += MarkdownParser.inlineMathSpans(in: line).map { ($0.range, 1) }
        replacements.sort { $0.0.location < $1.0.location }

        var result: [(NSRange, Int)] = []
        for replacement in replacements {
            if let last = result.last, NSMaxRange(last.0) > replacement.0.location { continue }
            result.append(replacement)
        }
        return result
    }

    nonisolated static func sourceOffset(forDisplayColumn column: Int, in line: String) -> Int {
        var source = 0
        var display = 0
        for (range, displayLength) in displayReplacements(in: line) {
            let visible = range.location - source
            if display + visible >= column {
                return source + (column - display)
            }
            display += visible
            source = range.location
            if display + displayLength > column {
                return source
            }
            display += displayLength
            source = NSMaxRange(range)
        }
        return source + (column - display)
    }

    private func isLiteralParagraph(_ range: NSRange) -> Bool {
        if highlighter.fences.blocks.contains(where: { NSLocationInRange(range.location, $0.fullRange) }) { return true }
        if highlighter.fences.delimiterLines.contains(where: { NSLocationInRange(range.location, $0) }) { return true }
        if highlighter.mathBlocks.contains(where: { NSLocationInRange(range.location, $0.fullRange) }) { return true }
        if let frontMatter = highlighter.frontMatter, NSLocationInRange(range.location, frontMatter) { return true }
        return false
    }

    private func styledParagraph(
        for range: NSRange,
        line: String,
        storage: NSTextStorage,
        selection: NSRange
    ) -> NSTextParagraph? {
        guard !highlighter.revealAllMarkers, !isLiteralParagraph(range) else { return nil }

        let lineNS = line as NSString
        let paragraphUntouched = !selectionTouches(range, selection)
        let display = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var changed = false

        for (span, displayLength) in Self.displayReplacements(in: line).reversed() {
            if displayLength == 1 {
                let mathSpans = MarkdownParser.inlineMathSpans(in: line)
                guard let math = mathSpans.first(where: { $0.range == span }) else { continue }
                let global = NSRange(location: range.location + span.location, length: span.length)
                guard !selectionTouches(global, selection) else { continue }
                guard let image = MathRenderer.shared.image(
                    latex: lineNS.substring(with: math.content),
                    fontSize: ThemeManager.shared.current.baseFont.pointSize,
                    display: false,
                    color: mathColor
                ) else { continue }

                let attachment = NSTextAttachment()
                attachment.image = image
                // Sit the formula on the text baseline instead of the line bottom.
                attachment.bounds = NSRect(
                    x: 0,
                    y: ThemeManager.shared.current.baseFont.descender * 0.6,
                    width: image.size.width,
                    height: image.size.height
                )
                display.replaceCharacters(in: span, with: NSAttributedString(attachment: attachment))
                changed = true
            } else if paragraphUntouched {
                display.deleteCharacters(in: span)
                changed = true
            }
        }

        guard changed else { return nil }
        return NSTextParagraph(attributedString: display)
    }

    private func mermaidParagraph(for range: NSRange, selection: NSRange) -> NSTextParagraph? {
        guard let block = highlighter.fences.blocks.first(where: {
            $0.language.lowercased() == "mermaid" && NSLocationInRange(range.location, $0.fullRange)
        }) else { return nil }
        guard !selectionTouches(block.fullRange, selection) else { return nil }

        let source = (textView.string as NSString).substring(with: block.range)
        let dark = themeIsDark
        guard let image = MermaidRenderer.shared.image(for: source, dark: dark, onReady: { [weak self] in
            self?.refreshDisplayParagraphs()
        }) else {
            // Still rendering or failed: collapse the block so the code does not flash.
            return Self.collapsedParagraph()
        }

        // The diagram takes the place of the opening fence line; the rest collapses.
        guard NSLocationInRange(range.location, block.openDelimiter) else {
            return Self.collapsedParagraph()
        }
        return blockParagraph(with: image, centered: true, newline: true)
    }

    private func mathBlockParagraph(for range: NSRange, selection: NSRange) -> NSTextParagraph? {
        guard let block = highlighter.mathBlocks.first(where: { NSLocationInRange(range.location, $0.fullRange) }) else {
            return nil
        }
        guard !selectionTouches(block.fullRange, selection) else { return nil }

        let latex = (textView.string as NSString).substring(with: block.range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty,
              let image = MathRenderer.shared.image(
                  latex: latex,
                  fontSize: ThemeManager.shared.current.baseFont.pointSize * 1.2,
                  display: true,
                  color: mathColor
              ) else { return nil }

        guard NSLocationInRange(range.location, block.openDelimiter) else {
            return Self.collapsedParagraph()
        }
        return blockParagraph(with: image, centered: true, newline: true)
    }

    private func tocParagraph(newline: Bool) -> NSTextParagraph? {
        let items = lastOutline
        guard !items.isEmpty else { return nil }
        let theme = ThemeManager.shared.current
        let result = NSMutableAttributedString()
        let baseLevel = items.map(\.level).min() ?? 1
        for (offset, item) in items.enumerated() {
            let indent = String(repeating: "      ", count: item.level - baseLevel)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: item.level == baseLevel
                    ? NSFontManager.shared.convert(theme.baseFont, toHaveTrait: .boldFontMask)
                    : theme.baseFont,
                .foregroundColor: theme.resolvedLink,
            ]
            if let url = URL(string: "marka-jump://heading/\(item.location)") {
                attributes[.link] = url
            }
            // U+2028 keeps the whole list inside one text paragraph.
            let separator = offset == items.count - 1 ? "" : "\u{2028}"
            result.append(NSAttributedString(string: indent + item.title + separator, attributes: attributes))
        }
        if newline {
            result.append(NSAttributedString(string: "\n", attributes: [.font: theme.baseFont]))
        }
        return NSTextParagraph(attributedString: result)
    }

    private static func collapsedParagraph() -> NSTextParagraph {
        NSTextParagraph(attributedString: NSAttributedString(
            string: "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]
        ))
    }

    private func refreshDisplayParagraphs() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        textView.textContentStorage?.performEditingTransaction {
            storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        }
    }


    private func blockParagraph(with image: NSImage, centered: Bool, newline: Bool) -> NSTextParagraph {
        let insets = textView.textContainerInset.width * 2
        let maxWidth = max(120, textView.bounds.width - insets - 24)
        let scale = image.size.width > maxWidth ? maxWidth / image.size.width : 1

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: 0,
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let display = NSMutableAttributedString(attachment: attachment)
        if newline {
            display.append(NSAttributedString(string: "\n"))
        }
        if centered {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            display.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: display.length)
            )
        }
        return NSTextParagraph(attributedString: display)
    }

    private func selectionTouches(_ range: NSRange, _ selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= NSMaxRange(range)
        }
        return NSIntersectionRange(range, selection).length > 0
    }

    static let sampleDocument = """
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

    Math: inline $E = mc^2$ and a display equation.

    $$ \\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2} $$

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
