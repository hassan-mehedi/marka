import Foundation

// Files under the document's folder that the sidebar and Quick Open care about.
enum ProjectFiles {
    static let extensions: Set<String> = ["md", "markdown", "txt"]
    static let skippedDirectories: Set<String> = ["node_modules", ".git", ".build", "build", "Pods", "DerivedData"]
    static let fileLimit = 5000

    nonisolated static func list(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else { continue }
            files.append(url)
            if files.count >= fileLimit { break }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    nonisolated static func relativePath(of url: URL, to root: URL) -> String {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else { return url.path }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }

    // Subsequence match with a score that favours runs and word starts. nil
    // when the query does not match at all. Every occurrence of the first
    // query character is tried as a start so "setup" finds the run in
    // "docs/guides/setup.md" instead of scattered letters.
    nonisolated static func fuzzyScore(query: String, candidate: String) -> Int? {
        let query = Array(query.lowercased())
        guard !query.isEmpty else { return 0 }
        let text = Array(candidate.lowercased())
        var best: Int?
        for start in text.indices where text[start] == query[0] {
            guard let score = greedyScore(query: query, text: text, from: start) else { break }
            best = max(best ?? Int.min, score)
        }
        return best
    }

    private nonisolated static func greedyScore(query: [Character], text: [Character], from start: Int) -> Int? {
        var score = 0
        var queryIndex = 0
        var previousMatch = -2
        for index in start..<text.count where queryIndex < query.count && text[index] == query[queryIndex] {
            score += 1
            if index == previousMatch + 1 { score += 3 }
            if index == 0 || "/_-. ".contains(text[index - 1]) { score += 4 }
            previousMatch = index
            queryIndex += 1
        }
        guard queryIndex == query.count else { return nil }
        return score - (text.count - query.count) / 8
    }

    struct Match: Equatable {
        var url: URL
        var line: Int
        var offset: Int
        var preview: String
    }

    // Case-insensitive substring search across the folder, capped so a huge
    // tree cannot flood the sidebar.
    nonisolated static func search(_ query: String, under root: URL, limit: Int = 500) -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        var matches: [Match] = []
        for url in list(under: root) {
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
            var offset = 0
            var lineNumber = 0
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lineNumber += 1
                let lineText = String(line)
                if lineText.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    matches.append(Match(url: url, line: lineNumber, offset: offset, preview: lineText.trimmingCharacters(in: .whitespaces)))
                    if matches.count >= limit { return matches }
                }
                offset += (lineText as NSString).length + 1
            }
        }
        return matches
    }
}
