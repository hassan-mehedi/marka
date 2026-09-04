import AppKit

// Table commands: Tab and Return move through cells, the Format > Table menu
// adds, moves, deletes, and aligns rows and columns.
extension EditorViewController {
    enum TableCommand: Int {
        case addRowAbove = 1, addRowBelow, addColumnLeft, addColumnRight
        case moveRowUp, moveRowDown, moveColumnLeft, moveColumnRight
        case deleteRow, deleteColumn, deleteTable
        case alignLeft, alignCenter, alignRight
        case formatTable
    }

    var caretTable: (table: TableBlock, cell: TableEditor.Cell)? {
        let offset = textView.selectedRange().location
        guard let table = highlighter.tables.first(where: {
            offset >= $0.fullRange.location && offset <= NSMaxRange($0.fullRange)
        }), let cell = TableEditor.cell(at: offset, in: table, text: textView.string) else { return nil }
        return (table, cell)
    }

    @objc func performTableCommand(_ sender: NSMenuItem) {
        guard let command = TableCommand(rawValue: sender.tag), let (table, cell) = caretTable else { return }
        var editor = TableEditor(table: table)
        var target = cell
        switch command {
        case .addRowAbove:
            editor.insertRow(at: max(cell.row, 1))
            target.row = max(cell.row, 1)
        case .addRowBelow:
            editor.insertRow(at: cell.row + 1)
            target.row = cell.row + 1
        case .addColumnLeft:
            editor.insertColumn(at: cell.column)
        case .addColumnRight:
            editor.insertColumn(at: cell.column + 1)
            target.column = cell.column + 1
        case .moveRowUp:
            editor.moveRow(cell.row, by: -1)
            if cell.row > 1 { target.row -= 1 }
        case .moveRowDown:
            editor.moveRow(cell.row, by: 1)
            if cell.row >= 1, cell.row + 1 < editor.rows.count { target.row += 1 }
        case .moveColumnLeft:
            editor.moveColumn(cell.column, by: -1)
            if cell.column > 0 { target.column -= 1 }
        case .moveColumnRight:
            editor.moveColumn(cell.column, by: 1)
            if cell.column + 1 < editor.columnCount { target.column += 1 }
        case .deleteRow:
            guard editor.rows.count > 1 else { return deleteTable(table) }
            editor.deleteRow(cell.row)
            target.row = min(cell.row, editor.rows.count - 1)
        case .deleteColumn:
            guard editor.columnCount > 1 else { return deleteTable(table) }
            editor.deleteColumn(cell.column)
            target.column = min(cell.column, editor.columnCount - 1)
        case .deleteTable:
            return deleteTable(table)
        case .alignLeft:
            editor.align(column: cell.column, .left)
        case .alignCenter:
            editor.align(column: cell.column, .center)
        case .alignRight:
            editor.align(column: cell.column, .right)
        case .formatTable:
            break
        }
        apply(editor, replacing: table, caretIn: target, selectContent: false)
    }

    func tableCommandIsAvailable() -> Bool {
        caretTable != nil
    }

    // Tab moves to the next cell, adding a row after the last one.
    func moveToNextTableCell(backward: Bool) -> Bool {
        guard let (table, cell) = caretTable else { return false }
        var editor = TableEditor(table: table)
        var target = cell
        if backward {
            if cell.column > 0 {
                target.column -= 1
            } else if cell.row > 0 {
                target = TableEditor.Cell(row: cell.row - 1, column: editor.columnCount - 1)
            } else {
                return true
            }
        } else if cell.column + 1 < editor.columnCount {
            target.column += 1
        } else if cell.row + 1 < editor.rows.count {
            target = TableEditor.Cell(row: cell.row + 1, column: 0)
        } else {
            editor.insertRow(at: editor.rows.count)
            target = TableEditor.Cell(row: editor.rows.count - 1, column: 0)
        }
        apply(editor, replacing: table, caretIn: target, selectContent: true)
        return true
    }

    // Return inside a table adds a row below the caret's row. After the last
    // pipe of the last row it is a plain newline, so a paragraph can follow a
    // table that ends the document.
    func insertTableRowOnReturn() -> Bool {
        guard let (table, cell) = caretTable else { return false }
        guard textView.selectedRange().location < NSMaxRange(table.fullRange) else { return false }
        var editor = TableEditor(table: table)
        editor.insertRow(at: cell.row + 1)
        apply(editor, replacing: table, caretIn: TableEditor.Cell(row: cell.row + 1, column: 0), selectContent: false)
        return true
    }

    private func deleteTable(_ table: TableBlock) {
        let ns = textView.string as NSString
        var range = table.fullRange
        if NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == 0x0A { range.length += 1 }
        replace(range, with: "", thenSelect: NSRange(location: range.location, length: 0))
    }

    private func apply(_ editor: TableEditor, replacing table: TableBlock, caretIn cell: TableEditor.Cell, selectContent: Bool) {
        let source = editor.formatted()
        let start = table.fullRange.location
        let current = (textView.string as NSString).substring(with: table.fullRange)
        if source != current {
            replace(table.fullRange, with: source, thenSelect: NSRange(location: start, length: 0))
        }
        let rewritten = TableBlock(
            fullRange: NSRange(location: start, length: (source as NSString).length),
            rows: editor.rows,
            alignments: editor.alignments
        )
        guard let content = TableEditor.contentRange(of: cell, in: rewritten, text: textView.string) else { return }
        let selection = selectContent ? content : NSRange(location: NSMaxRange(content), length: 0)
        selectSource(selection)
        textView.scrollRangeToVisible(selection)
    }
}
