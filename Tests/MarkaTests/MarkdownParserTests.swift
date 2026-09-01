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

@Test func fenceRegions() {
    let text = "before\n```\ncode line\n```\nafter"
    let fences = MarkdownParser.fences(in: text)
    #expect(fences.delimiterLines.count == 2)
    #expect(fences.contentRanges.count == 1)
    let content = (text as NSString).substring(with: fences.contentRanges[0])
    #expect(content == "code line\n")
}

@Test func unterminatedFenceRunsToEnd() {
    let text = "```\ncode"
    let fences = MarkdownParser.fences(in: text)
    #expect(fences.contentRanges.count == 1)
    let content = (text as NSString).substring(with: fences.contentRanges[0])
    #expect(content == "code")
}
