import AppKit

struct OutlineItem: Equatable {
    let level: Int
    let title: String
    let location: Int
}

@MainActor
final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((Int) -> Void)?
    private var items: [OutlineItem] = []
    private var tableView: NSTableView!

    func update(_ items: [OutlineItem]) {
        guard items != self.items else { return }
        self.items = items
        if isViewLoaded {
            tableView.reloadData()
        }
    }

    override func loadView() {
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: .init("title")))
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        self.tableView = tableView

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 700))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        view = scrollView
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let field = NSTextField(labelWithString: item.title)
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 12, weight: item.level == 1 ? .semibold : .regular)
        field.translatesAutoresizingMaskIntoConstraints = false

        let cell = NSTableCellView()
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: CGFloat(4 + (item.level - 1) * 12)),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        onSelect?(items[row].location)
    }
}
