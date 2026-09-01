import AppKit
import Foundation
import Testing
@testable import Marka

@Test func outlineCollectsHeadingsWithLocations() {
    let text = "# One\n\ntext\n\n## Two\n### Three\n"
    let items = MarkdownParser.outline(in: text)
    #expect(items.count == 3)
    #expect(items[0] == OutlineItem(level: 1, title: "One", location: 0))
    #expect(items[1].level == 2)
    #expect(items[1].title == "Two")
    #expect(items[2].title == "Three")
    #expect((text as NSString).substring(from: items[1].location).hasPrefix("## Two"))
}

@Test func outlineIgnoresHeadingsInsideFences() {
    let items = MarkdownParser.outline(in: "# Real\n")
    #expect(items.map(\.title) == ["Real"])
}

@Test @MainActor func documentRoundTripsUTF8() throws {
    let document = MarkaDocument()
    let original = "# Título\n\nemoji 🎉 and ünicode\n"
    try document.read(from: Data(original.utf8), ofType: MarkaDocument.markdownType)
    #expect(document.text == original)

    let written = try document.data(ofType: MarkaDocument.markdownType)
    #expect(String(data: written, encoding: .utf8) == original)
}

@Test @MainActor func documentRejectsInvalidUTF8() {
    let document = MarkaDocument()
    let invalid = Data([0xFF, 0xFE, 0xFD])
    #expect(throws: (any Error).self) {
        try document.read(from: invalid, ofType: MarkaDocument.markdownType)
    }
}

@Test @MainActor func documentPicksExtensionByType() {
    let document = MarkaDocument()
    #expect(document.fileNameExtension(forType: MarkaDocument.markdownType, saveOperation: .saveOperation) == "md")
    #expect(document.fileNameExtension(forType: MarkaDocument.plainTextType, saveOperation: .saveOperation) == "txt")
}

@Test @MainActor func outlineSidebarBuildsRowsForHeadings() {
    let outline = OutlineViewController()
    outline.loadView()
    outline.update(MarkdownParser.outline(in: "# One\n## Two\n"))

    guard let table = outline.view.subviews.compactMap({ $0 as? NSClipView }).first?.documentView as? NSTableView else {
        Issue.record("expected a table view inside the sidebar scroll view")
        return
    }
    #expect(table.numberOfRows == 2)

    guard let cell = outline.tableView(table, viewFor: table.tableColumns.first, row: 1) as? NSTableCellView,
          let label = cell.subviews.compactMap({ $0 as? NSTextField }).first
    else {
        Issue.record("expected a labelled cell view")
        return
    }
    #expect(label.stringValue == "Two")
}
