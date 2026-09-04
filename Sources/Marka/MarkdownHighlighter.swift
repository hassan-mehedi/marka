import AppKit

@MainActor
final class MarkdownHighlighter: NSObject, @MainActor NSTextStorageDelegate {
    private unowned let textView: NSTextView
    // Snapshot taken at the start of each styling pass.
    private var theme = ThemeManager.shared.current
    var revealAllMarkers = false
    var focusMode = false
    private(set) var fences = FenceInfo()
    private(set) var mathBlocks: [MathBlock] = []
    private(set) var tables: [TableBlock] = []
    private var exporting = false
    private(set) var frontMatter: NSRange?
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
        pendingEditStart = min(pendingEditStart ?? editedRange.location, editedRange.location)
        pendingDelta += delta
    }

    private var pendingEditStart: Int?
    private var pendingDelta = 0

    func highlightAll() {
        guard let storage = textView.textStorage else { return }
        let structure = MarkdownParser.structure(in: storage.string)
        fences = structure.fences
        mathBlocks = structure.mathBlocks
        tables = structure.tables
        frontMatter = structure.frontMatter
        codeTokenCache.removeAll()
        restyle(paragraphsIn: NSRange(location: 0, length: storage.length), storage: storage)
        pendingEditedRange = nil
        pendingEditStart = nil
        pendingDelta = 0
        previousSelection = textView.selectedRange()
    }

    func handleEdit() {
        guard let storage = textView.textStorage else { return }
        let structure = MarkdownParser.structure(in: storage.string)
        let newFences = structure.fences
        let newMathBlocks = structure.mathBlocks
        let newTables = structure.tables
        let newFrontMatter = structure.frontMatter

        // Typing shifts every block after the caret; only a change in the
        // block structure itself needs the whole document restyled.
        let edit = (start: pendingEditStart ?? 0, delta: pendingDelta)
        let structureChanged = !Self.sameStructure(old: fences, new: newFences, edit: edit)
            || newMathBlocks.map(\.fullRange) != mathBlocks.map { Self.shift($0.fullRange, by: edit) }
            || newTables.map(\.fullRange) != tables.map { Self.shift($0.fullRange, by: edit) }
            || newFrontMatter != frontMatter.map { Self.shift($0, by: edit) }
        fences = newFences
        mathBlocks = newMathBlocks
        tables = newTables
        frontMatter = newFrontMatter
        if structureChanged {
            codeTokenCache.removeAll()
            restyle(paragraphsIn: NSRange(location: 0, length: storage.length), storage: storage)
        } else if let edited = pendingEditedRange {
            restyle(paragraphsIn: edited, storage: storage)
            // Undo moves the caret in the same pass as the edit, so the
            // paragraphs it left and landed in need their markers redone too.
            let ns = storage.string as NSString
            let left = expandToBlock(ns.paragraphRange(for: clamp(previousSelection, to: ns.length)))
            let entered = expandToBlock(ns.paragraphRange(for: clamp(textView.selectedRange(), to: ns.length)))
            for block in [left, entered] where NSIntersectionRange(block, edited).length == 0 && !NSEqualRanges(block, edited) {
                restyle(paragraphsIn: block, storage: storage)
            }
        }
        pendingEditedRange = nil
        pendingEditStart = nil
        pendingDelta = 0
        previousSelection = textView.selectedRange()
    }

    static func shift(_ range: NSRange, by edit: (start: Int, delta: Int)) -> NSRange {
        if range.location >= edit.start {
            return NSRange(location: range.location + edit.delta, length: range.length)
        }
        if NSMaxRange(range) >= edit.start {
            return NSRange(location: range.location, length: max(range.length + edit.delta, 0))
        }
        return range
    }

    static func sameStructure(old: FenceInfo, new: FenceInfo, edit: (start: Int, delta: Int)) -> Bool {
        guard old.blocks.count == new.blocks.count, old.delimiterLines.count == new.delimiterLines.count else { return false }
        for (oldBlock, newBlock) in zip(old.blocks, new.blocks) {
            guard oldBlock.language == newBlock.language,
                  shift(oldBlock.range, by: edit) == newBlock.range,
                  shift(oldBlock.openDelimiter, by: edit) == newBlock.openDelimiter,
                  oldBlock.closeDelimiter.map { shift($0, by: edit) } == newBlock.closeDelimiter
            else { return false }
        }
        return true
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
        if let table = tables.first(where: { touches($0.fullRange, range) }) {
            result = NSUnionRange(result, table.fullRange)
        }
        return result
    }

    private func touches(_ block: NSRange, _ range: NSRange) -> Bool {
        NSIntersectionRange(block, range).length > 0 || NSLocationInRange(range.location, block)
    }

    func exportAttributedString() -> NSAttributedString {
        guard let storage = textView.textStorage else { return NSAttributedString() }
        let copy = NSTextStorage(string: storage.string)
        let saved = (revealAllMarkers, focusMode)
        revealAllMarkers = false
        focusMode = false
        exporting = true
        let nowhere = NSRange(location: copy.length + 1, length: 0)
        restyle(paragraphsIn: NSRange(location: 0, length: copy.length), storage: copy, selection: nowhere)
        exporting = false
        (revealAllMarkers, focusMode) = saved
        return copy
    }

    // One table cell or similar fragment, styled inline with its markers removed.
    func inlineStyled(_ line: String, bold: Bool = false) -> NSAttributedString {
        theme = ThemeManager.shared.current
        let storage = NSTextStorage(string: line)
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes([.font: theme.baseFont, .foregroundColor: theme.resolvedText], range: full)
        if bold {
            addTrait(.boldFontMask, range: full, storage: storage)
        }
        let nowhere = NSRange(location: storage.length + 1, length: 0)
        let saved = revealAllMarkers
        revealAllMarkers = false
        let spans = LineCache.info(for: line).inlineSpans
        for span in spans {
            applyInline(span, offset: 0, storage: storage, selection: nowhere)
        }
        revealAllMarkers = saved
        let markers = spans.flatMap { [$0.openMarker, $0.closeMarker] }.sorted { $0.location > $1.location }
        for marker in markers {
            storage.deleteCharacters(in: marker)
        }
        return storage
    }

    private static let codeParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.tailIndent = -12
        return style
    }()

    private func restyle(paragraphsIn range: NSRange, storage: NSTextStorage, selection: NSRange? = nil) {
        theme = ThemeManager.shared.current
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

        if let frontMatter, NSLocationInRange(paragraph.location, frontMatter) {
            let trimmed = ns.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
            let color = trimmed == "---" || trimmed == "..." ? theme.resolvedMarker : theme.resolvedSecondary
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: color], range: paragraph)
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        }

        if mathBlocks.contains(where: { NSLocationInRange(paragraph.location, $0.fullRange) }) {
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.resolvedMarker], range: paragraph)
            dimIfUnfocused(paragraph, storage: storage, selection: selection)
            return
        }

        if let block = fences.block(containing: paragraph) {
            storage.addAttributes([.font: theme.codeFont, .paragraphStyle: Self.codeParagraphStyle], range: paragraph)
            if exporting {
                storage.addAttribute(.backgroundColor, value: theme.resolvedCodeBackground, range: paragraph)
            }
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
        let info = LineCache.info(for: trimmed)

        switch info.blockKind {
        case .fenceDelimiter:
            storage.addAttributes(
                [.font: theme.codeFont, .foregroundColor: theme.resolvedMarker, .paragraphStyle: Self.codeParagraphStyle],
                range: paragraph
            )
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
            if info.isTOC {
                storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: paragraph)
            }
            if let definition = info.footnoteDefinition {
                storage.addAttribute(.foregroundColor, value: theme.resolvedAccent, range: shifted(definition, by: paragraph.location))
                let rest = NSRange(
                    location: paragraph.location + NSMaxRange(definition),
                    length: paragraph.length - NSMaxRange(definition)
                )
                storage.addAttribute(.foregroundColor, value: theme.resolvedSecondary, range: rest)
            }
            styleTableRowIfNeeded(info, paragraph: paragraph, ns: ns, storage: storage)
        }

        for reference in info.footnoteReferences {
            let range = shifted(reference.range, by: paragraph.location)
            let size = theme.baseFontSize * 0.75
            storage.addAttributes([
                .foregroundColor: theme.resolvedAccent,
                .font: FontCache.font(theme.baseFont, size: size),
                .baselineOffset: theme.baseFontSize * 0.3,
            ], range: range)
        }

        for span in info.inlineSpans {
            applyInline(span, offset: paragraph.location, storage: storage, selection: selection)
        }

        styleMathDelimiters(info, paragraph: paragraph, storage: storage)

        dimIfUnfocused(paragraph, storage: storage, selection: selection)
    }

    private func styleMathDelimiters(_ info: LineInfo, paragraph: NSRange, storage: NSTextStorage) {
        if info.displayMath != nil {
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: paragraph)
            return
        }
        for math in info.inlineMath {
            let open = NSRange(location: paragraph.location + math.range.location, length: 1)
            let close = NSRange(location: paragraph.location + NSMaxRange(math.range) - 1, length: 1)
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: open)
            storage.addAttribute(.foregroundColor, value: theme.resolvedMarker, range: close)
        }
    }

    private func styleTableRowIfNeeded(_ info: LineInfo, paragraph: NSRange, ns: NSString, storage: NSTextStorage) {
        let pipes = info.pipes
        guard !pipes.isEmpty else { return }

        let previous = neighborLine(of: paragraph, ns: ns, forward: false).map(LineCache.info(for:))
        let next = neighborLine(of: paragraph, ns: ns, forward: true).map(LineCache.info(for:))
        let nextIsSeparator = next?.blockKind == .tableSeparator
        let previousIsSeparator = previous?.blockKind == .tableSeparator
        let previousIsRow = previous.map { !$0.pipes.isEmpty } ?? false
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
        case .image:
            storage.addAttribute(.foregroundColor, value: theme.resolvedSecondary, range: content)
        }

        applyMarker(storage, range: shifted(span.openMarker, by: offset), revealed: revealed)
        applyMarker(storage, range: shifted(span.closeMarker, by: offset), revealed: revealed)
    }

    private func addTrait(_ trait: NSFontTraitMask, range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? theme.baseFont
            storage.addAttribute(.font, value: FontCache.font(font, withTrait: trait), range: subrange)
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
