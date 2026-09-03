import Foundation
import Testing
@testable import Marka

private let sample = "# Chapter\n\nSome **bold** text with $x^2$ math.\n\n- one\n- two\n"

@Test func pandocEpubExport() throws {
    guard PandocExporter.pandocURL != nil else { return }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("marka-\(UUID().uuidString).epub")
    defer { try? FileManager.default.removeItem(at: url) }

    try PandocExporter.export(markdown: sample, to: url, format: "epub", title: "Sample", workingDirectory: nil)
    let data = try Data(contentsOf: url)
    #expect(data.count > 1000)
    #expect(data.prefix(2) == Data([0x50, 0x4b]))
}

@Test func pandocLaTeXExport() throws {
    guard PandocExporter.pandocURL != nil else { return }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("marka-\(UUID().uuidString).tex")
    defer { try? FileManager.default.removeItem(at: url) }

    try PandocExporter.export(markdown: sample, to: url, format: "latex", title: "Sample", workingDirectory: nil)
    let tex = try String(contentsOf: url, encoding: .utf8)
    #expect(tex.contains("\\documentclass"))
    #expect(tex.contains("\\textbf{bold}"))
    #expect(tex.contains("x^2"))
}

@Test func pandocFailureSurfacesStderr() {
    guard PandocExporter.pandocURL != nil else { return }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("marka-\(UUID().uuidString).epub")
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(throws: NSError.self) {
        try PandocExporter.export(markdown: "x", to: url, format: "nonsense", title: "T", workingDirectory: nil)
    }
}

@Test func pandocImportConvertsHTML() throws {
    guard PandocExporter.pandocURL != nil else { return }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("marka-\(UUID().uuidString).html")
    defer { try? FileManager.default.removeItem(at: url) }
    try "<h1>Title</h1><p>Some <strong>bold</strong> text.</p>".write(to: url, atomically: true, encoding: .utf8)

    let markdown = try PandocExporter.importMarkdown(from: url)
    #expect(markdown.contains("# Title"))
    #expect(markdown.contains("**bold**"))

    let unsupported = url.deletingPathExtension().appendingPathExtension("xyz")
    #expect(throws: NSError.self) { try PandocExporter.importMarkdown(from: unsupported) }
}
