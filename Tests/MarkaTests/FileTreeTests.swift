import AppKit
import Foundation
import Testing
@testable import Marka

@Test @MainActor func fileTreeListsMarkdownFilesAndFolders() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("marka-tree-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
    try "a".write(to: root.appendingPathComponent("beta.md"), atomically: true, encoding: .utf8)
    try "b".write(to: root.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
    try "c".write(to: root.appendingPathComponent("skip.png"), atomically: true, encoding: .utf8)
    try "d".write(to: root.appendingPathComponent("notes/inner.md"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let controller = FileTreeViewController()
    controller.loadView()
    controller.rootURL = root

    let outlines = controller.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSOutlineView }
    let outline = try #require(outlines.first)
    #expect(outline.numberOfRows == 3)

    let names = (0..<outline.numberOfRows).compactMap {
        (outline.item(atRow: $0) as? FileTreeViewController.Node)?.url.lastPathComponent
    }
    #expect(names == ["notes", "alpha.txt", "beta.md"])

    outline.expandItem(outline.item(atRow: 0))
    #expect(outline.numberOfRows == 4)
    let inner = (outline.item(atRow: 1) as? FileTreeViewController.Node)?.url.lastPathComponent
    #expect(inner == "inner.md")
}
