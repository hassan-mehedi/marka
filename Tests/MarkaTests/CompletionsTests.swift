import AppKit
import Testing
@testable import Marka

@Test func emojiCompletionsPreferPrefixMatches() {
    let smile = Completions.emoji(matching: "smi")
    #expect(smile.first == "😄 :smile:")
    #expect(Completions.insertion(for: "😄 :smile:") == "😄")
    #expect(Completions.insertion(for: "```swift") == "```swift")
    #expect(Completions.emoji(matching: "zzzz").isEmpty)
}

@Test func languageCompletionsFilterByPrefix() {
    let languages = Completions.languages(matching: "sw")
    #expect(languages.contains("swift"))
    #expect(languages.allSatisfy { $0.hasPrefix("sw") })
    #expect(Completions.languages(matching: "").count == 12)
    #expect(Completions.languages.contains("mermaid"))
}

@Test @MainActor func completionRangeIncludesShortcodeColonAndFence() {
    let editor = EditorViewController()
    editor.loadView()
    editor.text = "Hi :smi"
    editor.textView.setSelectedRange(NSRange(location: 7, length: 0))
    let range = editor.textView.rangeForUserCompletion
    #expect((editor.text as NSString).substring(with: range) == ":smi")
    #expect(editor.textView(editor.textView, completions: [], forPartialWordRange: range, indexOfSelectedItem: nil).first == "😄 :smile:")

    editor.text = "```sw"
    editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
    let fence = editor.textView.rangeForUserCompletion
    #expect((editor.text as NSString).substring(with: fence) == "```sw")
    #expect(editor.textView(editor.textView, completions: [], forPartialWordRange: fence, indexOfSelectedItem: nil).contains("```swift"))
}
