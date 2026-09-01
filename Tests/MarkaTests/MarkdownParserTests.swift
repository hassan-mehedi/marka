import Foundation
import Testing
@testable import Marka

@Test func headingLevelAndMarker() {
    let kind = MarkdownParser.blockKind(of: "## Title")
    #expect(kind == .heading(level: 2, marker: NSRange(location: 0, length: 3)))
}

@Test func horizontalRuleBeatsList() {
    #expect(MarkdownParser.blockKind(of: "---") == .horizontalRule)
    guard case .listItem = MarkdownParser.blockKind(of: "- item") else {
        Issue.record("expected list item")
        return
    }
}

@Test func orderedListItem() {
    guard case let .listItem(marker) = MarkdownParser.blockKind(of: "12. item") else {
        Issue.record("expected list item")
        return
    }
    #expect(marker == NSRange(location: 0, length: 4))
}

@Test func blockquoteMarker() {
    #expect(MarkdownParser.blockKind(of: "> quoted") == .blockquote(marker: NSRange(location: 0, length: 2)))
}

@Test func boldAndCodeSpans() {
    let spans = MarkdownParser.inlineSpans(in: "a **b** and `c`")
    #expect(spans.count == 2)
    #expect(spans[0].kind == .bold)
    #expect(spans[0].content == NSRange(location: 4, length: 1))
    #expect(spans[1].kind == .code)
}

@Test func codeSpanProtectsItsContent() {
    let spans = MarkdownParser.inlineSpans(in: "`**not bold**`")
    #expect(spans.count == 1)
    #expect(spans[0].kind == .code)
}

@Test func boldItalicWinsOverBold() {
    let spans = MarkdownParser.inlineSpans(in: "***both***")
    #expect(spans.count == 1)
    #expect(spans[0].kind == .boldItalic)
}

@Test func linkSpanCapturesURL() {
    let spans = MarkdownParser.inlineSpans(in: "see [docs](https://example.com) here")
    #expect(spans.count == 1)
    #expect(spans[0].kind == .link(url: "https://example.com"))
}

@Test func taskListItemDetection() {
    guard case let .taskListItem(marker, box, checked) = MarkdownParser.blockKind(of: "- [x] done") else {
        Issue.record("expected task list item")
        return
    }
    #expect(marker == NSRange(location: 0, length: 2))
    #expect(box == NSRange(location: 2, length: 3))
    #expect(checked)
}

@Test func uncheckedTaskItem() {
    guard case let .taskListItem(_, _, checked) = MarkdownParser.blockKind(of: "- [ ] todo") else {
        Issue.record("expected task list item")
        return
    }
    #expect(!checked)
}

@Test func continuationMarkers() {
    #expect(MarkdownParser.continuationMarker(afterLine: "- item") == "- ")
    #expect(MarkdownParser.continuationMarker(afterLine: "  * item") == "  * ")
    #expect(MarkdownParser.continuationMarker(afterLine: "12. item") == "13. ")
    #expect(MarkdownParser.continuationMarker(afterLine: "3) item") == "4) ")
    #expect(MarkdownParser.continuationMarker(afterLine: "- [x] done") == "- [ ] ")
    #expect(MarkdownParser.continuationMarker(afterLine: "plain text") == nil)
}

@Test func emptyListItemDetection() {
    #expect(MarkdownParser.isEmptyListItem("- "))
    #expect(MarkdownParser.isEmptyListItem("- [ ] "))
    #expect(MarkdownParser.isEmptyListItem("2. "))
    #expect(!MarkdownParser.isEmptyListItem("- item"))
    #expect(!MarkdownParser.isEmptyListItem("plain"))
}

@Test func fenceRegions() {
    let text = "before\n```swift\ncode line\n```\nafter"
    let fences = MarkdownParser.fences(in: text)
    #expect(fences.delimiterLines.count == 2)
    #expect(fences.blocks.count == 1)
    #expect(fences.blocks[0].language == "swift")
    let content = (text as NSString).substring(with: fences.blocks[0].range)
    #expect(content == "code line\n")
}

@Test func unterminatedFenceRunsToEnd() {
    let text = "```\ncode"
    let fences = MarkdownParser.fences(in: text)
    #expect(fences.blocks.count == 1)
    #expect(fences.blocks[0].language.isEmpty)
    let content = (text as NSString).substring(with: fences.blocks[0].range)
    #expect(content == "code")
}

@Test @MainActor func treeSitterHighlightsSwiftCode() {
    let tokens = CodeHighlighter.shared.highlights(for: "let x = \"hi\" // note\n", language: "swift")
    #expect(!tokens.isEmpty)
    let names = Set(tokens.map { String($0.name.split(separator: ".").first ?? "") })
    #expect(names.contains("keyword"))
    #expect(names.contains("comment"))
}

@Test @MainActor func unknownLanguageYieldsNoTokens() {
    let tokens = CodeHighlighter.shared.highlights(for: "let x = 1", language: "brainfuck")
    #expect(tokens.isEmpty)
}
