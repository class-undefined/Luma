import AppKit
import LumaCore

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    let tabs = NSTabViewController()
    let general: GeneralPreferencesPane
    let display: DisplayPreferencesPane
    let associations: AssociationsPreferencesPane

    init(state: AppState, defaultApplications: DefaultApplicationSettings) {
        general = GeneralPreferencesPane(state: state)
        display = DisplayPreferencesPane(state: state)
        associations = AssociationsPreferencesPane(settings: defaultApplications)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 530),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Luma 偏好设置"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.delegate = self
        tabs.tabStyle = .toolbar
        for (controller, title, symbol) in [(general as NSViewController, "通用", "gearshape"), (display, "显示", "photo"), (associations, "默认查看器", "doc.on.doc")] {
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
        window.setContentSize(NSSize(width: 620, height: 530))
        window.center()
        general.onManageAssociations = { [weak self] in self?.tabs.selectedTabViewItemIndex = 2 }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() { general.refresh(); display.refresh() }
    func windowDidBecomeKey(_ notification: Notification) { refresh(); associations.settings.refresh() }
}

class PreferencesPane: NSViewController {
    let form = NSStackView()
    override func loadView() {
        view = SurfaceView(.windowBackgroundColor)
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 530)
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 18
        form.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            form.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            form.topAnchor.constraint(equalTo: view.topAnchor, constant: 28)
        ])
    }
    func add(_ view: NSView) {
        form.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
    }
    func heading(_ text: String) { add(label(text, size: 13, weight: .semibold)) }
    func detail(_ text: String) {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        add(field)
    }
    func row(_ text: String, control: NSView) {
        let title = label(text, size: 12)
        title.widthAnchor.constraint(equalToConstant: 132).isActive = true
        let pair = NSStackView(views: [title, control])
        pair.orientation = .horizontal
        pair.alignment = .centerY
        pair.spacing = 16
        add(pair)
    }
    func divider() { let line = NSBox(); line.boxType = .separator; add(line) }
}

final class GeneralPreferencesPane: PreferencesPane {
    let state: AppState
    let openMode = NSPopUpButton(frame: .zero, pullsDown: false)
    let restore = NSButton(checkboxWithTitle: "启动时恢复上次打开的文件夹", target: nil, action: nil)
    let adjacent = NSButton(checkboxWithTitle: "打开单张照片时，载入同一文件夹的其他照片", target: nil, action: nil)
    var onManageAssociations: (() -> Void)?
    init(state: AppState) { self.state = state; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        super.loadView()
        heading("打开图片")
        openMode.addItems(withTitles: OpenMode.allCases.map(\.title))
        openMode.target = self; openMode.action = #selector(changeOpenMode)
        openMode.setAccessibilityLabel("默认打开模式")
        row("默认打开模式", control: openMode)
        detail("对下次打开的图片或文件夹生效。纯图片查看只显示照片，支持方向键切图、缩放、评分和右键操作。")
        adjacent.target = self; adjacent.action = #selector(changeAdjacent)
        add(adjacent)
        divider()
        heading("启动")
        restore.target = self; restore.action = #selector(changeRestore)
        add(restore)
        divider()
        heading("默认照片查看器")
        detail("将选定的图片格式关联到 Luma，之后在 Finder 中双击照片即可打开。")
        let button = NSButton(title: "管理默认查看器…", target: self, action: #selector(manage))
        button.bezelStyle = .rounded
        form.addArrangedSubview(button)
        refresh()
    }
    func refresh() {
        guard isViewLoaded else { return }
        openMode.selectItem(at: OpenMode.allCases.firstIndex(of: state.preferences.openMode) ?? 0)
        restore.state = state.preferences.restoreLastFolder ? .on : .off
        adjacent.state = state.preferences.loadAdjacentImages ? .on : .off
    }
    @objc private func changeOpenMode() { state.updatePreferences { $0.openMode = OpenMode.allCases[openMode.indexOfSelectedItem] } }
    @objc private func changeRestore() { state.updatePreferences { $0.restoreLastFolder = restore.state == .on } }
    @objc private func changeAdjacent() { state.updatePreferences { $0.loadAdjacentImages = adjacent.state == .on } }
    @objc private func manage() { onManageAssociations?() }
}

final class DisplayPreferencesPane: PreferencesPane {
    let state: AppState
    let thumbnailSize = NSPopUpButton(frame: .zero, pullsDown: false)
    let filmstrip = NSButton(checkboxWithTitle: "照片详情中显示胶片栏", target: nil, action: nil)
    let inspector = NSButton(checkboxWithTitle: "照片详情中显示信息面板", target: nil, action: nil)
    let statusBar = NSButton(checkboxWithTitle: "看图时显示状态栏", target: nil, action: nil)
    init(state: AppState) { self.state = state; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        super.loadView()
        heading("图库")
        thumbnailSize.addItems(withTitles: ThumbnailSize.allCases.map { "\($0.title) · \(Int($0.width)) pt" })
        thumbnailSize.target = self; thumbnailSize.action = #selector(changeSize)
        row("缩略图大小", control: thumbnailSize)
        detail("与图库底部控件、Command＋滚轮和 Control＋滚轮保持一致。")
        divider()
        heading("照片详情")
        for (button, action) in [(filmstrip, #selector(changeFilmstrip)), (inspector, #selector(changeInspector)), (statusBar, #selector(changeStatusBar))] {
            button.target = self; button.action = action; add(button)
        }
        detail("这些选项立即生效。纯图片模式会隐藏胶片栏、信息面板、状态栏和工具栏。可在“显示”菜单中切换模式。")
        refresh()
    }
    func refresh() {
        guard isViewLoaded else { return }
        thumbnailSize.selectItem(at: state.thumbnailSize.rawValue)
        filmstrip.state = state.preferences.showFilmstrip ? .on : .off
        inspector.state = state.inspectorVisible ? .on : .off
        statusBar.state = state.preferences.showStatusBar ? .on : .off
    }
    @objc private func changeSize() { state.setSize(ThumbnailSize(clamping: thumbnailSize.indexOfSelectedItem)) }
    @objc private func changeFilmstrip() { state.updatePreferences { $0.showFilmstrip = filmstrip.state == .on } }
    @objc private func changeStatusBar() { state.updatePreferences { $0.showStatusBar = statusBar.state == .on } }
    @objc private func changeInspector() { if (inspector.state == .on) != state.inspectorVisible { state.toggleInspector() } }
}

final class AssociationsPreferencesPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let settings: DefaultApplicationSettings
    let table = NSTableView()
    let applyButton = NSButton(title: "设为所选类型的默认查看器", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "")
    private let count = label(size: 11, color: .secondaryLabelColor)
    private let spinner = NSProgressIndicator()
    private var selected: Set<String>
    private var refreshButton = NSButton(title: "刷新状态", target: nil, action: nil)
    private var scopeButtons: [NSButton] = []
    init(settings: DefaultApplicationSettings) {
        self.settings = settings
        selected = Set(settings.formats.filter { !$0.isRAW }.map(\.id))
        super.init(nibName: nil, bundle: nil)
        settings.onChange = { [weak self] in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = SurfaceView(.windowBackgroundColor)
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 530)
        let heading = label("选择由 Luma 默认打开的文件类型", size: 13, weight: .semibold)
        let description = label("仅更改选中的格式。系统如需确认，会显示原生确认窗口。", size: 11, color: .secondaryLabelColor)
        let all = NSButton(title: "全选", target: self, action: #selector(selectAllTypes))
        let common = NSButton(title: "常见图片", target: self, action: #selector(selectCommonTypes))
        let none = NSButton(title: "全不选", target: self, action: #selector(selectNoTypes))
        scopeButtons = [all, common, none]
        refreshButton.target = self; refreshButton.action = #selector(refreshStatus)
        let scopes = NSStackView(views: [all, common, none, count, refreshButton])
        scopes.spacing = 10
        for button in scopeButtons + [refreshButton] { button.bezelStyle = .rounded; button.controlSize = .small }
        for (id, title, width) in [("select", "", CGFloat(28)), ("type", "文件类型", 210), ("application", "当前默认应用", 280)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self
        table.rowHeight = 30; table.usesAlternatingRowBackgroundColors = true
        table.style = .fullWidth; table.selectionHighlightStyle = .none
        table.setAccessibilityLabel("图片格式与默认应用")
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        applyButton.bezelStyle = .rounded; applyButton.bezelColor = .controlAccentColor
        applyButton.controlSize = .large
        applyButton.font = .systemFont(ofSize: 12)
        applyButton.target = self; applyButton.action = #selector(apply)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let footer = NSStackView(views: [spinner, applyButton])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 12
        for child in [heading, description, scopes, scroll, status, footer] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            description.leadingAnchor.constraint(equalTo: heading.leadingAnchor), description.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scopes.leadingAnchor.constraint(equalTo: heading.leadingAnchor), scopes.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scopes.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: scopes.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: scopes.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: heading.leadingAnchor), status.trailingAnchor.constraint(equalTo: scopes.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12), status.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            footer.trailingAnchor.constraint(equalTo: scopes.trailingAnchor), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            footer.heightAnchor.constraint(equalToConstant: 32),
            spinner.widthAnchor.constraint(equalToConstant: 16), spinner.heightAnchor.constraint(equalToConstant: 16),
            applyButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        refresh()
    }
    func refresh() {
        guard isViewLoaded else { return }
        table.reloadData()
        count.stringValue = "已选 \(selected.count) 项"
        applyButton.isEnabled = settings.canConfigure && !selected.isEmpty && !settings.isApplying
        for button in scopeButtons + [refreshButton] { button.isEnabled = !settings.isApplying }
        if settings.isApplying { spinner.startAnimation(nil); status.stringValue = settings.progress }
        else {
            spinner.stopAnimation(nil)
            status.stringValue = !settings.canConfigure ? "请运行打包后的 Luma.app，以设置默认打开方式。" : settings.result?.message ?? "当前应用：\(settings.access.applicationURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
        }
        if let failures = settings.result?.failures, !failures.isEmpty {
            status.toolTip = failures.map { key, error in "\(settings.formats.first { $0.id == key }?.title ?? key)：\(error)" }.sorted().joined(separator: "\n")
        } else { status.toolTip = nil }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { settings.formats.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let format = settings.formats[row]
        let cell = NSTableCellView()
        if tableColumn?.identifier.rawValue == "select" {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleType))
            button.tag = row; button.state = selected.contains(format.id) ? .on : .off; button.isEnabled = !settings.isApplying
            button.setAccessibilityLabel("选择 \(format.title)")
            button.frame = NSRect(x: 3, y: 5, width: 22, height: 20)
            cell.addSubview(button)
            return cell
        }
        let current = settings.handlers[format.id]
        let name = current?.deletingPathExtension().lastPathComponent ?? "未设置"
        let isType = tableColumn?.identifier.rawValue == "type"
        let value = label(isType ? format.title : settings.isDefault(for: format) ? "✓ Luma" : name,
                          size: 12, color: isType ? .labelColor : settings.isDefault(for: format) ? .controlAccentColor : .secondaryLabelColor)
        value.frame = NSRect(x: 4, y: 6, width: max(40, (tableColumn?.width ?? 200) - 8), height: 18)
        value.autoresizingMask = [.width]
        value.toolTip = current?.path
        cell.addSubview(value); cell.textField = value
        return cell
    }
    @objc private func toggleType(_ sender: NSButton) {
        let id = settings.formats[sender.tag].id
        if sender.state == .on { selected.insert(id) } else { selected.remove(id) }
        refresh()
    }
    @objc private func selectAllTypes() { selected = Set(settings.formats.map(\.id)); refresh() }
    @objc private func selectCommonTypes() { selected = Set(settings.formats.filter { !$0.isRAW }.map(\.id)); refresh() }
    @objc private func selectNoTypes() { selected.removeAll(); refresh() }
    @objc private func refreshStatus() { settings.refresh() }
    @objc private func apply() {
        let formats = settings.formats.filter { selected.contains($0.id) }
        Task { await settings.apply(to: formats) }
    }
}
