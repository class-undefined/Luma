import AppKit
import LumaCore
import UniformTypeIdentifiers

final class WorkspaceView: FlippedView {
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
}

final class WindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate, NSWindowDelegate, NSUserInterfaceValidations, NSMenuDelegate {
    let state: AppState
    let clipboard: NSPasteboard
    let root = DropView(frame: .zero)
    let workspace = WorkspaceView(frame: .zero)
    let sidebar: SidebarViewController
    let gallery: GalleryViewController
    let viewer: ViewerViewController
    let empty = EmptyView(frame: .zero)
    let status: StatusBar
    let search = NSSearchField()
    let viewMode = NSSegmentedControl(images: [NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "网格")!, NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "列表")!], trackingMode: .selectOne, target: nil, action: nil)
    let titleLabel = label("Luma", size: 13, weight: .semibold)
    let subtitleLabel = label(size: 11, color: .secondaryLabelColor)
    private let titleView = NSView()
    private var toolbarItems: [String: NSToolbarItem] = [:]
    private let separator = NSBox()
    private let zoomLabel = label("100%", size: 11)
    let ratingFilterMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private var lastMode: AppState.Mode?
    private var keyMonitor: Any?
    private(set) var isFullscreen = false

    init(state: AppState, clipboard: NSPasteboard = .general) {
        self.state = state
        self.clipboard = clipboard
        sidebar = SidebarViewController(state: state)
        gallery = GalleryViewController(state: state)
        viewer = ViewerViewController(state: state)
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
        if state.defaults === UserDefaults.standard { window.setFrameAutosaveName("LumaMainWindow") }
        window.contentView = root
        root.addSubview(workspace)
        workspace.autoresizingMask = [.width, .height]
        workspace.frame = root.bounds
        workspace.addSubview(sidebar.view)
        workspace.addSubview(gallery.view)
        workspace.addSubview(viewer.view)
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
        viewer.contextMenu = { [weak self] in self?.photoMenu() ?? NSMenu() }
        viewer.onZoom = { [weak self] scale in self?.zoomLabel.stringValue = "\(Int((scale * 100).rounded()))%" }
        viewer.onReveal = { [weak self] in self?.showInFinder(nil) }
        viewer.onShare = { [weak self] in self?.share(nil) }
        viewer.onToggleFullscreen = { [weak self] in self?.toggleFullscreen(nil) }
        workspace.onLayout = { [weak self] in self?.layoutWorkspace() }
        state.onChange = { [weak self] change in self?.update(change) }
        state.onError = { [weak self] message in self?.showError(message) }
        configureToolbar()
        update(.content)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layoutWorkspace() {
        let bounds = workspace.bounds
        let emptyMode = state.mode == .empty
        let viewing = state.mode == .viewer
        let immersive = viewing && isFullscreen
        let sidebarWidth: CGFloat = state.sidebarVisible && !emptyMode && !viewing ? 216 : 0
        let height = bounds.height - (emptyMode || immersive ? 0 : 26)
        sidebar.view.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: height)
        separator.frame = NSRect(x: sidebarWidth - 1, y: 0, width: 1, height: height)
        gallery.view.frame = NSRect(x: sidebarWidth, y: 0, width: bounds.width - sidebarWidth, height: height)
        viewer.view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        empty.frame = bounds
        status.frame = NSRect(x: 0, y: height, width: bounds.width, height: 26)
        sidebar.view.isHidden = sidebarWidth == 0
        separator.isHidden = sidebarWidth == 0
        gallery.view.isHidden = emptyMode || viewing
        viewer.view.isHidden = !viewing
        status.isHidden = emptyMode || immersive
        empty.isHidden = !emptyMode
    }

    func update(_ change: AppState.Change) {
        let viewing = state.mode == .viewer
        let modeChanged = lastMode != state.mode
        if modeChanged {
            lastMode = state.mode
            window?.appearance = viewing ? NSAppearance(named: .darkAqua) : nil
            viewer.isFullscreen = viewing && isFullscreen
            configureToolbar()
        }
        window?.title = state.mode == .empty ? "Luma" : "\(state.selectedPhoto?.name ?? state.title) — Luma"
        titleLabel.stringValue = viewing ? state.selectedPhoto?.name ?? "Luma" : state.mode == .empty ? "Luma" : state.title
        subtitleLabel.stringValue = state.isLoading ? "正在读取图像…" : state.mode == .empty ? "" : viewing ? state.title : "\(state.visiblePhotos.count) 张图像"
        switch change {
        case .content:
            gallery.reload()
            if viewing { viewer.reload() }
            if search.stringValue != state.query { search.stringValue = state.query }
        case .selection:
            gallery.updateSelection()
            if viewing { viewer.updateSelection() }
        case .preferences:
            gallery.updatePreferences()
            viewer.updateLayout()
        case .loading: break
        }
        sidebar.reload()
        viewMode.selectedSegment = state.listMode ? 1 : 0
        if let item = ratingFilterMenu.itemArray.first(where: { $0.representedObject as? String == state.ratingFilter.stored }) {
            ratingFilterMenu.select(item)
        }
        status.update()
        layoutWorkspace()
        validateToolbar()
        if modeChanged && !viewing {
            gallery.updateSelection(reveal: true)
            if state.mode == .browser { window?.makeFirstResponder(state.listMode ? gallery.table : gallery.collection) }
        }
    }

    private func configureToolbar() {
        toolbarItems.removeAll()
        ratingFilterMenu.removeAllItems()
        ratingFilterMenu.controlSize = .small
        ratingFilterMenu.font = .systemFont(ofSize: 11)
        ratingFilterMenu.setAccessibilityLabel("按评分筛选照片")
        for filter in [RatingFilter.all] + (0...9).map({ .exact($0) }) + (1...9).map({ .atLeast($0) }) {
            ratingFilterMenu.addItem(withTitle: filter.title)
            ratingFilterMenu.lastItem?.representedObject = filter.stored
        }
        ratingFilterMenu.target = self
        ratingFilterMenu.action = #selector(chooseRatingFilter)
        ratingFilterMenu.frame = NSRect(x: 0, y: 0, width: 112, height: 26)
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
        let viewing = state.mode == .viewer
        titleView.frame = NSRect(x: 0, y: 0, width: viewing ? 260 : 200, height: 32)
        titleLabel.alignment = state.mode == .empty ? .center : .left
        titleLabel.font = .systemFont(ofSize: viewing ? 13 : 12, weight: .medium)
        titleLabel.frame = NSRect(x: 0, y: viewing || state.mode == .empty ? 7 : 15, width: titleView.frame.width, height: 18)
        subtitleLabel.frame = NSRect(x: 0, y: 1, width: 200, height: 16)
        subtitleLabel.isHidden = state.mode == .empty || viewing
        titleView.addSubview(titleLabel); titleView.addSubview(subtitleLabel)
        let toolbar = NSToolbar(identifier: "LumaBrowserToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        toolbar.isVisible = !(isFullscreen && state.mode == .viewer)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if state.mode == .empty { return [.flexibleSpace, .init("title"), .flexibleSpace] }
        let items = state.mode == .viewer
            ? ["back", "grid", "title", NSToolbarItem.Identifier.flexibleSpace.rawValue,
               "zoom", "fit", "rotate", "rating", "favorite", "share", "inspector", "fullscreen", "more"]
            : ["sidebar", "back", "forward", "title", NSToolbarItem.Identifier.flexibleSpace.rawValue,
               "viewMode", "ratingFilter", "sort", "share", "search"]
        return items.map { NSToolbarItem.Identifier($0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItem = itemIdentifier.rawValue == "search"
            ? NSSearchToolbarItem(itemIdentifier: itemIdentifier) : NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier.rawValue {
        case "sidebar": configure(item, symbol: "sidebar.left", label: "切换侧边栏", action: #selector(toggleSidebar))
        case "back": configure(item, symbol: "chevron.left", label: "返回", action: #selector(back))
        case "forward": configure(item, symbol: "chevron.right", label: "前进", action: #selector(forward))
        case "title": item.view = titleView; item.label = "当前文件夹"
        case "viewMode": item.view = viewMode; item.label = "显示方式"
        case "sort": configure(item, symbol: "arrow.up.arrow.down", label: "排序", action: #selector(showSort))
        case "ratingFilter": item.view = ratingFilterMenu; item.label = "评分筛选"
        case "rating": configure(item, symbol: "star", label: "照片评分", action: #selector(showRatingMenu))
        case "share": configure(item, symbol: "square.and.arrow.up", label: "共享", action: #selector(share))
        case "search":
            let searchItem = item as! NSSearchToolbarItem
            searchItem.searchField = search
            searchItem.preferredWidthForSearchField = 240
            item.label = "搜索"
        case "grid": configure(item, symbol: "square.grid.2x2", label: "返回图库", action: #selector(back))
        case "fit": configure(item, symbol: "rectangle.expand.vertical", label: "适合窗口", action: #selector(fitImage))
        case "rotate": configure(item, symbol: "arrow.counterclockwise", label: "向左旋转", action: #selector(rotateImage))
        case "favorite": configure(item, symbol: "heart", label: "收藏", action: #selector(favorite))
        case "inspector": configure(item, symbol: "info.circle", label: "显示检查器", action: #selector(toggleInspector))
        case "fullscreen": configure(item, symbol: "arrow.up.left.and.arrow.down.right", label: "进入全屏", action: #selector(toggleFullscreen))
        case "more": configure(item, symbol: "ellipsis.circle", label: "更多", action: #selector(showMore))
        case "zoom":
            let minus = ActionButton(symbol: "minus", title: "缩小") { [weak self] in self?.zoomOut(nil) }
            let plus = ActionButton(symbol: "plus", title: "放大") { [weak self] in self?.zoomIn(nil) }
            zoomLabel.alignment = .center
            let group = NSStackView(views: [minus, zoomLabel, plus])
            group.spacing = 8
            minus.widthAnchor.constraint(equalToConstant: 28).isActive = true
            plus.widthAnchor.constraint(equalToConstant: 28).isActive = true
            zoomLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
            item.view = group; item.label = "缩放"
        default: return nil
        }
        toolbarItems[itemIdentifier.rawValue] = item
        return item
    }
    private func configure(_ item: NSToolbarItem, symbol: String, label: String, action: Selector) {
        let button = ActionButton(symbol: symbol, title: label, size: state.mode == .viewer ? 13 : 14)
        button.actionHandler = { [weak self] in _ = self?.perform(action, with: nil) }
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        item.view = button
        item.autovalidates = false
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
    }
    private func validateToolbar() {
        toolbarItems["share"]?.isEnabled = state.selectedPhoto != nil
        toolbarItems["back"]?.isEnabled = state.mode == .viewer || state.canGoBack
        toolbarItems["forward"]?.isEnabled = state.canGoForward
        toolbarItems["sort"]?.isEnabled = state.hasPhotos
        toolbarItems["sidebar"]?.isEnabled = state.mode != .empty
        (toolbarItems["favorite"]?.view as? NSButton)?.image = NSImage(systemSymbolName: state.isFavorite ? "heart.fill" : "heart", accessibilityDescription: "收藏")
        toolbarItems["favorite"]?.toolTip = state.isFavorite ? "取消收藏（⌘D）" : "收藏（⌘D）"
        toolbarItems["rating"]?.toolTip = "评分：\(PhotoRating(state.selectedRating).title)（⌃0～9）"
        (toolbarItems["rating"]?.view as? NSButton)?.image = NSImage(systemSymbolName: state.selectedRating == 0 ? "star" : "star.fill", accessibilityDescription: "评分")
        for item in toolbarItems.values {
            if let button = item.view as? ActionButton { button.isEnabled = item.isEnabled }
        }
    }

    @objc func openFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "打开图片或文件夹"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage] + ImageDecoder.rawExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK { self?.state.open(panel.urls) }
        }
    }
    @objc func openDemo(_ sender: Any?) { state.showDemo() }
    @objc func openSelected(_ sender: Any?) {
        state.showViewer()
        window?.makeFirstResponder(viewer.canvas)
    }
    @objc func toggleSidebar(_ sender: Any?) { state.toggleSidebar() }
    @objc func back(_ sender: Any?) {
        if isFullscreen { window?.toggleFullScreen(nil) }
        else if state.mode == .viewer { state.showBrowser() }
        else { state.goBack() }
    }
    @objc func forward(_ sender: Any?) { state.goForward() }
    @objc func favorite(_ sender: Any?) { state.toggleFavorite() }
    @objc func assignRating(_ item: NSMenuItem) { state.setRating(item.tag) }
    @objc private func chooseRatingFilter() {
        if let value = ratingFilterMenu.selectedItem?.representedObject as? String { state.setRatingFilter(RatingFilter(stored: value)) }
    }
    func ratingMenu() -> NSMenu {
        let menu = NSMenu(title: "评分")
        menu.delegate = self
        for score in 0...9 {
            let item = NSMenuItem(title: PhotoRating(score).title, action: #selector(assignRating), keyEquivalent: "\(score)")
            item.keyEquivalentModifierMask = .control
            item.tag = score
            item.target = self
            item.state = score == state.selectedRating ? .on : .off
            item.isEnabled = state.selectedPhoto != nil
            menu.addItem(item)
        }
        return menu
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(assignRating) {
            item.state = item.tag == state.selectedRating ? .on : .off
            item.isEnabled = state.selectedPhoto != nil
        }
    }
    @objc private func showRatingMenu() {
        if let view = window?.contentView { ratingMenu().popUp(positioning: nil, at: window?.mouseLocationOutsideOfEventStream ?? .zero, in: view) }
    }
    @objc func toggleInspector(_ sender: Any?) { state.toggleInspector() }
    @objc func zoomIn(_ sender: Any?) { viewer.canvas.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { viewer.canvas.zoom(by: 1 / 1.25) }
    @objc func fitImage(_ sender: Any?) { viewer.canvas.fit() }
    @objc func actualSize(_ sender: Any?) { viewer.canvas.actualSize() }
    @objc func rotateImage(_ sender: Any?) { viewer.canvas.rotate() }
    @objc func toggleFullscreen(_ sender: Any?) {
        if state.mode != .viewer { state.showViewer() }
        guard state.hasPhotos else { return }
        window?.toggleFullScreen(nil)
    }
    @objc func increaseThumbnails(_ sender: Any?) { state.stepSize(1) }
    @objc func decreaseThumbnails(_ sender: Any?) { state.stepSize(-1) }
    @objc func focusSearch(_ sender: Any?) {
        if state.mode == .viewer { state.showBrowser() }
        (toolbarItems["search"] as? NSSearchToolbarItem)?.beginSearchInteraction()
    }
    @objc private func showMore(_ sender: Any?) {
        if let view = window?.contentView {
            photoMenu().popUp(positioning: nil, at: window?.mouseLocationOutsideOfEventStream ?? .zero, in: view)
        }
    }
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
    @objc private func changeViewMode() {
        state.setListMode(viewMode.selectedSegment == 1)
        window?.makeFirstResponder(state.listMode ? gallery.table : gallery.collection)
    }
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
        func add(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, enabled: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = modifiers
            item.isEnabled = enabled ?? (state.selectedPhoto != nil)
            menu.addItem(item)
        }
        add("打开图像", #selector(openSelected))
        let grade = NSMenuItem(title: "评分：\(PhotoRating(state.selectedRating).title)", action: nil, keyEquivalent: "")
        grade.submenu = ratingMenu()
        menu.addItem(grade)
        add(state.isFavorite ? "取消收藏" : "添加到个人收藏", #selector(favorite))
        menu.addItem(.separator())
        add("复制文件", #selector(copyFile), key: "c")
        add("复制文件名", #selector(copyFileName))
        add("复制文件路径", #selector(copyFilePath), key: "c", modifiers: [.command, .option])
        add("粘贴文件", #selector(pasteFiles), key: "v", enabled: pasteDestination != nil && !copiedFileURLs.isEmpty)
        menu.addItem(.separator())
        add("在 Finder 中显示", #selector(showInFinder))
        add("打开所在文件夹", #selector(openContainingFolder))
        add("共享…", #selector(share))
        menu.addItem(.separator())
        add("重命名…", #selector(renameFile), enabled: canModifyPhoto)
        add("制作副本", #selector(duplicateFile), enabled: canModifyPhoto)
        add("移到废纸篓", #selector(moveToTrash), key: "\u{8}", enabled: canModifyPhoto)
        return menu
    }
    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "操作未完成"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copyFile), #selector(copyFileName), #selector(copyFilePath), #selector(openContainingFolder): return state.selectedPhoto != nil
        case #selector(renameFile), #selector(duplicateFile), #selector(moveToTrash): return canModifyPhoto
        case #selector(pasteFiles): return pasteDestination != nil && !copiedFileURLs.isEmpty
        case #selector(openSelected), #selector(favorite), #selector(share), #selector(showInFinder), #selector(toggleFullscreen), #selector(assignRating): return state.selectedPhoto != nil
        case #selector(zoomIn), #selector(zoomOut), #selector(fitImage), #selector(actualSize), #selector(rotateImage), #selector(toggleInspector): return state.mode == .viewer
        case #selector(back): return state.mode == .viewer || state.canGoBack
        case #selector(forward): return state.canGoForward
        case #selector(increaseThumbnails): return state.mode == .browser && state.thumbnailSize != .huge
        case #selector(decreaseThumbnails): return state.mode == .browser && state.thumbnailSize != .tiny
        default: return true
        }
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, !(window?.firstResponder is NSTextView) else { return event }
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                if event.modifierFlags.contains(.option) { copyFilePath(nil) } else { copyFile(nil) }
                return nil
            case "v": pasteFiles(nil); return nil
            default:
                if event.keyCode == 51 { moveToTrash(nil); return nil }
            }
        }
        if event.modifierFlags.contains(.control), event.modifierFlags.intersection([.command, .option, .shift]).isEmpty,
           let characters = event.charactersIgnoringModifiers, characters.count == 1, let score = Int(characters) {
            state.setRating(score)
            return nil
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
        if event.keyCode == 53 {
            if !state.query.isEmpty && state.mode == .browser { state.setQuery("") }
            else if state.mode == .viewer { back(nil) }
            else { return event }
            return nil
        }
        guard state.mode == .viewer else { return event }
        switch event.keyCode {
        case 123: state.navigate(-1)
        case 124: state.navigate(1)
        case 49: break
        case 36: back(nil)
        default: return event
        }
        return nil
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        isFullscreen = true
        if state.mode == .viewer {
            window?.toolbar?.isVisible = false
            viewer.isFullscreen = true
            window?.makeFirstResponder(viewer.canvas)
        }
        layoutWorkspace()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        isFullscreen = true
        if state.mode == .viewer { window?.makeFirstResponder(viewer.canvas) }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        isFullscreen = false
        viewer.isFullscreen = false
        window.toolbar?.isVisible = true
        layoutWorkspace()
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        isFullscreen = true
        viewer.isFullscreen = state.mode == .viewer
        window.toolbar?.isVisible = state.mode != .viewer
        layoutWorkspace()
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        isFullscreen = false
        viewer.isFullscreen = false
        window?.toolbar?.isVisible = true
        layoutWorkspace()
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        window?.toolbar?.isVisible = true
        layoutWorkspace()
    }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}
