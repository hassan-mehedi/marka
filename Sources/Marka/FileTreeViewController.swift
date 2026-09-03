import AppKit
import UniformTypeIdentifiers

@MainActor
final class FileTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        let url: URL
        let isDirectory: Bool
        var children: [Node]?

        init(url: URL, isDirectory: Bool) {
            self.url = url
            self.isDirectory = isDirectory
        }
    }

    private static let fileExtensions: Set<String> = ["md", "markdown", "txt"]

    var rootURL: URL? {
        didSet {
            guard rootURL != oldValue else { return }
            reload()
        }
    }

    private var rootNodes: [Node] = []
    private var outlineView: NSOutlineView!
    private var placeholder: NSTextField!

    override func loadView() {
        let outlineView = NSOutlineView()
        let column = NSTableColumn(identifier: .init("file"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.style = .sourceList
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        self.outlineView = outlineView

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 700))
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        outlineView.backgroundColor = .clear

        let placeholder = NSTextField(wrappingLabelWithString: "Save the document to browse its folder.")
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        self.placeholder = placeholder

        let container = NSView(frame: scrollView.frame)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(placeholder)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            placeholder.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            placeholder.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            placeholder.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        view = container
        reload()
    }

    func reload() {
        guard isViewLoaded else { return }
        rootNodes = rootURL.map(Self.children(of:)) ?? []
        placeholder.isHidden = rootURL != nil
        outlineView.reloadData()
    }

    private static func children(of url: URL) -> [Node] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .compactMap { child -> Node? in
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDirectory, !fileExtensions.contains(child.pathExtension.lowercased()) {
                    return nil
                }
                return Node(url: child, isDirectory: isDirectory)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }

    private func nodes(for item: Any?) -> [Node] {
        guard let node = item as? Node else { return rootNodes }
        if node.children == nil {
            node.children = node.isDirectory ? Self.children(of: node.url) : []
        }
        return node.children ?? []
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        nodes(for: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        nodes(for: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }

        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: node.url.path)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField(labelWithString: node.url.lastPathComponent)
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false

        let cell = NSTableCellView()
        cell.addSubview(icon)
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: node.url, display: true) { _, _, _ in }
    }
}
