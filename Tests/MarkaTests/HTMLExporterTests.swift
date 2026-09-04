import Foundation
import Testing
@testable import Marka

@Test func htmlHeadingAndParagraph() {
    let html = HTMLExporter.fragment(from: "## Title\n\nSome **bold** text.\n")
    #expect(html.contains("<h2 id=\"title\">Title</h2>"))
    #expect(html.contains("<p>Some <strong>bold</strong> text.</p>"))
}

@Test func htmlEscapesMarkup() {
    let html = HTMLExporter.fragment(from: "a < b & `x > y`\n")
    #expect(html.contains("a &lt; b &amp;"))
    #expect(html.contains("<code>x &gt; y</code>"))
}

@Test func htmlLists() {
    let html = HTMLExporter.fragment(from: "- one\n- two\n\n1. first\n2. second\n")
    #expect(html.contains("<ul>\n<li>one</li>\n<li>two</li>\n</ul>"))
    #expect(html.contains("<ol>\n<li>first</li>\n<li>second</li>\n</ol>"))
}

@Test func htmlTaskList() {
    let html = HTMLExporter.fragment(from: "- [x] done\n- [ ] todo\n")
    #expect(html.contains("<input type=\"checkbox\" disabled checked> done"))
    #expect(html.contains("<input type=\"checkbox\" disabled> todo"))
}

@Test func htmlCodeFence() {
    let html = HTMLExporter.fragment(from: "```swift\nlet x = \"<hi>\"\n```\n")
    #expect(html.contains("<pre><code class=\"language-swift\">let x = &quot;&lt;hi&gt;&quot;\n</code></pre>"))
}

@Test func htmlMermaidFence() {
    let html = HTMLExporter.fragment(from: "```mermaid\ngraph TD\nA --> B\n```\n")
    #expect(html.contains("<pre class=\"mermaid\">"))
    #expect(html.contains("A --&gt; B"))
}

@Test func htmlTable() {
    let html = HTMLExporter.fragment(from: "| a | b |\n| --- | --- |\n| 1 | 2 |\n")
    #expect(html.contains("<th>a</th><th>b</th>"))
    #expect(html.contains("<td>1</td><td>2</td>"))
}

@Test func htmlMathAndLinks() {
    let html = HTMLExporter.fragment(from: "Inline $x^2$ and [docs](https://example.com).\n\n$$ E = mc^2 $$\n")
    #expect(html.contains("\\(x^2\\)"))
    #expect(html.contains("<a href=\"https://example.com\">docs</a>"))
    #expect(html.contains("<p class=\"math\">\\[E = mc^2\\]</p>"))
}

@Test func htmlBlockquoteAndRule() {
    let html = HTMLExporter.fragment(from: "> quoted line\n\n---\n")
    #expect(html.contains("<blockquote><p>quoted line</p></blockquote>"))
    #expect(html.contains("<hr>"))
}

@Test func htmlImageLine() {
    let html = HTMLExporter.fragment(from: "![shot](assets/pic.png)\n")
    #expect(html.contains("<img src=\"assets/pic.png\">"))
}

@Test func htmlDocumentIncludesMathJaxOnlyWhenNeeded() {
    let withMath = HTMLExporter.document(from: "$x$ math\n", title: "T")
    let plain = HTMLExporter.document(from: "plain\n", title: "T")
    #expect(withMath.contains("mathjax"))
    #expect(!plain.contains("mathjax"))
    #expect(plain.contains("<title>T</title>"))
}

@Test @MainActor func docxConversionProducesZipData() throws {
    let fragment = HTMLExporter.fragment(from: "# Title\n\nSome **bold** text.\n")
    let attributed = try NSAttributedString(
        data: Data(fragment.utf8),
        options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ],
        documentAttributes: nil
    )
    #expect(attributed.string.contains("Some bold text."))
    let data = try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
    )
    #expect(data.count > 500)
    #expect(data.prefix(2) == Data([0x50, 0x4b]))
}

@Test func htmlMultiLineMathBlock() {
    let html = HTMLExporter.fragment(from: "$$\nx = \\frac{a}{b}\n$$\n\ntext\n")
    #expect(html.contains("<p class=\"math\">\\[x = \\frac{a}{b}\\]</p>"))
    #expect(html.contains("<p>text</p>"))
}

@Test func htmlSkipsFrontMatter() {
    let html = HTMLExporter.fragment(from: "---\ntitle: Doc\n---\n# Heading\n")
    #expect(!html.contains("title: Doc"))
    #expect(html.contains("<h1 id=\"heading\">Heading</h1>"))
}

@Test func htmlTOCAndHeadingAnchors() {
    let html = HTMLExporter.fragment(from: "[TOC]\n\n# First Part\n\n## Sub Section\n\n# First Part\n")
    #expect(html.contains("<h1 id=\"first-part\">First Part</h1>"))
    #expect(html.contains("<h2 id=\"sub-section\">Sub Section</h2>"))
    #expect(html.contains("<h1 id=\"first-part-2\">First Part</h1>"))
    #expect(html.contains("<nav class=\"toc\">"))
    #expect(html.contains("<a href=\"#first-part\">First Part</a>"))
    #expect(html.contains("<a href=\"#sub-section\">Sub Section</a>"))
}

@Test func htmlFootnotes() {
    let html = HTMLExporter.fragment(from: "Claim[^a] and again[^b].\n\n[^a]: First note.\n[^b]: Second note.\n")
    #expect(html.contains("<sup id=\"fnref-a\"><a href=\"#fn-a\">[1]</a></sup>"))
    #expect(html.contains("<sup id=\"fnref-b\"><a href=\"#fn-b\">[2]</a></sup>"))
    #expect(html.contains("<li id=\"fn-a\">First note. <a href=\"#fnref-a\">&#8617;</a></li>"))
    #expect(!html.contains("<p>[^a]: First note.</p>"))
    #expect(html.contains("<section class=\"footnotes\">"))
}

@Test func htmlKeepsParagraphsWithPipes() {
    let html = HTMLExporter.fragment(from: "Run `ls | grep x` now.\n\nNext para.\n")
    #expect(html.contains("<p>Run <code>ls | grep x</code> now.</p>"))
    #expect(html.contains("<p>Next para.</p>"))
}

@Test func htmlTableStopsAtNextBlock() {
    let html = HTMLExporter.fragment(from: "| a | b |\n| - | - |\n| 1 | 2 |\n## Head | x\n")
    #expect(html.contains("<td>1</td><td>2</td>"))
    #expect(html.contains("<h2 id=\"head-x\">Head | x</h2>"))
}

@Test func htmlNestedInlineMarkup() {
    let html = HTMLExporter.fragment(from: "**bold `code`** and [**x**](u) and **a *b* c**\n")
    #expect(html.contains("<strong>bold <code>code</code></strong>"))
    #expect(html.contains("<a href=\"u\"><strong>x</strong></a>"))
    #expect(html.contains("<strong>a <em>b</em> c</strong>"))
}

@Test func htmlDropsBackslashEscapes() {
    let html = HTMLExporter.fragment(from: "\\*not italic\\* costs \\$5 and a\\|b\n")
    #expect(html.contains("<p>*not italic* costs $5 and a|b</p>"))
}

@Test func htmlInlineImage() {
    let html = HTMLExporter.fragment(from: "text ![alt](a.png) more\n")
    #expect(html.contains("<p>text <img src=\"a.png\" alt=\"alt\"> more</p>"))
}
