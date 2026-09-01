import Foundation

struct InlineSpan: Equatable {
    enum Kind: Equatable {
        case bold, italic, boldItalic, strikethrough, code
        case link(url: String)
    }

    let kind: Kind
    let range: NSRange
    let openMarker: NSRange
    let content: NSRange
    let closeMarker: NSRange
}

enum BlockKind: Equatable {
    case heading(level: Int, marker: NSRange)
    case blockquote(marker: NSRange)
    case listItem(marker: NSRange)
    case taskListItem(marker: NSRange, box: NSRange, checked: Bool)
    case horizontalRule
    case fenceDelimiter
    case tableSeparator
    case paragraph
}

struct FenceBlock: Equatable {
    var range: NSRange
    var language: String
}

struct FenceInfo: Equatable {
    var delimiterLines: [NSRange] = []
    var blocks: [FenceBlock] = []

    func block(containing paragraph: NSRange) -> FenceBlock? {
        blocks.first { NSLocationInRange(paragraph.location, $0.range) }
    }
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
    private static let linkSpan = regex("(\\[)([^\\[\\]\\n]+)(\\]\\(([^()\\s]*)\\))")
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
        var occupied: [NSRange] = []

        func collect(_ regex: NSRegularExpression, _ kind: (NSTextCheckingResult) -> InlineSpan.Kind) {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                guard !occupied.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
                spans.append(InlineSpan(
                    kind: kind(match),
                    range: match.range,
                    openMarker: match.range(at: 1),
                    content: match.range(at: 2),
                    closeMarker: match.range(at: 3)
                ))
                occupied.append(match.range)
            }
        }

        collect(codeSpan) { _ in .code }
        collect(linkSpan) { .link(url: ns.substring(with: $0.range(at: 4))) }
        collect(boldItalicSpan) { _ in .boldItalic }
        collect(boldSpan) { _ in .bold }
        collect(italicSpan) { _ in .italic }
        collect(strikeSpan) { _ in .strikethrough }

        return spans.sorted { $0.range.location < $1.range.location }
    }

    static func fences(in text: String) -> FenceInfo {
        let ns = text as NSString
        var info = FenceInfo()
        var openContentStart: Int?
        var openLanguage = ""

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { _, lineRange, enclosingRange, _ in
            let line = ns.substring(with: lineRange)
            guard line.hasPrefix("```") || line.hasPrefix("~~~") else { return }
            info.delimiterLines.append(lineRange)
            if let start = openContentStart {
                info.blocks.append(FenceBlock(
                    range: NSRange(location: start, length: lineRange.location - start),
                    language: openLanguage
                ))
                openContentStart = nil
            } else {
                openContentStart = NSMaxRange(enclosingRange)
                openLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        if let start = openContentStart, start < ns.length {
            info.blocks.append(FenceBlock(
                range: NSRange(location: start, length: ns.length - start),
                language: openLanguage
            ))
        }
        return info
    }

    private static let imageLine = regex("^[ \\t]*!\\[[^\\]\\n]*\\]\\(([^()\\s]+)\\)[ \\t]*$")

    static func imageLinePath(in line: String) -> String? {
        let ns = line as NSString
        guard let m = imageLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
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
