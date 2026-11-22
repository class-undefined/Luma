import AppKit
import LumaCore

final class WorkspaceView: FlippedView {
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
}

final class WindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let state: AppState
    let root = DropView(frame: .zero)
    let workspace = WorkspaceView(frame: .zero)
    let sidebar: SidebarViewController
    let gallery: GalleryViewController
    let empty = EmptyView(frame: .zero)
    let status: StatusBar
    let search = NSSearchField()
    let viewMode = NSSegmentedControl(images: [NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "网格")!, NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "列表")!], trackingMode: .selectOne, target: nil, action: nil)
    let titleLabel = label("Luma", size: 13, weight: .semibold)
    let subtitleLabel = label(size: 11, color: .secondaryLabelColor)
    private let titleView = NSView()
    private var toolbarItems: [String: NSToolbarItem] = [:]
    private let separator = NSBox()

    init(state: AppState) {
        self.state = state
        sidebar = SidebarViewController(state: state)
        gallery = GalleryViewController(state: state)
        status = StatusBar(state: state)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1440, screen.width - 80), height: min(850, screen.height - 80)),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.title = "Luma"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 880, height: 580)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LumaMainWindow")
        window.contentView = root
        root.addSubview(workspace)
        workspace.autoresizingMask = [.width, .height]
        workspace.frame = root.bounds
        workspace.addSubview(sidebar.view)
        workspace.addSubview(gallery.view)
        workspace.addSubview(empty)
        workspace.addSubview(status)
        separator.boxType = .separator
        workspace.addSubview(separator)
        root.onDrop = { [weak self] urls in self?.state.open(urls) }
        empty.onOpen = { [weak self] in self?.openFiles(nil) }
        empty.onDemo = { [weak self] in self?.state.showDemo() }
        sidebar.onOpen = { [weak self] in self?.openFiles(nil) }
        gallery.onOpenFiles = { [weak self] in self?.openFiles(nil) }
        gallery.onOpen = { [weak self] in self?.openSelected(nil) }
        gallery.contextMenu = { [weak self] in self?.photoMenu() ?? NSMenu() }
        workspace.onLayout = { [weak self] in self?.layoutWorkspace() }
        state.onChange = { [weak self] change in self?.update(change) }
        state.onError = { [weak self] message in self?.showError(message) }
        configureToolbar()
        update(.content)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layoutWorkspace() {
        let bounds = workspace.bounds
        let emptyMode = state.mode == .empty
        let sidebarWidth: CGFloat = state.sidebarVisible && !emptyMode ? 216 : 0
        let height = bounds.height - (emptyMode ? 0 : 26)
        sidebar.view.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: height)
        separator.frame = NSRect(x: sidebarWidth - 1, y: 0, width: 1, height: height)
        gallery.view.frame = NSRect(x: sidebarWidth, y: 0, width: bounds.width - sidebarWidth, height: height)
        empty.frame = bounds
        status.frame = NSRect(x: 0, y: height, width: bounds.width, height: 26)
        sidebar.view.isHidden = sidebarWidth == 0
        separator.isHidden = sidebarWidth == 0
        gallery.view.isHidden = emptyMode
        status.isHidden = emptyMode
        empty.isHidden = !emptyMode
    }

    func update(_ change: AppState.Change) {
        window?.title = state.mode == .empty ? "Luma" : "\(state.title) — Luma"
        titleLabel.stringValue = state.mode == .empty ? "Luma" : state.title
        subtitleLabel.stringValue = state.isLoading ? "正在读取图像…" : state.mode == .empty ? "" : "\(state.visiblePhotos.count) 张图像"
        switch change {
        case .content:
            gallery.reload()
            if search.stringValue != state.query { search.stringValue = state.query }
        case .selection: gallery.updateSelection()
        case .preferences: gallery.updatePreferences()
        case .loading: break
        }
        sidebar.reload()
        viewMode.selectedSegment = state.listMode ? 1 : 0
        status.update()
        layoutWorkspace()
        validateToolbar()
    }

    private func configureToolbar() {
        search.placeholderString = "搜索"
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.delegate = self
        search.target = self
        search.action = #selector(searchChanged)
        search.setAccessibilityLabel("搜索图像")
        search.frame = NSRect(x: 0, y: 0, width: 240, height: 28)
        viewMode.target = self
        viewMode.action = #selector(changeViewMode)
        viewMode.segmentStyle = .separated
        viewMode.setWidth(34, forSegment: 0)
        viewMode.setWidth(34, forSegment: 1)
        titleView.frame = NSRect(x: 0, y: 0, width: 200, height: 36)
        titleLabel.frame = NSRect(x: 0, y: 17, width: 200, height: 18)
        subtitleLabel.frame = NSRect(x: 0, y: 1, width: 200, height: 16)
        titleView.addSubview(titleLabel); titleView.addSubview(subtitleLabel)
        let toolbar = NSToolbar(identifier: "LumaBrowserToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ["sidebar", "back", "title", NSToolbarItem.Identifier.flexibleSpace.rawValue,
         "viewMode", "sort", "share", "search"].map { NSToolbarItem.Identifier($0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier.rawValue {
        case "sidebar": configure(item, symbol: "sidebar.left", label: "切换侧边栏", action: #selector(toggleSidebar))
        case "back": configure(item, symbol: "chevron.left", label: "返回", action: #selector(back))
        case "title": item.view = titleView; item.label = "当前文件夹"
        case "viewMode": item.view = viewMode; item.label = "显示方式"
        case "sort": configure(item, symbol: "arrow.up.arrow.down", label: "排序", action: #selector(showSort))
        case "share": configure(item, symbol: "square.and.arrow.up", label: "共享", action: #selector(share))
        case "search": item.view = search; item.label = "搜索"
        default: return nil
        }
        toolbarItems[itemIdentifier.rawValue] = item
        return item
    }
    private func configure(_ item: NSToolbarItem, symbol: String, label: String, action: Selector) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
    }
    private func validateToolbar() {
        toolbarItems["share"]?.isEnabled = state.selectedPhoto != nil
        toolbarItems["back"]?.isEnabled = state.mode != .empty
        toolbarItems["sort"]?.isEnabled = state.hasPhotos
        toolbarItems["sidebar"]?.isEnabled = state.mode != .empty
    }

    @objc func openFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "打开图片或文件夹"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK { self?.state.open(panel.urls) }
        }
    }
    @objc func openDemo(_ sender: Any?) { state.showDemo() }
    @objc func openSelected(_ sender: Any?) {
        if let photo = state.selectedPhoto { NSWorkspace.shared.open(photo.url) }
    }
    @objc func toggleSidebar(_ sender: Any?) { state.toggleSidebar() }
    @objc func back(_ sender: Any?) { state.showBrowser() }
    @objc func favorite(_ sender: Any?) { state.toggleFavorite() }
    @objc func showInFinder(_ sender: Any?) {
        if let photo = state.selectedPhoto { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
    }
    @objc func share(_ sender: Any?) {
        guard let photo = state.selectedPhoto, let view = window?.contentView else { return }
        let picker = NSSharingServicePicker(items: [photo.url])
        picker.show(relativeTo: NSRect(x: view.bounds.maxX - 300, y: view.bounds.maxY - 4, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
    @objc private func searchChanged() { state.setQuery(search.stringValue) }
    func controlTextDidChange(_ obj: Notification) { if obj.object as? NSSearchField === search { searchChanged() } }
    @objc private func changeViewMode() { state.setListMode(viewMode.selectedSegment == 1) }
    @objc private func showSort(_ sender: Any?) {
        let menu = NSMenu()
        for sort in PhotoSort.allCases {
            let item = NSMenuItem(title: sort.title, action: #selector(chooseSort), keyEquivalent: "")
            item.target = self
            item.representedObject = sort.rawValue
            item.state = sort == state.sort ? .on : .off
            menu.addItem(item)
        }
        let location = window?.mouseLocationOutsideOfEventStream ?? .zero
        if let view = window?.contentView { menu.popUp(positioning: nil, at: location, in: view) }
    }
    @objc private func chooseSort(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let sort = PhotoSort(rawValue: raw) { state.setSort(sort) }
    }
    func photoMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("打开图像", #selector(openSelected)), (state.isFavorite ? "取消收藏" : "添加到个人收藏", #selector(favorite)), ("共享…", #selector(share)), ("在 Finder 中显示", #selector(showInFinder))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = state.selectedPhoto != nil
            menu.addItem(item)
        }
        return menu
    }
    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "无法打开"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }
}
