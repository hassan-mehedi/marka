import Foundation

// Converts clipboard HTML from browsers and word processors into Markdown.
// The tokenizer is deliberately forgiving: real clipboard HTML is rarely
// well-formed XML.
enum HTMLToMarkdown {
    private enum Token {
        case open(name: String, attributes: [String: String], selfClosing: Bool)
        case close(name: String)
        case text(String)
    }

    private static let skipped: Set<String> = ["script", "style", "head", "title", "meta", "link"]
    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre",
        "table", "tr", "hr", "br", "section", "article", "header", "footer", "nav", "figure", "figcaption",
    ]

    static func markdown(from html: String) -> String {
        var converter = Converter()
        for token in tokenize(html) {
            converter.consume(token)
        }
        return converter.finish()
    }

    private struct Converter {
        private var output = ""
        private var listStack: [(ordered: Bool, index: Int)] = []
        private var blockquoteDepth = 0
        private var preDepth = 0
        private var skipDepth = 0
        private var linkHref: String?
        private var linkStart: String.Index?
        private var table: [[String]]? = nil
        private var tableRow: [String]? = nil
        private var tableCell: String? = nil
        private var tableHeaderRowCount = 0
        private var inHeaderCell = false
        private var pendingBlockBreak = false
        private var openMarkerEnd: String.Index?

        mutating func consume(_ token: Token) {
            switch token {
            case let .open(name, attributes, selfClosing):
                open(name, attributes)
                if selfClosing || name == "br" || name == "hr" || name == "img" { close(name) }
            case let .close(name):
                close(name)
            case let .text(text):
                write(text)
            }
        }

        mutating func finish() -> String {
            var result = output
            while result.hasSuffix("\n") { result.removeLast() }
            result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            return result.trimmingCharacters(in: .newlines)
        }

        private mutating func write(_ raw: String) {
            guard skipDepth == 0 else { return }
            if tableCell != nil {
                tableCell! += preDepth > 0 ? raw : collapse(raw)
                return
            }
            if preDepth > 0 {
                output += raw
                return
            }
            var text = collapse(raw)
            guard !text.isEmpty else { return }
            // "** bold**" is not bold in Markdown; move the space outside.
            if let end = openMarkerEnd, end == output.endIndex, text.hasPrefix(" "),
               let marker = ["**", "~~", "*"].first(where: { output.hasSuffix($0) }) {
                text = String(text.drop(while: { $0 == " " }))
                output.removeLast(marker.count)
                if !output.hasSuffix(" "), !output.isEmpty { output += " " }
                output += marker
            }
            openMarkerEnd = nil
            if pendingBlockBreak {
                startBlock()
            }
            if output.hasSuffix("\n") || output.isEmpty {
                output += linePrefix() + text.drop(while: { $0 == " " })
            } else {
                output += text
            }
        }

        private func collapse(_ text: String) -> String {
            text.replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
        }

        private func linePrefix() -> String {
            var prefix = String(repeating: "> ", count: blockquoteDepth)
            if !listStack.isEmpty {
                prefix += String(repeating: "  ", count: listStack.count)
            }
            return prefix
        }

        // Ends the current paragraph and leaves one blank line before the next block.
        private mutating func startBlock(blankLine: Bool = true) {
            pendingBlockBreak = false
            guard !output.isEmpty else { return }
            if !output.hasSuffix("\n") { output += "\n" }
            if blankLine, !output.hasSuffix("\n\n") {
                output += blockquoteDepth > 0 ? String(repeating: "> ", count: blockquoteDepth).trimmingCharacters(in: .whitespaces) + "\n" : "\n"
            }
        }

        private mutating func open(_ name: String, _ attributes: [String: String]) {
            if skipped.contains(name) { skipDepth += 1; return }
            guard skipDepth == 0 else { return }
            // A cell without its closing tag ends when the next cell or row starts.
            if tableCell != nil, ["th", "td", "tr", "table"].contains(name) {
                close("td")
            }
            if tableCell != nil {
                switch name {
                case "br": tableCell! += " "
                case "strong", "b": tableCell! += "**"
                case "em", "i": tableCell! += "*"
                case "code": tableCell! += "`"
                case "del", "s", "strike": tableCell! += "~~"
                case "a": linkHref = attributes["href"]; tableCell! += "["
                default: break
                }
                return
            }
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                startBlock()
                output += linePrefix() + String(repeating: "#", count: Int(String(name.last!))!) + " "
            case "p", "div", "section", "article", "header", "footer", "nav", "figure", "figcaption":
                startBlock(blankLine: name != "div" || output.hasSuffix("\n"))
            case "br":
                output += "  \n" + linePrefix()
            case "hr":
                startBlock()
                output += "---\n\n"
            case "strong", "b":
                output += "**"
                openMarkerEnd = output.endIndex
            case "em", "i":
                output += "*"
                openMarkerEnd = output.endIndex
            case "del", "s", "strike":
                output += "~~"
                openMarkerEnd = output.endIndex
            case "code":
                if preDepth == 0 {
                    output += "`"
                } else if output.hasSuffix("```\n"), let language = Self.language(in: attributes) {
                    output.removeLast()
                    output += language + "\n"
                }
            case "pre":
                startBlock()
                output += "```" + (Self.language(in: attributes) ?? "") + "\n"
                preDepth += 1
            case "a":
                linkHref = attributes["href"]
                linkStart = output.endIndex
                output += "["
            case "img":
                let alt = attributes["alt"] ?? ""
                output += "![\(alt)](\(attributes["src"] ?? ""))"
            case "ul", "ol":
                if listStack.isEmpty { startBlock() } else if !output.hasSuffix("\n") { output += "\n" }
                listStack.append((name == "ol", Int(attributes["start"] ?? "") ?? 1))
            case "li":
                if !output.hasSuffix("\n"), !output.isEmpty { output += "\n" }
                guard let list = listStack.last else { output += "- "; return }
                let indent = String(repeating: "  ", count: listStack.count - 1)
                let marker = list.ordered ? "\(list.index). " : "- "
                listStack[listStack.count - 1].index += 1
                output += String(repeating: "> ", count: blockquoteDepth) + indent + marker
            case "blockquote":
                startBlock()
                blockquoteDepth += 1
            case "table":
                startBlock()
                table = []
                tableHeaderRowCount = 0
            case "tr":
                tableRow = []
            case "th", "td":
                inHeaderCell = name == "th"
                tableCell = ""
            default:
                break
            }
        }

        private mutating func close(_ name: String) {
            if skipped.contains(name) { skipDepth = max(skipDepth - 1, 0); return }
            guard skipDepth == 0 else { return }
            if tableCell != nil, name == "tr" || name == "table" {
                close("td")
            }
            if tableCell != nil, name != "th", name != "td" {
                switch name {
                case "strong", "b": tableCell! += "**"
                case "em", "i": tableCell! += "*"
                case "code": tableCell! += "`"
                case "del", "s", "strike": tableCell! += "~~"
                case "a": tableCell! += "](\(linkHref ?? ""))"; linkHref = nil
                default: break
                }
                return
            }
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6", "p", "div", "section", "article", "header", "footer", "nav", "figure", "figcaption":
                pendingBlockBreak = true
                if name != "div" { startBlock() } else if !output.hasSuffix("\n") { output += "\n" }
            case "strong", "b":
                trimTrailingSpaceInsideMarker("**")
            case "em", "i":
                trimTrailingSpaceInsideMarker("*")
            case "del", "s", "strike":
                trimTrailingSpaceInsideMarker("~~")
            case "code":
                if preDepth == 0 { output += "`" }
            case "pre":
                preDepth = max(preDepth - 1, 0)
                if !output.hasSuffix("\n") { output += "\n" }
                output += "```\n\n"
            case "a":
                if let start = linkStart, let href = linkHref, output[output.index(after: start)...] == href {
                    output.removeSubrange(start...)
                    output += href
                } else {
                    output += "](\(linkHref ?? ""))"
                }
                linkHref = nil
                linkStart = nil
            case "ul", "ol":
                _ = listStack.popLast()
                if listStack.isEmpty { output += output.hasSuffix("\n") ? "\n" : "\n\n" }
            case "li":
                if !output.hasSuffix("\n") { output += "\n" }
            case "blockquote":
                blockquoteDepth = max(blockquoteDepth - 1, 0)
                if !output.hasSuffix("\n") { output += "\n" }
                let emptyQuoteLine = String(repeating: "> ", count: blockquoteDepth).trimmingCharacters(in: .whitespaces) + ">\n"
                while output.hasSuffix(emptyQuoteLine) { output.removeLast(emptyQuoteLine.count) }
                output += "\n"
            case "th", "td":
                var cell = tableCell ?? ""
                cell = cell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: "\\|")
                tableRow?.append(cell)
                tableCell = nil
            case "tr":
                if let row = tableRow {
                    table?.append(row)
                    if inHeaderCell, table?.count == 1 { tableHeaderRowCount = 1 }
                }
                tableRow = nil
                inHeaderCell = false
            case "table":
                if let rows = table, let first = rows.first {
                    let columns = rows.map(\.count).max() ?? first.count
                    let padded = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
                    let body = TableEditor(rows: padded, alignments: Array(repeating: .left, count: columns))
                    output += body.formatted() + "\n\n"
                }
                table = nil
            default:
                break
            }
        }

        private static func language(in attributes: [String: String]) -> String? {
            (attributes["class"] ?? "")
                .split(separator: " ")
                .first { $0.hasPrefix("language-") || $0.hasPrefix("lang-") }
                .map { String($0.split(separator: "-", maxSplits: 1).last ?? "") }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        // "**bold **" is not bold in Markdown; move the space outside.
        private mutating func trimTrailingSpaceInsideMarker(_ marker: String) {
            var spaces = ""
            while output.hasSuffix(" ") {
                output.removeLast()
                spaces += " "
            }
            if output.hasSuffix(marker) {
                output.removeLast(marker.count)
                output += spaces
                return
            }
            output += marker + spaces
        }
    }

    private static func tokenize(_ html: String) -> [Token] {
        var tokens: [Token] = []
        var index = html.startIndex
        var text = ""

        func flushText() {
            if !text.isEmpty {
                tokens.append(.text(decodeEntities(text)))
                text = ""
            }
        }

        while index < html.endIndex {
            let character = html[index]
            if character == "<" {
                if html[index...].hasPrefix("<!--") {
                    flushText()
                    if let end = html.range(of: "-->", range: index..<html.endIndex) {
                        index = end.upperBound
                    } else {
                        index = html.endIndex
                    }
                    continue
                }
                if let end = html[index...].firstIndex(of: ">") {
                    let inner = String(html[html.index(after: index)..<end])
                    if inner.hasPrefix("!") || inner.hasPrefix("?") {
                        flushText()
                        index = html.index(after: end)
                        continue
                    }
                    if inner.hasPrefix("/") {
                        flushText()
                        let name = inner.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
                        tokens.append(.close(name: name))
                        index = html.index(after: end)
                        continue
                    }
                    flushText()
                    let selfClosing = inner.hasSuffix("/")
                    let body = selfClosing ? String(inner.dropLast()) : inner
                    let (name, attributes) = parseTag(body)
                    tokens.append(.open(name: name, attributes: attributes, selfClosing: selfClosing))
                    index = html.index(after: end)
                    if name == "script" || name == "style" {
                        if let closeRange = html.range(of: "</\(name)", options: .caseInsensitive, range: index..<html.endIndex) {
                            index = closeRange.lowerBound
                        } else {
                            index = html.endIndex
                        }
                    }
                    continue
                }
            }
            text.append(character)
            index = html.index(after: index)
        }
        flushText()
        return tokens
    }

    private static func parseTag(_ body: String) -> (String, [String: String]) {
        let scanner = Scanner(string: body)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        guard let name = scanner.scanCharacters(from: CharacterSet.alphanumerics.union(.init(charactersIn: "-:"))) else {
            return (body.lowercased(), [:])
        }
        var attributes: [String: String] = [:]
        while !scanner.isAtEnd {
            guard let key = scanner.scanCharacters(from: CharacterSet.alphanumerics.union(.init(charactersIn: "-:_"))) else {
                _ = scanner.scanCharacter()
                continue
            }
            var value = ""
            if scanner.scanString("=") != nil {
                if scanner.scanString("\"") != nil {
                    value = scanner.scanUpToString("\"") ?? ""
                    _ = scanner.scanString("\"")
                } else if scanner.scanString("'") != nil {
                    value = scanner.scanUpToString("'") ?? ""
                    _ = scanner.scanString("'")
                } else {
                    value = scanner.scanUpToCharacters(from: .whitespacesAndNewlines) ?? ""
                }
            }
            attributes[key.lowercased()] = decodeEntities(value)
        }
        return (name.lowercased(), attributes)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "copy": "\u{00A9}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[amp...]
            guard let semicolon = after.firstIndex(of: ";"), after.distance(from: amp, to: semicolon) <= 10 else {
                result += "&"
                rest = after.dropFirst()
                continue
            }
            let entity = String(after[after.index(after: amp)..<semicolon])
            if entity.hasPrefix("#x") || entity.hasPrefix("#X"), let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(code) {
                result.append(Character(scalar))
            } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = UnicodeScalar(code) {
                result.append(Character(scalar))
            } else if let named = namedEntities[entity] {
                result += named
            } else {
                result += "&" + entity + ";"
            }
            rest = after[after.index(after: semicolon)...]
        }
        result += rest
        return result.replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
