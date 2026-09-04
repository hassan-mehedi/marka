import Foundation
import Testing
@testable import Marka

private func makeTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("marka-project-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/guides"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
    try "# Intro\nHello World\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "setup steps\nhello again\n".write(to: root.appendingPathComponent("docs/guides/setup.md"), atomically: true, encoding: .utf8)
    try "hello".write(to: root.appendingPathComponent("node_modules/pkg/skip.md"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
    return root
}

@Test func projectFileListingSkipsNoiseAndSorts() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = ProjectFiles.list(under: root).map { ProjectFiles.relativePath(of: $0, to: root) }
    #expect(files == ["docs/guides/setup.md", "README.md"])
}

@Test func fuzzyScorePrefersRunsAndWordStarts() {
    #expect(ProjectFiles.fuzzyScore(query: "xyz", candidate: "docs/setup.md") == nil)
    let setup = ProjectFiles.fuzzyScore(query: "setup", candidate: "docs/guides/setup.md")!
    let scattered = ProjectFiles.fuzzyScore(query: "setup", candidate: "some/extra/tiny/user/page.md")!
    #expect(setup > scattered)
    #expect(ProjectFiles.fuzzyScore(query: "", candidate: "anything") == 0)
}

@Test func folderSearchReportsLineAndOffset() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let matches = ProjectFiles.search("hello", under: root)
    #expect(matches.count == 2)
    let setup = matches.first { $0.url.lastPathComponent == "setup.md" }
    #expect(setup?.line == 2)
    #expect(setup?.offset == 12)
    #expect(setup?.preview == "hello again")
    #expect(ProjectFiles.search("  ", under: root).isEmpty)
}

@Test func searchReportsLineNumbersAndOffsetsPerMatchingLine() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.md")
    try "first\r\nsecond Needle needle\n\n  needle at end".write(to: file, atomically: true, encoding: .utf8)
    let matches = ProjectFiles.search("needle", in: [file])
    #expect(matches.map(\.line) == [2, 4])
    #expect(matches.map(\.offset) == [6, 28])
    #expect(matches.map(\.preview) == ["second Needle needle", "needle at end"])
    #expect(ProjectFiles.search("needle", under: folder).map(\.offset) == matches.map(\.offset))
}

@Test func fuzzyScoreWithPrecomputedKeyMatchesStringVersion() {
    let candidate = "docs/guides/setup.md"
    #expect(ProjectFiles.fuzzyScore(query: "setup", candidate: candidate)
        == ProjectFiles.fuzzyScore(query: Array("setup"), key: Array(candidate.lowercased())))
}
