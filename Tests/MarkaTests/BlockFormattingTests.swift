import AppKit
import Testing
@testable import Marka

@MainActor
private func makeEditor(_ text: String, select range: NSRange) -> EditorViewController {
    let editor = EditorViewController()
    editor.loadView()
    editor.text = text
    editor.textView.setSelectedRange(range)
    return editor
}

@Test @MainActor func bulletListTogglesSelectedLines() {
    let editor = makeEditor("one\ntwo\nthree", select: NSRange(location: 0, length: 7))
    editor.toggleBulletList(nil)
    #expect(editor.text == "- one\n- two\nthree")
    #expect(editor.textView.selectedRange() == NSRange(location: 0, length: 11))

    editor.toggleBulletList(nil)
    #expect(editor.text == "one\ntwo\nthree")
}

@Test @MainActor func orderedListNumbersLinesAndKeepsCaretColumn() {
    let editor = makeEditor("a\nb\nc", select: NSRange(location: 0, length: 5))
    editor.toggleOrderedList(nil)
    #expect(editor.text == "1. a\n2. b\n3. c")

    let caret = makeEditor("- item", select: NSRange(location: 4, length: 0))
    caret.toggleOrderedList(nil)
    #expect(caret.text == "1. item")
    #expect(caret.textView.selectedRange().location == 5)
}

@Test @MainActor func taskListConvertsBulletsAndBack() {
    let editor = makeEditor("- a\n- b", select: NSRange(location: 0, length: 7))
    editor.toggleTaskList(nil)
    #expect(editor.text == "- [ ] a\n- [ ] b")
    editor.toggleTaskList(nil)
    #expect(editor.text == "a\nb")
}

@Test @MainActor func blockquoteToggles() {
    let editor = makeEditor("quote me", select: NSRange(location: 3, length: 0))
    editor.toggleBlockquote(nil)
    #expect(editor.text == "> quote me")
    #expect(editor.textView.selectedRange().location == 5)
    editor.toggleBlockquote(nil)
    #expect(editor.text == "quote me")
}

@Test @MainActor func codeFenceWrapsSelectionOrOpensEmptyBlock() {
    let wrap = makeEditor("intro\nlet x = 1\nafter", select: NSRange(location: 6, length: 9))
    wrap.insertCodeFence(nil)
    #expect(wrap.text == "intro\n```\nlet x = 1\n```\nafter")
    #expect(wrap.textView.selectedRange() == NSRange(location: 10, length: 9))

    let empty = makeEditor("intro\nafter", select: NSRange(location: 5, length: 0))
    empty.insertCodeFence(nil)
    #expect(empty.text == "intro\n\n```\n\n```\n\nafter")
    #expect(empty.textView.selectedRange() == NSRange(location: 11, length: 0))
}

@Test @MainActor func horizontalRuleGetsBlankLinesAround() {
    let middle = makeEditor("a\n\nb", select: NSRange(location: 2, length: 0))
    middle.insertHorizontalRule(nil)
    #expect(middle.text == "a\n\n---\n\nb")

    let end = makeEditor("a", select: NSRange(location: 1, length: 0))
    end.insertHorizontalRule(nil)
    #expect(end.text == "a\n\n---\n")
    #expect(end.textView.selectedRange().location == 7)
}

@Test @MainActor func tableInsertSelectsFirstHeaderCell() {
    let editor = makeEditor("", select: NSRange(location: 0, length: 0))
    editor.insertTable(rows: 2, columns: 2)
    #expect(editor.text == "| Column 1 | Column 2 |\n| --- | --- |\n|   |   |")
    #expect(editor.textView.selectedRange() == NSRange(location: 2, length: 8))
}

@Test @MainActor func footnoteUsesNextFreeNumberAndAppendsDefinition() {
    let editor = makeEditor("Text[^1] more\n\n[^1]: first", select: NSRange(location: 13, length: 0))
    editor.insertFootnote(nil)
    #expect(editor.text == "Text[^1] more[^2]\n\n[^1]: first\n\n[^2]: ")
    #expect(editor.textView.selectedRange().location == (editor.text as NSString).length)
}

@Test @MainActor func fontScaleScalesThemeFonts() {
    let manager = ThemeManager.shared
    let base = manager.baseTheme.baseFontSize
    defer { manager.setFontScale(1) }
    manager.setFontScale(1.5)
    #expect(manager.current.baseFontSize == (base * 1.5).rounded())
    manager.setFontScale(9)
    #expect(manager.fontScale == 3)
}
