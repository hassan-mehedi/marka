import AppKit

@MainActor
final class SidebarViewController: NSViewController {
    let outline = OutlineViewController()
    let fileTree = FileTreeViewController()
    private var picker: NSSegmentedControl!
    private var container: NSView!

    override func loadView() {
        let picker = NSSegmentedControl(
            labels: ["Outline", "Files"],
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

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 700))
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

        addChild(outline)
        addChild(fileTree)
        if ProcessInfo.processInfo.environment["MARKA_SIDEBAR"] == "files" {
            picker.selectedSegment = 1
            show(fileTree)
        } else {
            show(outline)
        }
    }

    @objc private func paneChanged() {
        if picker.selectedSegment == 0 {
            show(outline)
        } else {
            fileTree.reload()
            show(fileTree)
        }
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
