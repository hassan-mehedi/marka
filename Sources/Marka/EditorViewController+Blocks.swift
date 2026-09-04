import AppKit
import UniformTypeIdentifiers

// Block-level commands from the Format menu: list and quote toggles plus
// inserting fences, tables, images, math, footnotes, and rules.
extension EditorViewController {
    enum ListStyle {
        case bullet, ordered, task
    }

    @objc func toggleBulletList(_ sender: Any?) { toggleList(.bullet) }
    @objc func toggleOrderedList(_ sender: Any?) { toggleList(.ordered) }
    @objc func toggleTaskList(_ sender: Any?) { toggleList(.task) }

    @objc func toggleBlockquote(_ sender: Any?) {
        rewriteSelectedLines { lines in
            let allQuoted = lines.allSatisfy { line in
                if case .blockquote = MarkdownParser.blockKind(of: line) { return true }
                return line.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return lines.map { line in
                if allQuoted {
                    guard case let .blockquote(marker) = MarkdownParser.blockKind(of: line) else { return line }
                    return (line as NSString).replacingCharacters(in: marker, with: "")
                }
                return "> " + line
            }
        }
    }

    @objc func insertCodeFence(_ sender: Any?) {
        insertBlock(open: "```", close: "```")
    }

    @objc func insertMathBlock(_ sender: Any?) {
        insertBlock(open: "$$", close: "$$")
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        insertStandaloneBlock("---", caretOffset: nil)
    }

    @objc func insertFootnote(_ sender: Any?) {
        let ns = textView.string as NSString
        let label = Self.nextFootnoteLabel(in: textView.string)
        let caret = textView.selectedRange()
        let reference = "[^\(label)]"
        let trailing = ns.length == 0 || ns.hasSuffix("\n") ? "\n" : "\n\n"
        let definition = "\(trailing)[^\(label)]: "

        let end = NSRange(location: ns.length, length: 0)
        guard textView.shouldChangeText(inRanges: [NSValue(range: caret), NSValue(range: end)], replacementStrings: [reference, definition]) else {
            return
        }
        textView.textStorage?.replaceCharacters(in: end, with: definition)
        textView.textStorage?.replaceCharacters(in: caret, with: reference)
        textView.didChangeText()
        let target = NSRange(location: (textView.string as NSString).length, length: 0)
        selectSource(target)
        textView.scrollRangeToVisible(target)
    }

    @objc func insertTable(_ sender: Any?) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Insert Table"
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let rows = NSTextField(string: "3")
        let columns = NSTextField(string: "3")
        for field in [rows, columns] {
            field.alignment = .right
            field.formatter = Self.tableSizeFormatter
        }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Rows"), rows],
            [NSTextField(labelWithString: "Columns"), columns],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 1).width = 60
        grid.frame = NSRect(x: 0, y: 0, width: 160, height: 56)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = rows

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.insertTable(rows: max(1, rows.integerValue), columns: max(1, columns.integerValue))
        }
    }

    func insertTable(rows: Int, columns: Int) {
        let header = "| " + (1...columns).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let separator = "|" + String(repeating: " --- |", count: columns)
        let body = String(repeating: "|" + String(repeating: "   |", count: columns) + "\n", count: max(rows - 1, 0))
        let table = ([header, separator].joined(separator: "\n") + "\n" + body).trimmingCharacters(in: .newlines)
        insertStandaloneBlock(table, caretOffset: 2, selectLength: ("Column 1" as NSString).length)
    }

    @objc func insertImage(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let path = self.markdownPath(for: url)
            let markdown = "![](\(path))"
            let caret = self.textView.selectedRange()
            self.replace(caret, with: markdown, thenSelect: NSRange(location: caret.location + 2, length: 0))
        }
    }

    func markdownPath(for url: URL) -> String {
        guard let base = document?.fileURL?.deletingLastPathComponent() else { return url.path }
        let baseParts = base.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > baseParts.count, Array(parts.prefix(baseParts.count)) == baseParts else { return url.path }
        return parts.dropFirst(baseParts.count).joined(separator: "/")
    }

    private static let tableSizeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 50
        formatter.allowsFloats = false
        return formatter
    }()

    nonisolated static func nextFootnoteLabel(in text: String) -> Int {
        var used: Set<Int> = []
        text.enumerateLines { line, _ in
            for reference in MarkdownParser.footnoteReferences(in: line) {
                if let number = Int(reference.label) { used.insert(number) }
            }
            if let definition = MarkdownParser.footnoteDefinitionMarker(in: line), let number = Int(definition.label) {
                used.insert(number)
            }
        }
        var label = 1
        while used.contains(label) { label += 1 }
        return label
    }

    private func toggleList(_ style: ListStyle) {
        rewriteSelectedLines { lines in
            let alreadyStyled = lines.allSatisfy { line in
                Self.listStyle(of: line) == style || line.trimmingCharacters(in: .whitespaces).isEmpty
            }
            var number = 0
            return lines.map { line in
                let stripped = Self.strippingListMarker(line)
                if alreadyStyled || line.trimmingCharacters(in: .whitespaces).isEmpty {
                    return alreadyStyled ? stripped.text : line
                }
                switch style {
                case .bullet:
                    return stripped.indent + "- " + stripped.text
                case .task:
                    return stripped.indent + "- [ ] " + stripped.text
                case .ordered:
                    number += 1
                    return stripped.indent + "\(number). " + stripped.text
                }
            }
        }
    }

    nonisolated static func listStyle(of line: String) -> ListStyle? {
        switch MarkdownParser.blockKind(of: line) {
        case .taskListItem:
            return .task
        case let .listItem(marker):
            let text = (line as NSString).substring(with: marker).trimmingCharacters(in: .whitespaces)
            return text.first?.isNumber == true ? .ordered : .bullet
        default:
            return nil
        }
    }

    // The leading whitespace and the content after any list marker.
    nonisolated static func strippingListMarker(_ line: String) -> (indent: String, text: String) {
        let ns = line as NSString
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        switch MarkdownParser.blockKind(of: line) {
        case let .taskListItem(_, box, _):
            let rest = ns.substring(from: NSMaxRange(box))
            return (indent, rest.hasPrefix(" ") ? String(rest.dropFirst()) : rest)
        case let .listItem(marker):
            return (indent, ns.substring(from: NSMaxRange(marker)))
        default:
            return (indent, String(line.dropFirst(indent.count)))
        }
    }

    // Applies a line transform to every paragraph the selection touches. A
    // selection stays over the rewritten lines; a bare caret keeps its column.
    private func rewriteSelectedLines(_ transform: ([String]) -> [String]) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound else { return }
        let range = ns.paragraphRange(for: selection)
        var block = ns.substring(with: range)
        let hadNewline = block.hasSuffix("\n")
        if hadNewline { block.removeLast() }
        let lines = block.components(separatedBy: "\n")
        let rewrittenLines = transform(lines)
        let rewritten = rewrittenLines.joined(separator: "\n")
        guard rewritten != block else { return }

        let newLength = (rewritten as NSString).length
        let firstDelta = ((rewrittenLines.first ?? "") as NSString).length - ((lines.first ?? "") as NSString).length
        let target = selection.length == 0
            ? NSRange(location: min(max(selection.location + firstDelta, range.location), range.location + newLength), length: 0)
            : NSRange(location: range.location, length: newLength)
        replace(range, with: rewritten + (hadNewline ? "\n" : ""), thenSelect: target)
    }

    // Wraps the selection in open/close delimiter lines, or inserts an empty
    // pair with the caret between them.
    private func insertBlock(open: String, close: String) {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        if selection.length > 0 {
            let range = ns.paragraphRange(for: selection)
            var body = ns.substring(with: range)
            let hadNewline = body.hasSuffix("\n")
            if hadNewline { body.removeLast() }
            let wrapped = open + "\n" + body + "\n" + close + (hadNewline ? "\n" : "")
            replace(range, with: wrapped, thenSelect: NSRange(location: range.location + (open as NSString).length + 1, length: (body as NSString).length))
            return
        }
        insertStandaloneBlock(open + "\n\n" + close, caretOffset: (open as NSString).length + 1)
    }

    // Inserts text as its own paragraph with blank lines around it. caretOffset
    // is where the caret lands inside the inserted text; nil puts it after.
    func insertStandaloneBlock(_ text: String, caretOffset: Int?, selectLength: Int = 0) {
        let ns = textView.string as NSString
        let caret = textView.selectedRange()
        let paragraph = ns.paragraphRange(for: NSRange(location: caret.location, length: 0))
        let line = Self.lineContent(of: paragraph, in: ns)
        let lineEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty

        var prefix = ""
        var suffix = ""
        let insertAt: NSRange
        if lineEmpty {
            insertAt = NSRange(location: paragraph.location, length: (line as NSString).length)
            if paragraph.location > 0 {
                let previous = ns.paragraphRange(for: NSRange(location: paragraph.location - 1, length: 0))
                if !Self.lineContent(of: previous, in: ns).trimmingCharacters(in: .whitespaces).isEmpty { prefix = "\n" }
            }
        } else {
            insertAt = NSRange(location: paragraph.location + (line as NSString).length, length: 0)
            prefix = "\n\n"
        }
        let nextStart = NSMaxRange(paragraph)
        if nextStart > paragraph.location, nextStart < ns.length {
            let next = ns.paragraphRange(for: NSRange(location: nextStart, length: 0))
            if !Self.lineContent(of: next, in: ns).trimmingCharacters(in: .whitespaces).isEmpty { suffix = "\n" }
        }
        if NSMaxRange(paragraph) >= ns.length, caretOffset == nil { suffix = "\n" }

        let base = insertAt.location + (prefix as NSString).length
        let target = caretOffset.map { NSRange(location: base + $0, length: selectLength) }
            ?? NSRange(location: base + (text as NSString).length + 1, length: 0)
        replace(insertAt, with: prefix + text + suffix, thenSelect: target)
    }

    nonisolated private static func lineContent(of paragraph: NSRange, in ns: NSString) -> String {
        var line = ns.substring(with: paragraph)
        if line.hasSuffix("\n") { line.removeLast() }
        return line
    }
}
