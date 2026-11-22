import AppKit

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Entry: NSObject {
        let title: String
        let symbol: String
        let source: AppState.Source?
        var children: [Entry]
        var count: Int
        init(_ title: String, symbol: String = "", source: AppState.Source? = nil, count: Int = 0, children: [Entry] = []) {
            self.title = title; self.symbol = symbol; self.source = source; self.count = count; self.children = children
        }
    }
    private let state: AppState
    let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let open = NSButton(title: "打开文件夹…", target: nil, action: nil)
    private var groups: [Entry] = []
    private var syncing = false
    var onOpen: (() -> Void)?

    init(state: AppState) { self.state = state; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        view = material
        let column = NSTableColumn(identifier: .init("sidebar"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.rowHeight = 36
        outline.style = .sourceList
        outline.indentationPerLevel = 0
        outline.backgroundColor = .clear
        outline.floatsGroupRows = false
        outline.setAccessibilityLabel("图库导航")
        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        open.bezelStyle = .rounded
        open.controlSize = .small
        open.font = .systemFont(ofSize: 12)
        open.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        open.imagePosition = .imageLeading
        open.alignment = .left
        open.target = self
        open.action = #selector(openFiles)
        open.translatesAutoresizingMaskIntoConstraints = false
        open.toolTip = "打开图片或文件夹（⌘O）"
        view.addSubview(scroll); view.addSubview(open)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: open.topAnchor, constant: -14),
            open.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            open.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            open.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            open.heightAnchor.constraint(equalToConstant: 30)
        ])
        reload()
    }
    @objc private func openFiles() { onOpen?() }

    func reload() {
        guard isViewLoaded else { return }
        syncing = true
        groups = [
            Entry("个人收藏", children: [
                Entry("最近打开", symbol: "clock", source: .recent, count: state.recentPaths.count),
                Entry("个人收藏", symbol: "heart", source: .favorites, count: state.favoritePaths.count)
            ]),
            Entry("文件夹", children: [Entry("山海之间", symbol: "folder", source: .demo, count: 12)] +
                  state.folders.map { url in
                      Entry(url.lastPathComponent, symbol: "folder", source: .folder(url),
                            count: state.source == .folder(url) ? state.allPhotos.count : -1)
                  })
        ]
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        for row in 0..<outline.numberOfRows {
            if let entry = outline.item(atRow: row) as? Entry, entry.source == state.source {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                break
            }
        }
        syncing = false
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Entry)?.children.count ?? groups.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Entry)?.children[index] ?? groups[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! Entry).children.isEmpty }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { (item as! Entry).source == nil }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as! Entry).source != nil }
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { (item as! Entry).source == nil ? 42 : 36 }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let entry = item as! Entry
        if entry.source == nil { return label(entry.title, size: 11, color: .secondaryLabelColor, weight: .medium) }
        let cell = NSTableCellView()
        let name = label(entry.title, size: 13)
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
        image.contentTintColor = entry.source == .recent ? .labelColor : .controlAccentColor
        let count = label(entry.count < 0 ? "" : "\(entry.count)", size: 11, color: .secondaryLabelColor)
        count.alignment = .right
        for v in [image, name, count] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -5),
            count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            count.centerYAnchor.constraint(equalTo: cell.centerYAnchor), count.widthAnchor.constraint(equalToConstant: 28)
        ])
        cell.textField = name
        cell.imageView = image
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let entry = outline.item(atRow: outline.selectedRow) as? Entry, let source = entry.source else { return }
        switch source {
        case .demo: state.showDemo()
        case .recent: state.showRecent()
        case .favorites: state.showFavorites()
        case .folder(let url): state.open([url])
        case .files: break
        }
    }
}
