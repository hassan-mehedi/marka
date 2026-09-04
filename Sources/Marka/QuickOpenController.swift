import AppKit

// Cmd+Shift+O: fuzzy file switcher over the document's folder, or over the
// recent documents when the document has no folder yet.
@MainActor
final class QuickOpenController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QuickOpenController()

    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var root: URL?
    private var candidates: [ProjectIndex.Entry] = []
    private var results: [ProjectIndex.Entry] = []
    private var listing: Task<Void, Never>?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = true
        super.init(window: panel)
        panel.contentView = makeContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(root: URL?) {
        self.root = root
        searchField.stringValue = ""
        listing?.cancel()
        if let root {
            // Walking a big folder takes a while; the panel opens at once and
            // fills in when the listing lands. The index keeps it for next time.
            candidates = []
            filter()
            listing = Task { [weak self] in
                let entries = await ProjectIndex.index(for: root).entries()
                guard !Task.isCancelled, let self else { return }
                candidates = entries
                filter()
            }
        } else {
            candidates = NSDocumentController.shared.recentDocumentURLs.map { url in
                let name = url.lastPathComponent
                return ProjectIndex.Entry(url: url, displayPath: name, searchKey: Array(name.lowercased()))
            }
            filter()
        }
        guard let window else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.maxY - window.frame.height - frame.height * 0.2
            ))
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
    }

    private func makeContent() -> NSView {
        let searchField = NSSearchField()
        searchField.placeholderString = "Open file…"
        searchField.font = .systemFont(ofSize: 18)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        self.searchField = searchField

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: .init("file")))
        tableView.headerView = nil
        tableView.rowHeight = 40
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected)
        tableView.backgroundColor = .clear
        self.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSVisualEffectView()
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active
        content.addSubview(searchField)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        return content
    }

    func controlTextDidChange(_ notification: Notification) {
        filter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            select(row: tableView.selectedRow + 1)
        case #selector(NSResponder.moveUp(_:)):
            select(row: tableView.selectedRow - 1)
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            window?.orderOut(nil)
        default:
            return false
        }
        return true
    }

    private func select(row: Int) {
        guard !results.isEmpty else { return }
        let clamped = min(max(row, 0), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
    }

    private func filter() {
        let query = Array(searchField.stringValue.lowercased())
        if query.isEmpty {
            results = Array(candidates.prefix(50))
        } else {
            results = candidates
                .compactMap { entry -> (ProjectIndex.Entry, Int)? in
                    ProjectFiles.fuzzyScore(query: query, key: entry.searchKey).map { (entry, $0) }
                }
                .sorted { $0.1 > $1.1 }
                .prefix(50)
                .map(\.0)
        }
        tableView.reloadData()
        select(row: 0)
    }

    @objc private func openSelected() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : tableView.clickedRow
        guard results.indices.contains(row) else { return }
        let url = results[row].url
        window?.orderOut(nil)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = results[row]
        let cell = LabelCellView.dequeue(from: tableView, identifier: "file", showsDetail: true, indent: 8)
        cell.label.stringValue = entry.url.lastPathComponent
        cell.label.font = .systemFont(ofSize: 13, weight: .medium)
        let folder: String
        if root != nil {
            folder = entry.displayPath.contains("/") ? String(entry.displayPath.dropLast(entry.url.lastPathComponent.count + 1)) : ""
        } else {
            folder = entry.url.deletingLastPathComponent().path
        }
        cell.detail.stringValue = folder
        cell.detail.isHidden = folder.isEmpty
        return cell
    }
}
