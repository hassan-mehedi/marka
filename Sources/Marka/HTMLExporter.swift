import Foundation

enum HTMLExporter {
    static func document(from markdown: String, title: String) -> String {
        let body = fragment(from: markdown)
        let needsMath = body.contains("class=\"math\"") || body.contains("\\(")
        let needsMermaid = body.contains("class=\"mermaid\"")
        var head = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>
        body { max-width: 44em; margin: 2em auto; padding: 0 1em; font: 16px/1.6 -apple-system, sans-serif; }
        code { font: 14px ui-monospace, monospace; background: rgba(128, 128, 128, 0.15); padding: 1px 4px; border-radius: 3px; }
        pre { background: rgba(128, 128, 128, 0.12); padding: 12px; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { color: #666; border-left: 3px solid #ccc; margin-left: 0; padding-left: 1em; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #ccc; padding: 4px 10px; }
        img { max-width: 100%; }
        </style>
        """
        if needsMath {
            head += "\n<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-chtml.js\" async></script>"
        }
        if needsMermaid {
            head += """

            <script type="module">
            import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
            mermaid.initialize({ startOnLoad: true });
            </script>
            """
        }
        return head + "\n</head>\n<body>\n" + body + "</body>\n</html>\n"
    }

    private final class FootnoteContext {
        var numbers: [String: Int] = [:]
        var order: [String] = []

        func number(for label: String) -> Int {
            if let number = numbers[label] { return number }
            let number = numbers.count + 1
            numbers[label] = number
            order.append(label)
            return number
        }
    }

    static func fragment(from markdown: String) -> String {
        let ns = markdown as NSString
        let fences = MarkdownParser.fences(in: markdown)
        let mathBlocks = MarkdownParser.mathBlocks(in: markdown, excluding: fences)
        let outline = MarkdownParser.outline(in: markdown)
        var slugs: [Int: String] = [:]
        var usedSlugs: [String: Int] = [:]
        for item in outline {
            let base = slugify(item.title)
            let count = usedSlugs[base, default: 0]
            usedSlugs[base] = count + 1
            slugs[item.location] = count == 0 ? base : "\(base)-\(count + 1)"
        }
        var lines: [String] = []
        var lineStarts: [Int] = []
        var location = 0
        while location < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: range)
            if line.hasSuffix("\n") { line.removeLast() }
            lines.append(line)
            lineStarts.append(range.location)
            location = NSMaxRange(range)
        }

        var html = ""
        var index = 0
        let footnotes = FootnoteContext()
        var definitions: [String: String] = [:]
        var definitionOrder: [String] = []

        if let frontMatter = MarkdownParser.frontMatterRange(in: markdown) {
            while index < lines.count, NSLocationInRange(lineStarts[index], frontMatter) {
                index += 1
            }
        }

        func fenceBlock(at start: Int) -> FenceBlock? {
            fences.blocks.first { NSLocationInRange(start, $0.fullRange) }
        }

        while index < lines.count {
            let line = lines[index]

            if let block = fenceBlock(at: lineStarts[index]) {
                let code = ns.substring(with: block.range)
                if block.language.lowercased() == "mermaid" {
                    html += "<pre class=\"mermaid\">\n\(escape(code))</pre>\n"
                } else {
                    let cls = block.language.isEmpty ? "" : " class=\"language-\(escape(block.language))\""
                    html += "<pre><code\(cls)>\(escape(code))</code></pre>\n"
                }
                while index < lines.count, NSLocationInRange(lineStarts[index], block.fullRange) {
                    index += 1
                }
                continue
            }

            if let block = mathBlocks.first(where: { NSLocationInRange(lineStarts[index], $0.fullRange) }) {
                let latex = ns.substring(with: block.range).trimmingCharacters(in: .whitespacesAndNewlines)
                html += "<p class=\"math\">\\[\(escape(latex))\\]</p>\n"
                while index < lines.count, NSLocationInRange(lineStarts[index], block.fullRange) {
                    index += 1
                }
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let latex = MarkdownParser.displayMathContent(in: line) {
                html += "<p class=\"math\">\\[\(escape(latex))\\]</p>\n"
                index += 1
                continue
            }

            if let definition = MarkdownParser.footnoteDefinitionMarker(in: line) {
                if definitions[definition.label] == nil {
                    definitionOrder.append(definition.label)
                }
                definitions[definition.label] = (line as NSString).substring(from: NSMaxRange(definition.marker))
                index += 1
                continue
            }

            if MarkdownParser.isTOCLine(line) {
                html += toc(outline, slugs: slugs)
                index += 1
                continue
            }

            if let path = MarkdownParser.imageLinePath(in: line) {
                html += "<p><img src=\"\(escape(path))\"></p>\n"
                index += 1
                continue
            }

            switch MarkdownParser.blockKind(of: line) {
            case .horizontalRule:
                html += "<hr>\n"
                index += 1
                continue
            case let .heading(level, marker):
                let content = (line as NSString).substring(from: NSMaxRange(marker))
                let id = slugs[lineStarts[index]].map { " id=\"\($0)\"" } ?? ""
                html += "<h\(level)\(id)>\(inline(content, footnotes: footnotes))</h\(level)>\n"
                index += 1
                continue
            case .blockquote:
                var quoted: [String] = []
                while index < lines.count, case let .blockquote(marker) = MarkdownParser.blockKind(of: lines[index]) {
                    quoted.append((lines[index] as NSString).substring(from: NSMaxRange(marker)))
                    index += 1
                }
                html += "<blockquote><p>\(quoted.map { inline($0, footnotes: footnotes) }.joined(separator: "<br>\n"))</p></blockquote>\n"
                continue
            case .listItem, .taskListItem:
                html += list(&index, lines: lines, footnotes: footnotes)
                continue
            case .tableSeparator:
                index += 1
                continue
            case .fenceDelimiter:
                index += 1
                continue
            case .paragraph:
                break
            }

            if !MarkdownParser.pipeRanges(in: line).isEmpty,
               index + 1 < lines.count,
               MarkdownParser.blockKind(of: lines[index + 1]) == .tableSeparator {
                html += table(&index, lines: lines, footnotes: footnotes)
                continue
            }

            var paragraph: [String] = []
            while index < lines.count,
                  !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  MarkdownParser.blockKind(of: lines[index]) == .paragraph,
                  fenceBlock(at: lineStarts[index]) == nil,
                  MarkdownParser.displayMathContent(in: lines[index]) == nil,
                  MarkdownParser.imageLinePath(in: lines[index]) == nil,
                  MarkdownParser.pipeRanges(in: lines[index]).isEmpty {
                paragraph.append(lines[index])
                index += 1
            }
            if paragraph.isEmpty {
                index += 1
                continue
            }
            html += "<p>\(paragraph.map { inline($0, footnotes: footnotes) }.joined(separator: "\n"))</p>\n"
        }
        let labels = footnotes.order + definitionOrder.filter { footnotes.numbers[$0] == nil }
        if !labels.isEmpty {
            html += "<hr>\n<section class=\"footnotes\">\n<ol>\n"
            for label in labels {
                _ = footnotes.number(for: label)
                let content = definitions[label].map { inline($0) } ?? ""
                html += "<li id=\"fn-\(escape(label))\">\(content) <a href=\"#fnref-\(escape(label))\">&#8617;</a></li>\n"
            }
            html += "</ol>\n</section>\n"
        }
        return html
    }

    private static func list(_ index: inout Int, lines: [String], footnotes: FootnoteContext? = nil) -> String {
        var items: [(text: String, checkbox: Bool, checked: Bool)] = []
        var ordered = false
        var first = true
        loop: while index < lines.count {
            let line = lines[index]
            switch MarkdownParser.blockKind(of: line) {
            case let .listItem(marker):
                if first { ordered = line.trimmingCharacters(in: .whitespaces).first?.isNumber == true }
                items.append(((line as NSString).substring(from: NSMaxRange(marker)), false, false))
            case let .taskListItem(_, box, checked):
                if first { ordered = false }
                items.append(((line as NSString).substring(from: NSMaxRange(box)), true, checked))
            default:
                break loop
            }
            first = false
            index += 1
        }
        let tag = ordered ? "ol" : "ul"
        var html = "<\(tag)>\n"
        for item in items {
            if item.checkbox {
                let checked = item.checked ? " checked" : ""
                html += "<li><input type=\"checkbox\" disabled\(checked)>\(inline(item.text, footnotes: footnotes))</li>\n"
            } else {
                html += "<li>\(inline(item.text, footnotes: footnotes))</li>\n"
            }
        }
        return html + "</\(tag)>\n"
    }

    private static func table(_ index: inout Int, lines: [String], footnotes: FootnoteContext? = nil) -> String {
        func cells(of line: String) -> [String] {
            let ns = line as NSString
            var pipes = MarkdownParser.pipeRanges(in: line).map(\.location)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("|") { pipes.insert(-1, at: 0) }
            if !trimmed.hasSuffix("|") { pipes.append(ns.length) }
            var result: [String] = []
            for (start, end) in zip(pipes, pipes.dropFirst()) {
                let cell = ns.substring(with: NSRange(location: start + 1, length: end - start - 1))
                result.append(cell.trimmingCharacters(in: .whitespaces))
            }
            return result
        }

        var html = "<table>\n<thead>\n<tr>"
        for cell in cells(of: lines[index]) {
            html += "<th>\(inline(cell, footnotes: footnotes))</th>"
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        index += 2
        while index < lines.count, !MarkdownParser.pipeRanges(in: lines[index]).isEmpty {
            html += "<tr>"
            for cell in cells(of: lines[index]) {
                html += "<td>\(inline(cell, footnotes: footnotes))</td>"
            }
            html += "</tr>\n"
            index += 1
        }
        return html + "</tbody>\n</table>\n"
    }

    private static func toc(_ items: [OutlineItem], slugs: [Int: String]) -> String {
        guard !items.isEmpty else { return "" }
        let base = items.map(\.level).min() ?? 1
        var html = "<nav class=\"toc\">\n"
        var level = base - 1
        for item in items {
            let target = max(item.level, base)
            while level < target {
                html += "<ul>\n"
                level += 1
            }
            while level > target {
                html += "</ul>\n"
                level -= 1
            }
            html += "<li><a href=\"#\(slugs[item.location] ?? "")\">\(inline(item.title))</a></li>\n"
        }
        while level >= base {
            html += "</ul>\n"
            level -= 1
        }
        return html + "</nav>\n"
    }

    private static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        var slug = ""
        var lastWasDash = true
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "section" : slug
    }

    private static func inline(_ text: String, footnotes: FootnoteContext? = nil) -> String {
        let ns = text as NSString
        let spans = MarkdownParser.inlineSpans(in: text)
        let mathSpans = MarkdownParser.inlineMathSpans(in: text)
            .filter { math in !spans.contains { NSIntersectionRange($0.range, math.range).length > 0 } }
        let refs = footnotes == nil ? [] : MarkdownParser.footnoteReferences(in: text)
            .filter { ref in !spans.contains { NSIntersectionRange($0.range, ref.range).length > 0 } }

        enum Piece {
            case span(InlineSpan)
            case math(MathSpan)
            case footnote(NSRange, String)

            var location: Int { range.location }

            var range: NSRange {
                switch self {
                case let .span(span): span.range
                case let .math(math): math.range
                case let .footnote(range, _): range
                }
            }
        }

        let pieces = (spans.map(Piece.span) + mathSpans.map(Piece.math) + refs.map { Piece.footnote($0.range, $0.label) })
            .sorted { $0.location < $1.location }
        var html = ""
        var cursor = 0
        for piece in pieces {
            if piece.location > cursor {
                html += escape(ns.substring(with: NSRange(location: cursor, length: piece.location - cursor)))
            }
            switch piece {
            case let .span(span):
                let content = ns.substring(with: span.content)
                switch span.kind {
                case .bold: html += "<strong>\(escape(content))</strong>"
                case .italic: html += "<em>\(escape(content))</em>"
                case .boldItalic: html += "<strong><em>\(escape(content))</em></strong>"
                case .strikethrough: html += "<del>\(escape(content))</del>"
                case .code: html += "<code>\(escape(content))</code>"
                case let .link(url): html += "<a href=\"\(escape(url))\">\(escape(content))</a>"
                }
            case let .math(math):
                html += "\\(\(escape(ns.substring(with: math.content)))\\)"
            case let .footnote(_, label):
                let number = footnotes?.number(for: label) ?? 0
                html += "<sup id=\"fnref-\(escape(label))\"><a href=\"#fn-\(escape(label))\">[\(number)]</a></sup>"
            }
            cursor = NSMaxRange(piece.range)
        }
        if cursor < ns.length {
            html += escape(ns.substring(from: cursor))
        }
        return html
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
