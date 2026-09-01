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

@Test func displayColumnMapsBackToSourceOffset() {
    let line = "**bold** text"
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 4, in: line) == 6)
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 5, in: line) == 9)
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 0, in: line) == 0)
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 9, in: line) == 13)

    let math = "a $x$ b"
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 2, in: math) == 2)
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 3, in: math) == 5)
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 4, in: math) == 6)

    let heading = "## Title"
    #expect(EditorViewController.sourceOffset(forDisplayColumn: 2, in: heading) == 5)
}

@Test @MainActor func markersVanishFromUntouchedParagraphs() {
    let editor = makeEditor("**bold** and `code`\nplain\n", caret: 22)
    let display = displayString(editor, paragraph: NSRange(location: 0, length: 20))
    #expect(display == "bold and code\n")
}

@Test @MainActor func headingMarkerVanishes() {
    let editor = makeEditor("## Title\nplain\n", caret: 11)
    #expect(displayString(editor, paragraph: NSRange(location: 0, length: 9)) == "Title\n")
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

@Test @MainActor func caretEntryRemapsDisplayColumn() {
    let editor = makeEditor("**bold** text\nplain\n", caret: 16)
    editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))

    editor.textView.setSelectedRange(NSRange(location: 4, length: 0))
    editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
    #expect(editor.textView.selectedRange() == NSRange(location: 6, length: 0))

    editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
    #expect(editor.textView.selectedRange() == NSRange(location: 6, length: 0))
}
