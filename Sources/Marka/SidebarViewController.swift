import AppKit

@MainActor
final class SidebarViewController: NSViewController {
    let outline = OutlineViewController()
    let fileTree = FileTreeViewController()
    let search = SearchViewController()

    var rootURL: URL? {
        didSet {
            fileTree.rootURL = rootURL
            search.rootURL = rootURL
            watcher = rootURL.map { url in
                FolderWatcher(url: url) { [weak self] in self?.fileTree.reload() }
            }
        }
    }
    private var watcher: FolderWatcher?
    private var picker: NSSegmentedControl!
    private var container: NSView!

    override func loadView() {
        let picker = NSSegmentedControl(
            labels: ["Outline", "Files", "Search"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(paneChanged)
        )
        picker.selectedSegment = 0
        picker.segmentStyle = .capsule
        picker.translatesAutoresizingMaskIntoConstraints = false
        self.picker = picker

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.container = container

        let view = OpaqueBackgroundView(frame: NSRect(x: 0, y: 0, width: 220, height: 700))
        view.color = ThemeManager.shared.current.resolvedBackground
        view.addSubview(picker)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            picker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            picker.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.didChange,
            object: nil
        )

        addChild(outline)
        addChild(fileTree)
        addChild(search)
        let savedPane = ProcessInfo.processInfo.environment["MARKA_SIDEBAR"] ?? UserDefaults.standard.string(forKey: Self.paneKey)
        switch savedPane {
        case "files":
            picker.selectedSegment = 1
            show(fileTree)
        case "search":
            picker.selectedSegment = 2
            show(search)
        default:
            show(outline)
        }
    }

    func showSearch() {
        picker.selectedSegment = 2
        paneChanged()
        search.focus()
    }

    private static let paneKey = "MarkaSidebarPane"

    @objc private func themeDidChange() {
        (view as? OpaqueBackgroundView)?.color = ThemeManager.shared.current.resolvedBackground
    }

    @objc private func paneChanged() {
        switch picker.selectedSegment {
        case 1:
            fileTree.reload()
            show(fileTree)
        case 2:
            show(search)
        default:
            show(outline)
        }
        UserDefaults.standard.set(["outline", "files", "search"][picker.selectedSegment], forKey: Self.paneKey)
    }

    private func show(_ child: NSViewController) {
        container.subviews.forEach { $0.removeFromSuperview() }
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
