import AppKit

@MainActor
final class MarkdownHighlighter: NSObject, @MainActor NSTextStorageDelegate {
    private unowned let textView: NSTextView
    private var theme: Theme { ThemeManager.shared.current }
    var revealAllMarkers = false
    var focusMode = false
    private(set) var fences = FenceInfo()
    private(set) var mathBlocks: [MathBlock] = []
    private var pendingEditedRange: NSRange?
    private var previousSelection = NSRange(location: 0, length: 0)

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        textView.textStorage?.delegate = self
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        pendingEditedRange = pendingEditedRange.map { NSUnionRange($0, editedRange) } ?? editedRange
    }

    func highlightAll() {
        guard let storage = textView.textStorage else { return }
        fences = MarkdownParser.fences(in: storage.string)
        mathBlocks = MarkdownParser.mathBlocks(in: storage.string, excluding: fences)
        codeTokenCache.removeAll()
        restyle(paragraphsIn: NSRange(location: 0, length: storage.length), storage: storage)
        pendingEditedRange = nil
        previousSelection = textView.selectedRange()
    }

    func handleEdit() {
        guard let storage = textView.textStorage else { return }
        let newFences = MarkdownParser.fences(in: storage.string)
        let newMathBlocks = MarkdownParser.mathBlocks(in: storage.string, excluding: newFences)
        if newFences != fences || newMathBlocks != mathBlocks {
            fences = newFences
            mathBlocks = newMathBlocks
            codeTokenCache.removeAll()
            restyle(paragraphsIn: NSRange(location: 0, length: storage.length), storage: storage)
        } else if let edited = pendingEditedRange {
            restyle(paragraphsIn: edited, storage: storage)
        }
        pendingEditedRange = nil
        previousSelection = textView.selectedRange()
    }

    func handleSelectionChange() {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        defer { previousSelection = selection }
        guard pendingEditedRange == nil else { return }

        let ns = storage.string as NSString
        // Restyle the whole block when the caret crosses a mermaid fence or a
        // math block, so every collapsed paragraph in it rebuilds together.
        let old = expandToBlock(ns.paragraphRange(for: clamp(previousSelection, to: ns.length)))
        let new = expandToBlock(ns.paragraphRange(for: clamp(selection, to: ns.length)))
        restyle(paragraphsIn: old, storage: storage)
        if !NSEqualRanges(old, new) {
            restyle(paragraphsIn: new, storage: storage)
        }
    }

    private func expandToBlock(_ range: NSRange) -> NSRange {
        var result = range
        if let fence = fences.blocks.first(where: { touches($0.fullRange, range) }) {
            result = NSUnionRange(result, fence.fullRange)
        }
        if let math = mathBlocks.first(where: { touches($0.fullRange, range) }) {
            result = NSUnionRange(result, math.fullRange)
        }
        return result
    }

    private func touches(_ block: NSRange, _ range: NSRange) -> Bool {
        NSIntersectionRange(block, range).length > 0 || NSLocationInRange(range.location, block)
    }

    func exportAttributedString() -> NSAttributedString {
        guard let storage = textView.textStorage else { return NSAttributedString() }
        let copy = NSTextStorage(string: storage.string)
        let saved = revealAllMarkers
        revealAllMarkers = false
        let nowhere = NSRange(location: copy.length + 1, length: 0)
        restyle(paragraphsIn: NSRange(location: 0, length: copy.length), storage: copy, selection: nowhere)
        revealAllMarkers = saved
        return copy
    }

    private func restyle(paragraphsIn range: NSRange, storage: NSTextStorage, selection: NSRange? = nil) {
        let ns = storage.string as NSString
        var target = ns.paragraphRange(for: clamp(range, to: ns.length))
        // Include one paragraph on each side: table header styling depends on neighbors.
        if target.location > 0 {
            let previous = ns.paragraphRange(for: NSRange(location: target.location - 1, length: 0))
            target = NSUnionRange(target, previous)
        }
        if NSMaxRange(target) < ns.length {
            let next = ns.paragraphRange(for: NSRange(location: NSMaxRange(target), length: 0))
            target = NSUnionRange(target, next)
        }
        let selection = selection ?? textView.selectedRange()

        storage.beginEditing()
        var location = target.location
        while location < NSMaxRange(target) {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            styleParagraph(paragraph, ns: ns, storage: storage, selection: selection)
            location = NSMaxRange(paragraph)
        }
        storage.endEditing()
    }

    private func styleParagraph(_ paragraph: NSRange, ns: NSString, storage: NSTextStorage, selection: NSRange) {
        storage.setAttributes([.font: theme.baseFont, .foregroundColor: theme.resolvedText], range: paragraph)

        if mathBlocks.contains(where: { NSLocationInRange(paragraph.location, $0.fullRange) }) {
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.resolvedMarker], range: paragraph)
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        }

        if let block = fences.block(containing: paragraph) {
            storage.addAttributes([.font: theme.codeFont, .backgroundColor: theme.resolvedCodeBackground], range: paragraph)
            for token in tokens(for: block, ns: ns) {
                let global = shifted(token.range, by: block.range.location)
                let intersection = NSIntersectionRange(global, paragraph)
                if intersection.length > 0, let color = theme.tokenColor(String(token.name.split(separator: ".").first ?? "")) {
                    storage.addAttribute(.foregroundColor, value: color, range: intersection)
                }
            }
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        }

        let line = ns.substring(with: paragraph)
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line

        switch MarkdownParser.blockKind(of: trimmed) {
        case .fenceDelimiter:
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.resolvedMarker], range: paragraph)
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        case .horizontalRule:
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: paragraph)
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        case let .heading(level, marker):
            storage.addAttribute(.font, value: theme.headingFont(level: level), range: paragraph)
            applyMarker(
                storage,
                range: shifted(marker, by: paragraph.location),
                revealed: caretTouches(paragraph, selection: selection)
            )
        case let .blockquote(marker):
            let markerRange = shifted(marker, by: paragraph.location)
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: markerRange)
            let rest = NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(paragraph) - NSMaxRange(markerRange))
            storage.addAttribute(.foregroundColor, value: theme.resolvedSecondary, range: rest)
        case let .listItem(marker):
            storage.addAttribute(.foregroundColor, value: theme.resolvedAccent, range: shifted(marker, by: paragraph.location))
        case let .taskListItem(marker, box, checked):
            let markerRange = shifted(marker, by: paragraph.location)
            let boxRange = shifted(box, by: paragraph.location)
            storage.addAttribute(.foregroundColor, value: theme.resolvedAccent, range: markerRange)
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.resolvedAccent], range: boxRange)
            if checked {
                let rest = NSRange(location: NSMaxRange(boxRange), length: NSMaxRange(paragraph) - NSMaxRange(boxRange))
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: theme.resolvedSecondary],
                    range: rest
                )
            }
        case .tableSeparator:
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: paragraph)
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        case .paragraph:
            styleTableRowIfNeeded(trimmed, paragraph: paragraph, ns: ns, storage: storage)
        }

        for span in MarkdownParser.inlineSpans(in: trimmed) {
            applyInline(span, offset: paragraph.location, storage: storage, selection: selection)
        }

        styleMathDelimiters(in: trimmed, paragraph: paragraph, storage: storage)

        dimIfUnfocused(paragraph, storage: storage, selection: selection)
    }

    private func styleMathDelimiters(in line: String, paragraph: NSRange, storage: NSTextStorage) {
        if MarkdownParser.displayMathContent(in: line) != nil {
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: paragraph)
            return
        }
        for math in MarkdownParser.inlineMathSpans(in: line) {
            let open = NSRange(location: paragraph.location + math.range.location, length: 1)
            let close = NSRange(location: paragraph.location + NSMaxRange(math.range) - 1, length: 1)
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: open)
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: close)
        }
    }

    private func styleTableRowIfNeeded(_ line: String, paragraph: NSRange, ns: NSString, storage: NSTextStorage) {
        let pipes = MarkdownParser.pipeRanges(in: line)
        guard !pipes.isEmpty else { return }

        let previous = neighborLine(of: paragraph, ns: ns, forward: false)
        let next = neighborLine(of: paragraph, ns: ns, forward: true)
        let nextIsSeparator = next.map { MarkdownParser.blockKind(of: $0) == .tableSeparator } ?? false
        let previousIsSeparator = previous.map { MarkdownParser.blockKind(of: $0) == .tableSeparator } ?? false
        let previousIsRow = previous.map { !MarkdownParser.pipeRanges(in: $0).isEmpty } ?? false
        guard nextIsSeparator || previousIsSeparator || previousIsRow else { return }

        for pipe in pipes {
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: shifted(pipe, by: paragraph.location))
        }
        if nextIsSeparator {
            addTrait(.boldFontMask, range: paragraph, storage: storage)
        }
    }

    private func neighborLine(of paragraph: NSRange, ns: NSString, forward: Bool) -> String? {
        let location: Int
        if forward {
            guard NSMaxRange(paragraph) < ns.length else { return nil }
            location = NSMaxRange(paragraph)
        } else {
            guard paragraph.location > 0 else { return nil }
            location = paragraph.location - 1
        }
        let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
        var line = ns.substring(with: range)
        if line.hasSuffix("\n") { line.removeLast() }
        return line
    }

    private var codeTokenCache: [Int: (code: String, tokens: [CodeHighlighter.Token])] = [:]

    private func tokens(for block: FenceBlock, ns: NSString) -> [CodeHighlighter.Token] {
        guard !block.language.isEmpty else { return [] }
        let code = ns.substring(with: block.range)
        if let cached = codeTokenCache[block.range.location], cached.code == code {
            return cached.tokens
        }
        let tokens = CodeHighlighter.shared.highlights(for: code, language: block.language)
        codeTokenCache[block.range.location] = (code, tokens)
        return tokens
    }

    private func dimIfUnfocused(_ paragraph: NSRange, storage: NSTextStorage, selection: NSRange) {
        guard focusMode, !selectionTouches(paragraph, selection: selection) else { return }
        storage.enumerateAttribute(.foregroundColor, in: paragraph) { value, subrange, _ in
            guard let color = value as? NSColor, color != .clear else { return }
            storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.35), range: subrange)
        }
    }

    private func applyInline(_ span: InlineSpan, offset: Int, storage: NSTextStorage, selection: NSRange) {
        let content = shifted(span.content, by: offset)
        let whole = shifted(span.range, by: offset)
        let revealed = caretTouches(whole, selection: selection)

        switch span.kind {
        case .code:
            storage.addAttributes([.font: theme.codeFont, .backgroundColor: theme.resolvedCodeBackground], range: content)
        case .bold:
            addTrait(.boldFontMask, range: content, storage: storage)
        case .italic:
            addTrait(.italicFontMask, range: content, storage: storage)
        case .boldItalic:
            addTrait(.boldFontMask, range: content, storage: storage)
            addTrait(.italicFontMask, range: content, storage: storage)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
        case let .link(url):
            storage.addAttribute(.foregroundColor, value: theme.resolvedLink, range: content)
            if !revealed, let parsed = URL(string: url) {
                storage.addAttribute(.link, value: parsed, range: content)
            }
        }

        applyMarker(storage, range: shifted(span.openMarker, by: offset), revealed: revealed)
        applyMarker(storage, range: shifted(span.closeMarker, by: offset), revealed: revealed)
    }

    private func addTrait(_ trait: NSFontTraitMask, range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? theme.baseFont
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }

    private func applyMarker(_ storage: NSTextStorage, range: NSRange, revealed: Bool) {
        if revealed {
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: range)
        } else {
            storage.addAttributes(
                [.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)],
                range: range
            )
        }
    }

    private func caretTouches(_ range: NSRange, selection: NSRange) -> Bool {
        if revealAllMarkers { return true }
        return selectionTouches(range, selection: selection)
    }

    private func selectionTouches(_ range: NSRange, selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= NSMaxRange(range)
        }
        return NSIntersectionRange(range, selection).length > 0
    }

    private func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }
}
