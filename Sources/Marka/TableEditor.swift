import Foundation

// Structural edits on a pipe table's source text. Every edit returns the
// rewritten table plus the cell the caret should land in.
struct TableEditor: Equatable {
    struct Cell: Equatable {
        var row: Int
        var column: Int
    }

    var rows: [[String]]
    var alignments: [TableBlock.Alignment]

    init(table: TableBlock) {
        rows = table.rows
        alignments = table.alignments
    }

    init(rows: [[String]], alignments: [TableBlock.Alignment]) {
        self.rows = rows
        self.alignments = alignments
    }

    var columnCount: Int { alignments.count }

    // Maps a caret offset inside the table source to a cell. The separator
    // line counts as the header row.
    static func cell(at offset: Int, in table: TableBlock, text: String) -> Cell? {
        guard offset >= table.fullRange.location, offset <= NSMaxRange(table.fullRange) else { return nil }
        let lines = lineRanges(of: table, in: text)
        guard let lineIndex = lines.lastIndex(where: { $0.location <= offset }) else { return nil }
        let row = lineIndex == 0 ? 0 : max(lineIndex - 1, 0)
        let ns = text as NSString
        let line = ns.substring(with: lines[lineIndex])
        let column = offset - lines[lineIndex].location
        let pipes = MarkdownParser.pipeRanges(in: line).map(\.location)
        var boundaries = pipes
        if !line.trimmingCharacters(in: .whitespaces).hasPrefix("|") { boundaries.insert(-1, at: 0) }
        let index = boundaries.filter { $0 < column }.count - 1
        let columns = table.alignments.count
        return Cell(row: min(row, table.rows.count - 1), column: min(max(index, 0), columns - 1))
    }

    static func lineRanges(of table: TableBlock, in text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        ns.enumerateSubstrings(in: table.fullRange, options: .byLines) { _, lineRange, _, _ in
            ranges.append(lineRange)
        }
        return ranges
    }

    // The source range of a cell's trimmed content.
    static func contentRange(of cell: Cell, in table: TableBlock, text: String) -> NSRange? {
        let lines = lineRanges(of: table, in: text)
        let lineIndex = cell.row == 0 ? 0 : cell.row + 1
        guard lineIndex < lines.count else { return nil }
        let ns = text as NSString
        let lineRange = lines[lineIndex]
        let line = ns.substring(with: lineRange)
        var boundaries = MarkdownParser.pipeRanges(in: line).map(\.location)
        if !line.trimmingCharacters(in: .whitespaces).hasPrefix("|") { boundaries.insert(-1, at: 0) }
        if !line.trimmingCharacters(in: .whitespaces).hasSuffix("|") { boundaries.append((line as NSString).length) }
        guard cell.column + 1 < boundaries.count else {
            return NSRange(location: NSMaxRange(lineRange), length: 0)
        }
        let start = boundaries[cell.column] + 1
        let end = boundaries[cell.column + 1]
        let raw = (line as NSString).substring(with: NSRange(location: start, length: end - start))
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return NSRange(location: lineRange.location + start + min(1, (raw as NSString).length), length: 0)
        }
        let leading = raw.prefix { $0 == " " }.count
        return NSRange(location: lineRange.location + start + leading, length: (trimmed as NSString).length)
    }

    // Column widths padded so the pipes line up in source view.
    func formatted() -> String {
        let widths = (0..<columnCount).map { column in
            max(3, rows.map { ($0.indices.contains(column) ? $0[column] : "").count }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { index, cell in
                cell + String(repeating: " ", count: max(widths[index] - cell.count, 0))
            }.joined(separator: " | ") + " |"
        }
        let separator = "| " + alignments.enumerated().map { index, alignment in
            let width = widths[index]
            switch alignment {
            case .left: return String(repeating: "-", count: width)
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            case .right: return String(repeating: "-", count: width - 1) + ":"
            }
        }.joined(separator: " | ") + " |"
        var lines = [line(rows.first ?? []), separator]
        lines += rows.dropFirst().map(line)
        return lines.joined(separator: "\n")
    }

    mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: min(max(index, 1), rows.count))
    }

    mutating func deleteRow(_ index: Int) {
        guard rows.indices.contains(index), rows.count > 1 else { return }
        rows.remove(at: index)
    }

    mutating func moveRow(_ index: Int, by delta: Int) {
        let target = index + delta
        guard index >= 1, rows.indices.contains(index), target >= 1, rows.indices.contains(target) else { return }
        rows.swapAt(index, target)
    }

    mutating func insertColumn(at index: Int) {
        let index = min(max(index, 0), columnCount)
        alignments.insert(.left, at: index)
        for row in rows.indices {
            rows[row].insert(row == 0 ? "Column \(index + 1)" : "", at: index)
        }
    }

    mutating func deleteColumn(_ index: Int) {
        guard alignments.indices.contains(index), columnCount > 1 else { return }
        alignments.remove(at: index)
        for row in rows.indices where rows[row].indices.contains(index) {
            rows[row].remove(at: index)
        }
    }

    mutating func moveColumn(_ index: Int, by delta: Int) {
        let target = index + delta
        guard alignments.indices.contains(index), alignments.indices.contains(target) else { return }
        alignments.swapAt(index, target)
        for row in rows.indices where rows[row].indices.contains(index) && rows[row].indices.contains(target) {
            rows[row].swapAt(index, target)
        }
    }

    mutating func align(column: Int, _ alignment: TableBlock.Alignment) {
        guard alignments.indices.contains(column) else { return }
        alignments[column] = alignment
    }
}
