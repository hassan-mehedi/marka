import AppKit
import Testing
@testable import Marka

@MainActor
private func makeEditor(text: String, caret: Int) -> EditorViewController {
    let editor = EditorViewController()
    editor.loadView()
    editor.text = text
    editor.textView.setSelectedRange(NSRange(location: caret, length: 0))
    return editor
}

@MainActor
private func type(_ typed: String, into editor: EditorViewController) -> Bool {
    let selection = editor.textView.selectedRange()
    return editor.textView(editor.textView, shouldChangeTextIn: selection, replacementString: typed)
}

@Test @MainActor func smartQuotesCurlByPosition() {
    UserDefaults.standard.set(true, forKey: "MarkaSmartPunctuation")
    defer { UserDefaults.standard.removeObject(forKey: "MarkaSmartPunctuation") }

    let editor = makeEditor(text: "Say ", caret: 4)
    #expect(!type("\"", into: editor))
    #expect(editor.text == "Say \u{201C}")

    #expect(!type("hi", into: editor) == false)
    let closing = makeEditor(text: "Say \u{201C}hi", caret: 7)
    #expect(!type("\"", into: closing))
    #expect(closing.text == "Say \u{201C}hi\u{201D}")

    let apostrophe = makeEditor(text: "don", caret: 3)
    #expect(!type("'", into: apostrophe))
    #expect(apostrophe.text == "don\u{2019}")
}

@Test @MainActor func smartDashConvertsDoubleHyphen() {
    UserDefaults.standard.set(true, forKey: "MarkaSmartPunctuation")
    defer { UserDefaults.standard.removeObject(forKey: "MarkaSmartPunctuation") }

    let editor = makeEditor(text: "word -", caret: 6)
    #expect(!type("-", into: editor))
    #expect(editor.text == "word \u{2014}")

    let rule = makeEditor(text: "--", caret: 2)
    #expect(type("-", into: rule))
    #expect(rule.text == "--")

    let table = makeEditor(text: "| -", caret: 3)
    #expect(type("-", into: table))
}

@Test @MainActor func smartPunctuationSkipsCodeContexts() {
    UserDefaults.standard.set(true, forKey: "MarkaSmartPunctuation")
    defer { UserDefaults.standard.removeObject(forKey: "MarkaSmartPunctuation") }

    let span = makeEditor(text: "`ab`", caret: 2)
    #expect(type("\"", into: span))

    let fence = makeEditor(text: "```\ncode\n```\n", caret: 6)
    #expect(type("\"", into: fence))

    let math = makeEditor(text: "$x y$", caret: 3)
    #expect(type("'", into: math))
}

@Test @MainActor func smartPunctuationOffByDefault() {
    UserDefaults.standard.removeObject(forKey: "MarkaSmartPunctuation")
    let editor = makeEditor(text: "Say ", caret: 4)
    #expect(type("\"", into: editor))
    #expect(editor.text == "Say ")
}
