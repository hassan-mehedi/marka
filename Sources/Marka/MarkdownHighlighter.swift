import AppKit

@MainActor
final class MarkdownHighlighter: NSObject, @MainActor NSTextStorageDelegate {
    static let baseFont = NSFont.systemFont(ofSize: 16)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let codeBackground = NSColor.systemGray.withAlphaComponent(0.15)
    private static let headingSizes: [CGFloat] = [28, 24, 21, 19, 17, 16]

    private unowned let textView: NSTextView
    var revealAllMarkers = false
    private var fences = FenceInfo()
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
        restyle(paragraphsIn: NSRange(location: 0, length: storage.length), storage: storage)
        pendingEditedRange = nil
        previousSelection = textView.selectedRange()
    }

    func handleEdit() {
        guard let storage = textView.textStorage else { return }
        let newFences = MarkdownParser.fences(in: storage.string)
        if newFences != fences {
            fences = newFences
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
        let old = ns.paragraphRange(for: clamp(previousSelection, to: ns.length))
        let new = ns.paragraphRange(for: clamp(selection, to: ns.length))
        restyle(paragraphsIn: old, storage: storage)
        if !NSEqualRanges(old, new) {
            restyle(paragraphsIn: new, storage: storage)
        }
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
        let target = ns.paragraphRange(for: clamp(range, to: ns.length))
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
        storage.setAttributes([.font: Self.baseFont, .foregroundColor: NSColor.textColor], range: paragraph)

        if fences.isContent(paragraph) {
            storage.addAttributes([.font: Self.codeFont, .backgroundColor: Self.codeBackground], range: paragraph)
            return
        }

        let line = ns.substring(with: paragraph)
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line

        switch MarkdownParser.blockKind(of: trimmed) {
        case .fenceDelimiter:
            storage.addAttributes([.font: Self.codeFont, .foregroundColor: NSColor.tertiaryLabelColor], range: paragraph)
            return
        case .horizontalRule:
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: paragraph)
            return
        case let .heading(level, marker):
            let font = NSFont.boldSystemFont(ofSize: Self.headingSizes[min(max(level, 1), 6) - 1])
            storage.addAttribute(.font, value: font, range: paragraph)
            applyMarker(
                storage,
                range: shifted(marker, by: paragraph.location),
                revealed: caretTouches(paragraph, selection: selection)
            )
        case let .blockquote(marker):
            let markerRange = shifted(marker, by: paragraph.location)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: markerRange)
            let rest = NSRange(location: NSMaxRange(markerRange), length: NSMaxRange(paragraph) - NSMaxRange(markerRange))
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: rest)
        case let .listItem(marker):
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: shifted(marker, by: paragraph.location))
        case let .taskListItem(marker, box, checked):
            let markerRange = shifted(marker, by: paragraph.location)
            let boxRange = shifted(box, by: paragraph.location)
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: markerRange)
            storage.addAttributes([.font: Self.codeFont, .foregroundColor: NSColor.controlAccentColor], range: boxRange)
            if checked {
                let rest = NSRange(location: NSMaxRange(boxRange), length: NSMaxRange(paragraph) - NSMaxRange(boxRange))
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor],
                    range: rest
                )
            }
        case .paragraph:
            break
        }

        for span in MarkdownParser.inlineSpans(in: trimmed) {
            applyInline(span, offset: paragraph.location, storage: storage, selection: selection)
        }
    }

    private func applyInline(_ span: InlineSpan, offset: Int, storage: NSTextStorage, selection: NSRange) {
        let content = shifted(span.content, by: offset)
        let whole = shifted(span.range, by: offset)
        let revealed = caretTouches(whole, selection: selection)

        switch span.kind {
        case .code:
            storage.addAttributes([.font: Self.codeFont, .backgroundColor: Self.codeBackground], range: content)
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
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: content)
            if !revealed, let parsed = URL(string: url) {
                storage.addAttribute(.link, value: parsed, range: content)
            }
        }

        applyMarker(storage, range: shifted(span.openMarker, by: offset), revealed: revealed)
        applyMarker(storage, range: shifted(span.closeMarker, by: offset), revealed: revealed)
    }

    private func addTrait(_ trait: NSFontTraitMask, range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? Self.baseFont
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }

    private func applyMarker(_ storage: NSTextStorage, range: NSRange, revealed: Bool) {
        if revealed {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        } else {
            storage.addAttributes(
                [.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.01)],
                range: range
            )
        }
    }

    private func caretTouches(_ range: NSRange, selection: NSRange) -> Bool {
        if revealAllMarkers { return true }
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
