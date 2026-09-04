import Foundation

struct InlineSpan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case bold, italic, boldItalic, strikethrough, code
        case link(url: String)
        case image(src: String)
    }

    let kind: Kind
    let range: NSRange
    let openMarker: NSRange
    let content: NSRange
    let closeMarker: NSRange
}

enum BlockKind: Equatable, Sendable {
    case heading(level: Int, marker: NSRange)
    case blockquote(marker: NSRange)
    case listItem(marker: NSRange)
    case taskListItem(marker: NSRange, box: NSRange, checked: Bool)
    case horizontalRule
    case fenceDelimiter
    case tableSeparator
    case paragraph
}

struct MathSpan: Equatable, Sendable {
    let range: NSRange
    let content: NSRange
}

struct FenceBlock: Equatable, Sendable {
    var range: NSRange
    var language: String
    var openDelimiter: NSRange
    var closeDelimiter: NSRange?

    var fullRange: NSRange {
        var union = NSUnionRange(openDelimiter, range)
        if let closeDelimiter {
            union = NSUnionRange(union, closeDelimiter)
        }
        return union
    }
}

struct FenceInfo: Equatable, Sendable {
    var delimiterLines: [NSRange] = []
    var blocks: [FenceBlock] = []

    func block(containing paragraph: NSRange) -> FenceBlock? {
        blocks.first { NSLocationInRange(paragraph.location, $0.range) }
    }
}

struct MathBlock: Equatable, Sendable {
    var range: NSRange
    var openDelimiter: NSRange
    var closeDelimiter: NSRange?

    var fullRange: NSRange {
        var union = NSUnionRange(openDelimiter, range)
        if let closeDelimiter {
            union = NSUnionRange(union, closeDelimiter)
        }
        return union
    }
}

struct TableBlock: Equatable, Sendable {
    enum Alignment: Equatable, Sendable {
        case left, center, right
    }

    var fullRange: NSRange
    var rows: [[String]]
    var alignments: [Alignment]
}

// Everything the editor needs to know about one line, computed once and
// shared by the highlighter, the display layer and the caret remap.
struct LineInfo: Sendable {
    let blockKind: BlockKind
    let inlineSpans: [InlineSpan]
    let inlineMath: [MathSpan]
    let displayMath: String?
    let footnoteDefinition: NSRange?
    let footnoteReferences: [(range: NSRange, label: String)]
    let pipes: [NSRange]
    let isTOC: Bool
    let imagePath: String?

    // Source ranges that render with a different length: markers vanish,
    // an inline math span becomes a single attachment character.
    func displayReplacements(
        markersHidden: Bool = true,
        mathCollapses: (MathSpan) -> Bool = { _ in true }
    ) -> [(range: NSRange, displayLength: Int)] {
        var replacements: [(NSRange, Int)] = []
        if markersHidden {
            if case let .heading(_, marker) = blockKind {
                replacements.append((marker, 0))
            }
            for span in inlineSpans {
                replacements.append((span.openMarker, 0))
                replacements.append((span.closeMarker, 0))
            }
        }
        replacements += inlineMath.filter(mathCollapses).map { ($0.range, 1) }
        replacements.sort { $0.0.location < $1.0.location }

        var result: [(NSRange, Int)] = []
        for replacement in replacements {
            if let last = result.last, NSMaxRange(last.0) > replacement.0.location { continue }
            result.append(replacement)
        }
        return result
    }

    init(line: String) {
        blockKind = MarkdownParser.blockKind(of: line)
        pipes = MarkdownParser.pipeRanges(in: line)
        switch blockKind {
        case .fenceDelimiter, .horizontalRule, .tableSeparator:
            inlineSpans = []
            inlineMath = []
            displayMath = nil
            footnoteDefinition = nil
            footnoteReferences = []
            isTOC = false
            imagePath = nil
        default:
            inlineSpans = MarkdownParser.inlineSpans(in: line)
            displayMath = MarkdownParser.displayMathContent(in: line)
            inlineMath = displayMath == nil ? MarkdownParser.inlineMathSpans(in: line) : []
            footnoteDefinition = MarkdownParser.footnoteDefinitionMarker(in: line)?.marker
            footnoteReferences = footnoteDefinition == nil ? MarkdownParser.footnoteReferences(in: line) : []
            isTOC = MarkdownParser.isTOCLine(line)
            imagePath = MarkdownParser.imageLinePath(in: line)
        }
    }
}

// Two-generation cache of LineInfo keyed by the line text. When the young
// generation fills up it becomes the old one, so lines still in use survive
// while lines that were edited away fall out after one more turnover.
enum LineCache {
    private static let capacity = 4000
    private static let lock = NSLock()
    nonisolated(unsafe) private static var young: [String: LineInfo] = [:]
    nonisolated(unsafe) private static var old: [String: LineInfo] = [:]

    static func info(for line: String) -> LineInfo {
        lock.lock()
        if let hit = young[line] {
            lock.unlock()
            return hit
        }
        if let hit = old[line] {
            store(line, hit)
            lock.unlock()
            return hit
        }
        lock.unlock()
        let info = LineInfo(line: line)
        lock.lock()
        store(line, info)
        lock.unlock()
        return info
    }

    private static func store(_ line: String, _ info: LineInfo) {
        if young.count >= capacity {
            old = young
            young = [:]
        }
        young[line] = info
    }
}

// Block-level layout of a document: fences, math blocks, tables and front
// matter, found in one pass over the lines.
struct BlockStructure: Equatable, Sendable {
    var fences = FenceInfo()
    var mathBlocks: [MathBlock] = []
    var tables: [TableBlock] = []
    var frontMatter: NSRange?
}

enum MarkdownParser {
    private static let heading = regex("^(#{1,6})[ \\t]+")
    private static let blockquote = regex("^((?:>[ \\t]?)+)")
    private static let listItem = regex("^[ \\t]{0,8}(?:[-*+]|\\d{1,9}[.)])[ \\t]+")
    private static let taskItem = regex("^([ \\t]{0,8}[-*+][ \\t]+)(\\[[ xX]\\])(?=[ \\t]|$)")
    private static let orderedMarker = regex("^([ \\t]*)(\\d{1,9})([.)][ \\t]+)$")
    private static let horizontalRule = regex("^[ \\t]*(?:-{3,}|_{3,}|\\*{3,})[ \\t]*$")
    private static let tableSeparatorRow = regex("^[ \\t]*\\|?[ \\t]*:?-+:?[ \\t]*(?:\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*$")

    private static let codeSpan = regex("(`+)([^`\\n]+?)(\\1)")
    private static let linkSpan = regex("(?<!!)(\\[)([^\\[\\]\\n]+)(\\]\\(([^()\\s]*)\\))")
    private static let imageSpan = regex("(!\\[)([^\\[\\]\\n]*)(\\]\\(([^()\\s]+)\\))")
    private static let boldItalicSpan = regex("(\\*\\*\\*)(?=\\S)([^*\\n]+?)(?<=\\S)(\\*\\*\\*)")
    private static let boldSpan = regex("(\\*\\*)(?=\\S)([^\\n]+?)(?<=\\S)(\\*\\*)")
    private static let italicSpan = regex("(?<![*\\\\])(\\*)(?![*\\s])([^*\\n]+?)(?<![\\s*])(\\*)(?!\\*)")
    private static let strikeSpan = regex("(~~)(?=\\S)([^\\n]+?)(?<=\\S)(~~)")

    static func blockKind(of line: String) -> BlockKind {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            return .fenceDelimiter
        }
        if horizontalRule.firstMatch(in: line, range: full) != nil {
            return .horizontalRule
        }
        if line.contains("|"), tableSeparatorRow.firstMatch(in: line, range: full) != nil {
            return .tableSeparator
        }
        if let m = heading.firstMatch(in: line, range: full) {
            return .heading(level: m.range(at: 1).length, marker: m.range)
        }
        if let m = blockquote.firstMatch(in: line, range: full) {
            return .blockquote(marker: m.range(at: 1))
        }
        if let m = taskItem.firstMatch(in: line, range: full) {
            let box = m.range(at: 2)
            let checked = ns.substring(with: box).lowercased().contains("x")
            return .taskListItem(marker: m.range(at: 1), box: box, checked: checked)
        }
        if let m = listItem.firstMatch(in: line, range: full) {
            return .listItem(marker: m.range)
        }
        return .paragraph
    }

    static func inlineSpans(in text: String) -> [InlineSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [InlineSpan] = []

        // Spans may nest inside one another, so `**bold `code`**` styles both.
        // A span that only partly overlaps an earlier one, or that sits inside
        // a code span, is not a span.
        func collect(_ regex: NSRegularExpression, _ kind: (NSTextCheckingResult) -> InlineSpan.Kind) {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                for span in spans where NSIntersectionRange(span.range, match.range).length > 0 {
                    let insideExisting = contains(span.content, match.range)
                    let wrapsExisting = contains(match.range(at: 2), span.range)
                    guard wrapsExisting || insideExisting && span.kind != .code else { return }
                }
                spans.append(InlineSpan(
                    kind: kind(match),
                    range: match.range,
                    openMarker: match.range(at: 1),
                    content: match.range(at: 2),
                    closeMarker: match.range(at: 3)
                ))
            }
        }

        collect(codeSpan) { _ in .code }
        collect(imageSpan) { .image(src: ns.substring(with: $0.range(at: 4))) }
        collect(linkSpan) { .link(url: ns.substring(with: $0.range(at: 4))) }
        collect(boldItalicSpan) { _ in .boldItalic }
        collect(boldSpan) { _ in .bold }
        collect(italicSpan) { _ in .italic }
        collect(strikeSpan) { _ in .strikethrough }

        return spans.sorted {
            $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length
        }
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    static func mathBlocks(in text: String, excluding fences: FenceInfo) -> [MathBlock] {
        let ns = text as NSString
        var blocks: [MathBlock] = []
        var openContentStart: Int?
        var openDelimiter = NSRange(location: 0, length: 0)

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { _, lineRange, enclosingRange, _ in
            guard ns.substring(with: lineRange).trimmingCharacters(in: .whitespaces) == "$$" else { return }
            guard !fences.blocks.contains(where: { NSLocationInRange(lineRange.location, $0.fullRange) }) else { return }
            if let start = openContentStart {
                blocks.append(MathBlock(
                    range: NSRange(location: start, length: lineRange.location - start),
                    openDelimiter: openDelimiter,
                    closeDelimiter: lineRange
                ))
                openContentStart = nil
            } else {
                openContentStart = NSMaxRange(enclosingRange)
                openDelimiter = lineRange
            }
        }
        if let start = openContentStart, start < ns.length {
            blocks.append(MathBlock(
                range: NSRange(location: start, length: ns.length - start),
                openDelimiter: openDelimiter,
                closeDelimiter: nil
            ))
        }
        return blocks
    }

    // The run of backticks or tildes that opens a fence, or nil for other lines.
    static func fenceMarker(of line: String) -> (character: Character, length: Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let length = line.prefix { $0 == first }.count
        return length >= 3 ? (first, length) : nil
    }

    // A closing fence repeats the opener's character at least as many times
    // and carries nothing else; a shorter or different run is content.
    private static func closesFence(_ line: String, opener: (character: Character, length: Int)) -> Bool {
        guard let marker = fenceMarker(of: line), marker.character == opener.character, marker.length >= opener.length else {
            return false
        }
        return line.dropFirst(marker.length).allSatisfy { $0 == " " || $0 == "\t" }
    }


    static func structure(in text: String) -> BlockStructure {
        let ns = text as NSString
        var result = BlockStructure()

        var fenceContentStart: Int?
        var fenceLanguage = ""
        var fenceDelimiter = NSRange(location: 0, length: 0)
        var opener: (character: Character, length: Int) = ("`", 3)

        var mathContentStart: Int?
        var mathDelimiter = NSRange(location: 0, length: 0)

        var frontMatterOpen = false
        var frontMatterDecided = false

        var previous: (text: String, range: NSRange, inFence: Bool)?
        var tableStart: NSRange?
        var tableRows: [[String]] = []
        var tableAlignments: [TableBlock.Alignment] = []
        var tableEnd = NSRange(location: 0, length: 0)

        func closeTable() {
            guard let start = tableStart else { return }
            tableStart = nil
            let columns = tableRows.map(\.count).max() ?? 0
            guard columns > 0 else { return }
            result.tables.append(TableBlock(
                fullRange: NSUnionRange(start, tableEnd),
                rows: tableRows.map { row in row + Array(repeating: "", count: columns - row.count) },
                alignments: Array((tableAlignments + Array(repeating: .left, count: columns)).prefix(columns))
            ))
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { substring, lineRange, enclosingRange, _ in
            let line = substring ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !frontMatterDecided {
                if frontMatterOpen {
                    if trimmed == "---" || trimmed == "..." {
                        result.frontMatter = NSRange(location: 0, length: NSMaxRange(lineRange))
                        frontMatterDecided = true
                    }
                } else if lineRange.location == 0, trimmed == "---" {
                    frontMatterOpen = true
                } else {
                    frontMatterDecided = true
                }
            }

            var inFence = false
            if let start = fenceContentStart {
                inFence = true
                if closesFence(line, opener: opener) {
                    result.fences.delimiterLines.append(lineRange)
                    result.fences.blocks.append(FenceBlock(
                        range: NSRange(location: start, length: lineRange.location - start),
                        language: fenceLanguage,
                        openDelimiter: fenceDelimiter,
                        closeDelimiter: lineRange
                    ))
                    fenceContentStart = nil
                }
            } else if let marker = fenceMarker(of: line) {
                inFence = true
                result.fences.delimiterLines.append(lineRange)
                opener = marker
                fenceContentStart = NSMaxRange(enclosingRange)
                fenceLanguage = String(line.dropFirst(marker.length)).trimmingCharacters(in: .whitespaces)
                fenceDelimiter = lineRange
            }

            if !inFence, trimmed == "$$" {
                if let start = mathContentStart {
                    result.mathBlocks.append(MathBlock(
                        range: NSRange(location: start, length: lineRange.location - start),
                        openDelimiter: mathDelimiter,
                        closeDelimiter: lineRange
                    ))
                    mathContentStart = nil
                } else {
                    mathContentStart = NSMaxRange(enclosingRange)
                    mathDelimiter = lineRange
                }
            }

            let hasPipes = !pipeRanges(in: line).isEmpty
            if tableStart != nil {
                if hasPipes, blockKind(of: line) == .paragraph {
                    tableRows.append(tableCells(in: line))
                    tableEnd = lineRange
                    previous = (line, lineRange, inFence)
                    return
                }
                closeTable()
            }
            if let header = previous, !header.inFence, hasPipes, !pipeRanges(in: header.text).isEmpty,
               blockKind(of: line) == .tableSeparator {
                tableStart = header.range
                tableEnd = lineRange
                tableRows = [tableCells(in: header.text)]
                tableAlignments = tableCells(in: line).map { cell in
                    switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                    case (true, true): .center
                    case (false, true): .right
                    default: .left
                    }
                }
            }
            previous = (line, lineRange, inFence)
        }

        closeTable()
        if let start = fenceContentStart, start < ns.length {
            result.fences.blocks.append(FenceBlock(
                range: NSRange(location: start, length: ns.length - start),
                language: fenceLanguage,
                openDelimiter: fenceDelimiter,
                closeDelimiter: nil
            ))
        }
        if let start = mathContentStart, start < ns.length {
            result.mathBlocks.append(MathBlock(
                range: NSRange(location: start, length: ns.length - start),
                openDelimiter: mathDelimiter,
                closeDelimiter: nil
            ))
        }
        return result
    }

    static func fences(in text: String) -> FenceInfo {
        let ns = text as NSString
        var info = FenceInfo()
        var openContentStart: Int?
        var openLanguage = ""
        var openDelimiter = NSRange(location: 0, length: 0)
        var opener: (character: Character, length: Int) = ("`", 3)

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { _, lineRange, enclosingRange, _ in
            let line = ns.substring(with: lineRange)
            if let start = openContentStart {
                guard closesFence(line, opener: opener) else { return }
                info.delimiterLines.append(lineRange)
                info.blocks.append(FenceBlock(
                    range: NSRange(location: start, length: lineRange.location - start),
                    language: openLanguage,
                    openDelimiter: openDelimiter,
                    closeDelimiter: lineRange
                ))
                openContentStart = nil
            } else if let marker = fenceMarker(of: line) {
                info.delimiterLines.append(lineRange)
                opener = marker
                openContentStart = NSMaxRange(enclosingRange)
                openLanguage = String(line.dropFirst(marker.length)).trimmingCharacters(in: .whitespaces)
                openDelimiter = lineRange
            }
        }
        if let start = openContentStart, start < ns.length {
            info.blocks.append(FenceBlock(
                range: NSRange(location: start, length: ns.length - start),
                language: openLanguage,
                openDelimiter: openDelimiter,
                closeDelimiter: nil
            ))
        }
        return info
    }

    private static let imageLine = regex("^[ \\t]*!\\[[^\\]\\n]*\\]\\(([^()\\s]+)\\)[ \\t]*$")
    private static let displayMathLine = regex("^[ \\t]*\\$\\$[ \\t]*(.*\\S)[ \\t]*\\$\\$[ \\t]*$")
    private static let inlineMath = regex("(?<![\\\\$])(\\$)(?![\\s$])((?:[^$\\\\\\n]|\\\\.)+?)(?<![\\s\\\\])(\\$)(?![\\d$])")

    static func displayMathContent(in line: String) -> String? {
        let ns = line as NSString
        guard let m = displayMathLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func inlineMathSpans(in line: String) -> [MathSpan] {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard displayMathContent(in: line) == nil else { return [] }

        // Math inside a code span is literal text, not a formula.
        var protected: [NSRange] = []
        codeSpan.enumerateMatches(in: line, range: full) { match, _, _ in
            if let match { protected.append(match.range) }
        }

        var spans: [MathSpan] = []
        inlineMath.enumerateMatches(in: line, range: full) { match, _, _ in
            guard let match else { return }
            guard !protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
            spans.append(MathSpan(range: match.range, content: match.range(at: 2)))
        }
        return spans
    }

    static func imageLinePath(in line: String) -> String? {
        let ns = line as NSString
        guard let m = imageLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static let footnoteDefinition = regex("^\\[\\^([^\\]\\s]+)\\]:[ \\t]*")
    private static let footnoteReference = regex("\\[\\^([^\\]\\s]+)\\](?!:)")

    static func footnoteDefinitionMarker(in line: String) -> (marker: NSRange, label: String)? {
        let ns = line as NSString
        guard let match = footnoteDefinition.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (match.range, ns.substring(with: match.range(at: 1)))
    }

    static func footnoteReferences(in line: String) -> [(range: NSRange, label: String)] {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard footnoteDefinitionMarker(in: line) == nil else { return [] }

        var protected: [NSRange] = []
        codeSpan.enumerateMatches(in: line, range: full) { match, _, _ in
            if let match { protected.append(match.range) }
        }

        var refs: [(NSRange, String)] = []
        footnoteReference.enumerateMatches(in: line, range: full) { match, _, _ in
            guard let match else { return }
            guard !protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
            refs.append((match.range, ns.substring(with: match.range(at: 1))))
        }
        return refs
    }

    static func isTOCLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).lowercased() == "[toc]"
    }

    static func frontMatterRange(in text: String) -> NSRange? {
        let ns = text as NSString
        var sawOpener = false
        var result: NSRange?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, _, stop in
            let trimmed = line?.trimmingCharacters(in: .whitespaces) ?? ""
            if !sawOpener {
                guard lineRange.location == 0, trimmed == "---" else {
                    stop.pointee = true
                    return
                }
                sawOpener = true
                return
            }
            if trimmed == "---" || trimmed == "..." {
                result = NSRange(location: 0, length: NSMaxRange(lineRange))
                stop.pointee = true
            }
        }
        return result
    }

    static func outline(in text: String) -> [OutlineItem] {
        let excluded = fences(in: text).blocks.map(\.fullRange) + [frontMatterRange(in: text)].compactMap { $0 }
        return outline(in: text, excluding: excluded)
    }

    static func outline(in text: String, excluding excluded: [NSRange]) -> [OutlineItem] {
        let ns = text as NSString
        var items: [OutlineItem] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, _, _ in
            guard let line, line.hasPrefix("#"), case let .heading(level, marker) = blockKind(of: line) else { return }
            guard !excluded.contains(where: { NSLocationInRange(lineRange.location, $0) }) else { return }
            let title = (line as NSString).substring(from: NSMaxRange(marker)).trimmingCharacters(in: .whitespaces)
            items.append(OutlineItem(level: level, title: title, location: lineRange.location))
        }
        return items
    }

    // Offsets of the pipes that separate cells, with -1 and the line length
    // standing in for a missing leading or trailing pipe. An escaped pipe
    // is cell content, so `| a | b\|` still ends in an open cell.
    static func tableBoundaries(in line: String) -> [Int] {
        let ns = line as NSString
        var boundaries = pipeRanges(in: line).map(\.location)
        let leadingPipe = boundaries.first.map { ns.substring(to: $0).trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        let trailingPipe = boundaries.last.map { ns.substring(from: $0 + 1).trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        if !leadingPipe { boundaries.insert(-1, at: 0) }
        if !trailingPipe { boundaries.append(ns.length) }
        return boundaries
    }

    static func tableCells(in line: String) -> [String] {
        let ns = line as NSString
        let boundaries = tableBoundaries(in: line)
        return zip(boundaries, boundaries.dropFirst()).map { start, end in
            ns.substring(with: NSRange(location: start + 1, length: end - start - 1)).trimmingCharacters(in: .whitespaces)
        }
    }

    static func tables(in text: String, excluding fences: FenceInfo) -> [TableBlock] {
        let ns = text as NSString
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, _, _ in
            lines.append((line ?? "", lineRange))
        }

        var tables: [TableBlock] = []
        var index = 0
        while index + 1 < lines.count {
            let header = lines[index]
            guard !pipeRanges(in: header.text).isEmpty,
                  blockKind(of: lines[index + 1].text) == .tableSeparator,
                  !fences.blocks.contains(where: { NSLocationInRange(header.range.location, $0.fullRange) })
            else {
                index += 1
                continue
            }

            let headerCells = tableCells(in: header.text)
            let alignments = tableCells(in: lines[index + 1].text).map { cell -> TableBlock.Alignment in
                switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                case (true, true): .center
                case (false, true): .right
                default: .left
                }
            }
            var rows = [headerCells]
            var last = index + 1
            var next = index + 2
            while next < lines.count, !pipeRanges(in: lines[next].text).isEmpty,
                  blockKind(of: lines[next].text) == .paragraph {
                rows.append(tableCells(in: lines[next].text))
                last = next
                next += 1
            }
            // Every cell survives, so a rewrite of the table never drops one
            // that sits beyond the header's width.
            let columns = rows.map(\.count).max() ?? 0
            guard columns > 0 else {
                index = next
                continue
            }
            tables.append(TableBlock(
                fullRange: NSUnionRange(header.range, lines[last].range),
                rows: rows.map { row in row + Array(repeating: "", count: columns - row.count) },
                alignments: Array((alignments + Array(repeating: .left, count: columns)).prefix(columns))
            ))
            index = next
        }
        return tables
    }

    static func pipeRanges(in line: String) -> [NSRange] {
        let ns = line as NSString
        var pipes: [NSRange] = []
        var index = 0
        while index < ns.length {
            let character = ns.character(at: index)
            if character == 0x5C { // backslash escapes the next character
                index += 2
                continue
            }
            if character == 0x7C { // |
                pipes.append(NSRange(location: index, length: 1))
            }
            index += 1
        }
        return pipes
    }

    static func continuationMarker(afterLine line: String) -> String? {
        let ns = line as NSString
        switch blockKind(of: line) {
        case let .taskListItem(marker, _, _):
            return ns.substring(with: marker) + "[ ] "
        case let .listItem(marker):
            let text = ns.substring(with: marker)
            let markerNS = text as NSString
            guard let m = orderedMarker.firstMatch(in: text, range: NSRange(location: 0, length: markerNS.length)),
                  let number = Int(markerNS.substring(with: m.range(at: 2)))
            else { return text }
            return markerNS.substring(with: m.range(at: 1)) + String(number + 1) + markerNS.substring(with: m.range(at: 3))
        default:
            return nil
        }
    }

    static func isEmptyListItem(_ line: String) -> Bool {
        let ns = line as NSString
        let contentStart: Int
        switch blockKind(of: line) {
        case let .taskListItem(_, box, _):
            contentStart = NSMaxRange(box)
        case let .listItem(marker):
            contentStart = NSMaxRange(marker)
        default:
            return false
        }
        let rest = ns.substring(from: contentStart)
        return rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}
