import Foundation

// The Markdown files under one folder, listed once and kept until the folder
// changes. Quick Open and folder search share it, so neither walks the tree
// on every keystroke.
@MainActor
final class ProjectIndex {
    struct Entry: Sendable {
        let url: URL
        let displayPath: String
        // Lowercased display path, ready for fuzzy matching.
        let searchKey: [Character]
    }

    private static var indexes: [URL: ProjectIndex] = [:]

    static func index(for root: URL) -> ProjectIndex {
        let key = root.standardizedFileURL
        if let existing = indexes[key] { return existing }
        let index = ProjectIndex(root: key)
        indexes[key] = index
        return index
    }

    let root: URL
    private var cached: [Entry]?
    private var loading: Task<[Entry], Never>?
    private var watcher: FolderWatcher?

    private init(root: URL) {
        self.root = root
        watcher = FolderWatcher(url: root) { [weak self] in self?.invalidate() }
    }

    func entries() async -> [Entry] {
        if let cached { return cached }
        if let loading { return await loading.value }
        let root = root
        let task = Task.detached(priority: .userInitiated) {
            ProjectFiles.list(under: root).map { url in
                let path = ProjectFiles.relativePath(of: url, to: root)
                return Entry(url: url, displayPath: path, searchKey: Array(path.lowercased()))
            }
        }
        loading = task
        let result = await task.value
        if loading == task {
            cached = result
            loading = nil
        }
        return result
    }

    func invalidate() {
        cached = nil
        loading = nil
    }
}
