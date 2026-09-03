import AppKit
import Testing
@testable import Marka

private let source = "| Name | Qty |\n| --- | ---: |\n| Apple | 3 |\n| Pear | 12 |"

private func table() -> TableBlock {
    MarkdownParser.tables(in: source, excluding: FenceInfo()).first!
}

@Test func cellLookupFromOffset() {
    let block = table()
    #expect(TableEditor.cell(at: 3, in: block, text: source) == TableEditor.Cell(row: 0, column: 0))
    #expect(TableEditor.cell(at: 10, in: block, text: source) == TableEditor.Cell(row: 0, column: 1))
    let pearLine = (source as NSString).range(of: "| Pear").location
    #expect(TableEditor.cell(at: pearLine + 9, in: block, text: source) == TableEditor.Cell(row: 2, column: 1))
    #expect(TableEditor.cell(at: 20, in: block, text: source)?.row == 0)
}

@Test func contentRangeSkipsPadding() {
    let block = table()
    let range = TableEditor.contentRange(of: TableEditor.Cell(row: 1, column: 0), in: block, text: source)!
    #expect((source as NSString).substring(with: range) == "Apple")
}

@Test func formattedAlignsPipes() {
    let editor = TableEditor(table: table())
    #expect(editor.formatted() == "| Name  | Qty |\n| ----- | --: |\n| Apple | 3   |\n| Pear  | 12  |")
}

@Test func structuralEdits() {
    var editor = TableEditor(table: table())
    editor.insertColumn(at: 1)
    #expect(editor.rows[0] == ["Name", "Column 2", "Qty"])
    #expect(editor.alignments == [.left, .left, .right])
    editor.deleteColumn(1)
    editor.insertRow(at: 1)
    #expect(editor.rows[1] == ["", ""])
    editor.moveRow(1, by: 1)
    #expect(editor.rows[1] == ["Apple", "3"])
    editor.deleteRow(2)
    editor.align(column: 0, .center)
    #expect(editor.formatted() == "| Name  | Qty |\n| :---: | --: |\n| Apple | 3   |\n| Pear  | 12  |")
    editor.moveRow(0, by: 1)
    #expect(editor.rows[0] == ["Name", "Qty"])
}

@MainActor
private func makeEditor(_ text: String, caret: Int) -> EditorViewController {
    let editor = EditorViewController()
    editor.loadView()
    editor.text = text
    editor.textView.setSelectedRange(NSRange(location: caret, length: 0))
    return editor
}

@Test @MainActor func tabMovesThroughCellsAndAppendsRow() {
    let editor = makeEditor(source, caret: 3)
    #expect(editor.moveToNextTableCell(backward: false))
    #expect((editor.text as NSString).substring(with: editor.textView.selectedRange()) == "Qty")
    #expect(editor.moveToNextTableCell(backward: false))
    #expect((editor.text as NSString).substring(with: editor.textView.selectedRange()) == "Apple")
    #expect(editor.moveToNextTableCell(backward: true))
    #expect((editor.text as NSString).substring(with: editor.textView.selectedRange()) == "Qty")

    let last = (editor.text as NSString).range(of: "12").location
    editor.textView.setSelectedRange(NSRange(location: last, length: 0))
    #expect(editor.moveToNextTableCell(backward: false))
    #expect(editor.text.hasSuffix("| Pear  | 12  |\n|       |     |"))
    #expect(editor.textView.selectedRange().location == (editor.text as NSString).range(of: "|       |").location + 2)
}

@Test @MainActor func returnAddsRowBelowCaret() {
    let editor = makeEditor(source + "\n\nafter", caret: 3)
    #expect(editor.insertTableRowOnReturn())
    #expect(editor.text == "| Name  | Qty |\n| ----- | --: |\n|       |     |\n| Apple | 3   |\n| Pear  | 12  |\n\nafter")
    #expect(editor.textView.selectedRange().location == (editor.text as NSString).range(of: "|       |").location + 2)
    #expect(!makeEditor("plain", caret: 2).insertTableRowOnReturn())
}
