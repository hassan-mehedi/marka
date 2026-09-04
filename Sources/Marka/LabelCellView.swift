import AppKit

// One reusable row for the sidebar lists and Quick Open: an optional icon,
// a label and an optional detail line under it. Rows are dequeued by
// identifier so scrolling does not rebuild views and constraints.
final class LabelCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let icon = NSImageView()
    private var leading: NSLayoutConstraint!

    var indent: CGFloat {
        get { leading.constant }
        set { leading.constant = newValue }
    }

    init(identifier: NSUserInterfaceItemIdentifier, showsIcon: Bool, showsDetail: Bool, indent: CGFloat) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        let text = NSStackView(views: showsDetail ? [label, detail] : [label])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: showsIcon ? [icon, text] : [text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        leading = row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent)
        var constraints = [
            leading!,
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if showsIcon {
            constraints += [
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func dequeue(
        from tableView: NSTableView,
        identifier: String,
        showsIcon: Bool = false,
        showsDetail: Bool = false,
        indent: CGFloat = 2
    ) -> LabelCellView {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? LabelCellView {
            return reused
        }
        return LabelCellView(identifier: id, showsIcon: showsIcon, showsDetail: showsDetail, indent: indent)
    }
}
