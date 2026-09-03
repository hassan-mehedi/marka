import AppKit

// Hosts the split view under a custom tab strip. The stock tab bar is kept
// hidden; windows still live in the native tab group, so the Window menu and
// the tab shortcuts keep working and only the strip is drawn here.
@MainActor
final class DocumentContentViewController: NSViewController {
    let split: NSSplitViewController
    private let tabBar = TabBarView()
    private var tabBarHeight: NSLayoutConstraint!

    init(split: NSSplitViewController) {
        self.split = split
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        tabBar.onSelect = { window in
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        tabBar.onClose = { window in window.performClose(nil) }
        tabBar.onAdd = { NSDocumentController.shared.newDocument(nil) }

        addChild(split)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        split.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        view.addSubview(split.view)
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarHeight,
            split.view.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            split.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view

        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification, NSWindow.didUpdateNotification] {
            center.addObserver(self, selector: #selector(windowsDidChange), name: name, object: nil)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    @objc private func windowsDidChange() {
        refresh()
    }

    private func refresh() {
        guard let window = view.window else { return }
        // Reading tabGroup on a lone window gives it a group of its own, and
        // later windows then open beside it instead of joining it as tabs.
        let group = window.tabbedWindows == nil ? nil : window.tabGroup
        let windows = (group?.windows ?? [window]).filter { $0.contentViewController != nil }
        // AppKit keeps the stock tab bar visible while a group has two or more
        // tabs; it is the window's only bottom title bar accessory, so hide it.
        for accessory in window.titlebarAccessoryViewControllers where accessory.layoutAttribute == .bottom {
            accessory.isHidden = true
        }
        let showsTabs = windows.count > 1
        tabBar.isHidden = !showsTabs
        tabBarHeight.constant = showsTabs ? TabBarView.height : 0
        let selected = group?.selectedWindow ?? window
        tabBar.tabs = windows.map {
            TabBarView.Tab(window: $0, title: $0.title, isEdited: $0.isDocumentEdited, isSelected: $0 === selected)
        }
    }
}

@MainActor
final class TabBarView: NSView {
    struct Tab: Equatable {
        let window: NSWindow
        let title: String
        let isEdited: Bool
        let isSelected: Bool

        static func == (lhs: Tab, rhs: Tab) -> Bool {
            lhs.window === rhs.window && lhs.title == rhs.title && lhs.isEdited == rhs.isEdited && lhs.isSelected == rhs.isSelected
        }
    }

    static let height: CGFloat = 36

    var tabs: [Tab] = [] {
        didSet {
            if tabs != oldValue { needsDisplay = true }
        }
    }
    var onSelect: ((NSWindow) -> Void)?
    var onClose: ((NSWindow) -> Void)?
    var onAdd: (() -> Void)?

    private static let tabHeight: CGFloat = 26
    private static let maxTabWidth: CGFloat = 220
    private static let minTabWidth: CGFloat = 72
    private static let gap: CGFloat = 6
    private static let inset: CGFloat = 10
    private static let addButtonWidth: CGFloat = 26
    private static let closeButtonSize: CGFloat = 16
    private static let radius: CGFloat = 7

    private var hoveredIndex: Int?
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange), name: ThemeManager.didChange, object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    @objc private func themeDidChange() {
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    private var addButtonRect: NSRect {
        let y = (bounds.height - Self.tabHeight) / 2
        return NSRect(x: bounds.width - Self.inset - Self.addButtonWidth, y: y, width: Self.addButtonWidth, height: Self.tabHeight)
    }

    private func tabRects() -> [NSRect] {
        guard !tabs.isEmpty else { return [] }
        let available = addButtonRect.minX - Self.gap - Self.inset
        let count = CGFloat(tabs.count)
        let width = max(Self.minTabWidth, min(Self.maxTabWidth, (available - Self.gap * (count - 1)) / count))
        let y = (bounds.height - Self.tabHeight) / 2
        return (0..<tabs.count).map { index in
            NSRect(x: Self.inset + CGFloat(index) * (width + Self.gap), y: y, width: width, height: Self.tabHeight)
        }
    }

    private func closeButtonRect(in tab: NSRect) -> NSRect {
        NSRect(
            x: tab.minX + 6,
            y: tab.midY - Self.closeButtonSize / 2,
            width: Self.closeButtonSize,
            height: Self.closeButtonSize
        )
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        tabRects().firstIndex { $0.contains(point) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ThemeManager.shared.current
        let background = theme.resolvedBackground
        let isDark = background.brightness < 0.5
        let strip = background.blended(withFraction: isDark ? 0.35 : 0.06, of: .black) ?? background
        let border = theme.resolvedMarker.withAlphaComponent(0.55)

        strip.setFill()
        bounds.fill()

        for (index, tab) in tabs.enumerated() {
            let rect = tabRects()[index].insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius)
            path.lineWidth = 1
            if tab.isSelected {
                background.setFill()
                path.fill()
                border.setStroke()
            } else {
                if index == hoveredIndex {
                    (background.blended(withFraction: 0.5, of: strip) ?? strip).setFill()
                    path.fill()
                }
                border.withAlphaComponent(0.3).setStroke()
            }
            path.stroke()

            let showsClose = tab.isSelected || index == hoveredIndex
            var titleRect = rect.insetBy(dx: 10, dy: 0)
            if showsClose {
                drawCloseGlyph(in: closeButtonRect(in: rect), color: theme.resolvedSecondary)
                titleRect.origin.x += Self.closeButtonSize + 4
                titleRect.size.width -= Self.closeButtonSize + 4
            }
            drawTitle(tab, in: titleRect, color: tab.isSelected ? theme.resolvedText : theme.resolvedSecondary)
        }

        drawAddGlyph(in: addButtonRect, color: theme.resolvedSecondary)
    }

    private func drawTitle(_ tab: Tab, in rect: NSRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: 12, weight: tab.isSelected ? .medium : .regular)
        let title = NSAttributedString(
            string: tab.isEdited ? "\(tab.title) •" : tab.title,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        )
        let height = title.size().height
        let textRect = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        title.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawCloseGlyph(in rect: NSRect, color: NSColor) {
        let glyph = rect.insetBy(dx: 5, dy: 5)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: glyph.minX, y: glyph.minY))
        path.line(to: NSPoint(x: glyph.maxX, y: glyph.maxY))
        path.move(to: NSPoint(x: glyph.maxX, y: glyph.minY))
        path.line(to: NSPoint(x: glyph.minX, y: glyph.maxY))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawAddGlyph(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX - 5, y: rect.midY))
        path.line(to: NSPoint(x: rect.midX + 5, y: rect.midY))
        path.move(to: NSPoint(x: rect.midX, y: rect.midY - 5))
        path.line(to: NSPoint(x: rect.midX, y: rect.midY + 5))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    override func mouseMoved(with event: NSEvent) {
        let index = tabIndex(at: convert(event.locationInWindow, from: nil))
        if index != hoveredIndex {
            hoveredIndex = index
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if addButtonRect.contains(point) {
            onAdd?()
            return
        }
        guard let index = tabIndex(at: point) else {
            super.mouseDown(with: event)
            return
        }
        let tab = tabs[index]
        if closeButtonRect(in: tabRects()[index]).contains(point), tab.isSelected || index == hoveredIndex {
            onClose?(tab.window)
        } else {
            onSelect?(tab.window)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2,
              let index = tabIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        onClose?(tabs[index].window)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSColor {
    var brightness: CGFloat {
        guard let rgb = usingColorSpace(.deviceRGB) else { return 1 }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }
}
