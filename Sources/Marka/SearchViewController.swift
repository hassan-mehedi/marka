import AppKit

// Sidebar pane that searches every Markdown file under the document's folder.
@MainActor
final class SearchViewController: NSViewController, NSSearchFieldDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class FileGroup {
        let url: URL
        let matches: [ProjectFiles.Match]
        init(url: URL, matches: [ProjectFiles.Match]) {
            self.url = url
            self.matches = matches
        }
    }

    var rootURL: URL?
    var onSelect: ((ProjectFiles.Match) -> Void)?
    private(set) var groups: [FileGroup] = []
    private var searchField: NSSearchField!
    private var outlineView: NSOutlineView!
    private var statusLabel: NSTextField!
    private var searchGeneration = 0

    override func loadView() {
        let searchField = NSSearchField()
        searchField.placeholderString = "Find in folder"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        self.searchField = searchField

        let outlineView = NSOutlineView()
        let column = NSTableColumn(identifier: .init("match"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.backgroundColor = .clear
        self.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel = statusLabel

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 700))
        container.addSubview(searchField)
        container.addSubview(statusLabel)
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    func focus() {
        view.window?.makeFirstResponder(searchField)
    }

    func search(_ query: String) {
        searchField.stringValue = query
        runSearch()
    }

    func controlTextDidChange(_ notification: Notification) {
        runSearch()
    }

    func runSearch() {
        let query = searchField.stringValue
        searchGeneration += 1
        let generation = searchGeneration
        guard let rootURL, query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            show([], status: rootURL == nil ? "Save the document to search its folder." : "")
            return
        }
        statusLabel.stringValue = "Searching…"
        Task.detached(priority: .userInitiated) {
            let matches = ProjectFiles.search(query, under: rootURL)
            await MainActor.run {
                guard generation == self.searchGeneration else { return }
                self.show(matches, status: matches.isEmpty
                    ? "No matches"
                    : "\(matches.count) match\(matches.count == 1 ? "" : "es") in \(Set(matches.map(\.url)).count) file\(Set(matches.map(\.url)).count == 1 ? "" : "s")")
            }
        }
    }

    func show(_ matches: [ProjectFiles.Match], status: String) {
        var order: [URL] = []
        var byFile: [URL: [ProjectFiles.Match]] = [:]
        for match in matches {
            if byFile[match.url] == nil { order.append(match.url) }
            byFile[match.url, default: []].append(match)
        }
        groups = order.map { FileGroup(url: $0, matches: byFile[$0] ?? []) }
        statusLabel.stringValue = status
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let group = item as? FileGroup else { return groups.count }
        return group.matches.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let group = item as? FileGroup else { return groups[index] }
        return group.matches[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is FileGroup
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let field: NSTextField
        if let group = item as? FileGroup {
            let name = rootURL.map { ProjectFiles.relativePath(of: group.url, to: $0) } ?? group.url.lastPathComponent
            field = NSTextField(labelWithString: name)
            field.font = .systemFont(ofSize: 12, weight: .semibold)
        } else if let match = item as? ProjectFiles.Match {
            field = NSTextField(labelWithString: "\(match.line): \(match.preview)")
            field.font = .systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
        } else {
            return nil
        }
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        if let group = outlineView.item(atRow: row) as? FileGroup {
            if outlineView.isItemExpanded(group) { outlineView.collapseItem(group) } else { outlineView.expandItem(group) }
            return
        }
        guard let match = outlineView.item(atRow: row) as? ProjectFiles.Match else { return }
        onSelect?(match)
    }
}
