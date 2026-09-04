import Testing
@testable import Marka

@Test func htmlHeadingsParagraphsAndInline() {
    let html = """
    <html><head><style>p{color:red}</style></head><body>
    <h2>Title</h2>
    <p>Some <b>bold </b>and <em>italic</em> with <code>x &lt; y</code> and a
    <a href="https://example.com">link</a>.</p>
    <p>Second&nbsp;paragraph &amp; more.</p>
    </body></html>
    """
    let expected = """
    ## Title

    Some **bold** and *italic* with `x < y` and a [link](https://example.com).

    Second paragraph & more.
    """
    #expect(HTMLToMarkdown.markdown(from: html) == expected)
}

@Test func htmlListsQuotesAndCode() {
    let html = """
    <ul><li>one</li><li>two<ol start="3"><li>three</li></ol></li></ul>
    <blockquote><p>quoted</p></blockquote>
    <pre class="language-swift"><code>let a = 1
    let b = 2</code></pre>
    <hr>
    <img src="pic.png" alt="A pic">
    """
    let expected = """
    - one
    - two
      3. three

    > quoted

    ```swift
    let a = 1
    let b = 2
    ```

    ---

    ![A pic](pic.png)
    """
    #expect(HTMLToMarkdown.markdown(from: html) == expected)
}

@Test func htmlTableBecomesPipeTable() {
    let html = "<table><tr><th>Name</th><th>Qty</th></tr><tr><td>Apple</td><td>3</td></tr></table>"
    #expect(HTMLToMarkdown.markdown(from: html) == "| Name  | Qty |\n| ----- | --- |\n| Apple | 3   |")
}

@Test func bareUrlLinksCollapseToTheUrl() {
    #expect(HTMLToMarkdown.markdown(from: "<p>See <a href=\"https://a.b\">https://a.b</a></p>") == "See https://a.b")
    #expect(HTMLToMarkdown.decodeEntities("&#65;&#x42;&unknown; &lt;") == "AB&unknown; <")
}

@Test func htmlToMarkdownClosesUnterminatedCells() {
    let markdown = HTMLToMarkdown.markdown(from: "<table><tr><td>a<td>b</tr></table><p>after</p>")
    #expect(markdown.contains("| a   | b   |"))
    #expect(markdown.hasSuffix("after"))
}

@Test func htmlToMarkdownReadsLanguageFromCodeTag() {
    let markdown = HTMLToMarkdown.markdown(from: "<pre><code class=\"language-swift\">let a = 1</code></pre>")
    #expect(markdown.hasPrefix("```swift\nlet a = 1\n```"))
}

@Test func htmlToMarkdownMovesLeadingSpaceOutOfEmphasis() {
    #expect(HTMLToMarkdown.markdown(from: "text<b> bold</b>") == "text **bold**")
}
