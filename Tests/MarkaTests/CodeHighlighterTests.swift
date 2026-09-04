import Foundation
import SwiftTreeSitter
import Testing
@testable import Marka

@Test func inputEditCoversTheChangedSpan() {
    let edit = CodeHighlighter.edit(from: "let x = 1\nprint(x)", to: "let x = 12\nprint(x)")
    #expect(edit.startByte == 9 * 2)
    #expect(edit.oldEndByte == 9 * 2)
    #expect(edit.newEndByte == 10 * 2)
    #expect(edit.startPoint.row == 0 && edit.startPoint.column == 18)
    let multiline = CodeHighlighter.edit(from: "a\nb\nc", to: "a\nbX\nc")
    #expect(multiline.startPoint.row == 1 && multiline.startPoint.column == 2)
    #expect(multiline.newEndPoint.row == 1 && multiline.newEndPoint.column == 4)
}

@Test @MainActor func incrementalParseMatchesFreshParse() throws {
    let first = "let x = 1\nprint(x)"
    let second = "let x = 12\nprint(x)\nlet y = \"s\""
    let start = try #require(CodeHighlighter.shared.parse(first, language: "swift", previous: nil))
    let incremental = try #require(CodeHighlighter.shared.parse(second, language: "swift", previous: start))
    let fresh = try #require(CodeHighlighter.shared.parse(second, language: "swift", previous: nil))
    let describe = { (parse: CodeHighlighter.Parse) in parse.tokens.map { "\($0.range.location):\($0.range.length):\($0.name)" } }
    #expect(describe(incremental) == describe(fresh))
    #expect(!fresh.tokens.isEmpty)
}
