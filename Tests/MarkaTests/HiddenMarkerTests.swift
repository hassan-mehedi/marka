import AppKit
import Testing
@testable import Marka

@MainActor
private func makeEditor(_ text: String, caret: Int) -> EditorViewController {
    let editor = EditorViewController()
    editor.loadView()
    editor.text = text
    editor.textView.setSelectedRange(NSRange(location: caret, length: 0))
    return editor
}

@MainActor
private func displayString(_ editor: EditorViewController, paragraph: NSRange) -> String? {
    guard let contentStorage = editor.textView.textContentStorage else { return nil }
    return editor.textContentStorage(contentStorage, textParagraphWith: paragraph)?
        .attributedString.string
}

@MainActor
private func fontSizes(_ editor: EditorViewController, in range: NSRange) -> [CGFloat] {
    guard let storage = editor.textView.textStorage else { return [] }
    return (range.location..<NSMaxRange(range)).map { index in
        (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
    }
}

@Test @MainActor func markersShrinkToZeroInUntouchedParagraphs() {
    let editor = makeEditor("**bold** and `code`\nplain\n", caret: 22)
    #expect(displayString(editor, paragraph: NSRange(location: 0, length: 20)) == nil)
    #expect(fontSizes(editor, in: NSRange(location: 0, length: 2)) == [0.01, 0.01])
    #expect(fontSizes(editor, in: NSRange(location: 6, length: 2)) == [0.01, 0.01])
    #expect(fontSizes(editor, in: NSRange(location: 2, length: 4)).allSatisfy { $0 > 1 })
    #expect(fontSizes(editor, in: NSRange(location: 13, length: 1)) == [0.01])
    #expect(fontSizes(editor, in: NSRange(location: 18, length: 1)) == [0.01])
}

@Test @MainActor func headingMarkerShrinksToZero() {
    let editor = makeEditor("## Title\nplain\n", caret: 11)
    #expect(displayString(editor, paragraph: NSRange(location: 0, length: 9)) == nil)
    #expect(fontSizes(editor, in: NSRange(location: 0, length: 3)) == [0.01, 0.01, 0.01])
    #expect(fontSizes(editor, in: NSRange(location: 3, length: 5)).allSatisfy { $0 > 1 })
}

@Test @MainActor func caretParagraphKeepsItsMarkers() {
    let editor = makeEditor("**bold** text\nplain\n", caret: 3)
    #expect(displayString(editor, paragraph: NSRange(location: 0, length: 14)) == nil)
}

@Test @MainActor func fenceContentKeepsMarkers() {
    let editor = makeEditor("```\n**x** `y`\n```\nplain\n", caret: 20)
    #expect(displayString(editor, paragraph: NSRange(location: 4, length: 10)) == nil)
}

@Test @MainActor func sourceModeKeepsMarkers() {
    let editor = makeEditor("**bold**\nplain\n", caret: 11)
    editor.toggleSourceMode(NSMenuItem())
    #expect(displayString(editor, paragraph: NSRange(location: 0, length: 9)) == nil)
}

@MainActor
private func displayParagraph(_ editor: EditorViewController, paragraph: NSRange) -> NSAttributedString? {
    guard let contentStorage = editor.textView.textContentStorage else { return nil }
    return editor.textContentStorage(contentStorage, textParagraphWith: paragraph)?.attributedString
}

@Test @MainActor func collapsedParagraphsKeepTheSourceLength() {
    let table = makeEditor("| a | b |\n|---|---|\n| 1 | 2 |\nplain\n", caret: 32)
    let header = displayParagraph(table, paragraph: NSRange(location: 0, length: 10))
    #expect(header?.length == 10)
    #expect(header?.string.first == "\u{FFFC}")
    #expect((header?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize == 0.01)
    let separator = displayParagraph(table, paragraph: NSRange(location: 10, length: 10))
    #expect(separator?.length == 10)
    #expect((separator?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 0.01)

    let fence = makeEditor("```swift\nlet a = 1\n```\nplain\n", caret: 25)
    let open = displayParagraph(fence, paragraph: NSRange(location: 0, length: 9))
    #expect(open?.length == 9)
    #expect(open?.string.hasPrefix("swift") == true)
    #expect(displayParagraph(fence, paragraph: NSRange(location: 19, length: 4))?.length == 4)

    let diagram = makeEditor("```mermaid\ngraph TD\nA-->B\n```\nplain\n", caret: 32)
    #expect(displayParagraph(diagram, paragraph: NSRange(location: 0, length: 11))?.length == 11)
    #expect(displayParagraph(diagram, paragraph: NSRange(location: 11, length: 9))?.length == 9)
}

@Test @MainActor func inlineMathKeepsTheSourceLength() {
    let editor = makeEditor("a $x$ b\nplain\n", caret: 10)
    guard let display = displayParagraph(editor, paragraph: NSRange(location: 0, length: 8)) else {
        Issue.record("math paragraph was not replaced")
        return
    }
    #expect(display.length == 8)
    #expect(display.string[display.string.index(display.string.startIndex, offsetBy: 2)] == "\u{FFFC}")
    #expect((display.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize == 0.01)
    #expect((display.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.pointSize == 0.01)
    #expect((display.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 > 1)
}

@Test @MainActor func editsBeforeAFenceKeepTheStructureEqual() {
    let before = "intro\n\n```swift\nlet a = 1\n```\n"
    let after = "intro!\n\n```swift\nlet a = 1\n```\n"
    let old = MarkdownParser.fences(in: before)
    let new = MarkdownParser.fences(in: after)
    #expect(MarkdownHighlighter.sameStructure(old: old, new: new, edit: (start: 5, delta: 1)))
    #expect(!MarkdownHighlighter.sameStructure(old: old, new: new, edit: (start: 5, delta: 0)))

    let inside = MarkdownParser.fences(in: "intro\n\n```swift\nlet ab = 1\n```\n")
    #expect(MarkdownHighlighter.sameStructure(old: old, new: inside, edit: (start: 20, delta: 1)))
    #expect(MarkdownHighlighter.shift(NSRange(location: 10, length: 5), by: (start: 12, delta: 2)) == NSRange(location: 10, length: 7))
    #expect(MarkdownHighlighter.shift(NSRange(location: 10, length: 5), by: (start: 3, delta: -2)) == NSRange(location: 8, length: 5))
}
