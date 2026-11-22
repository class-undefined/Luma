import AppKit
import LumaCore

final class GalleryLayout: NSCollectionViewLayout {
    var size: ThumbnailSize = .medium
    private(set) var geometry = GalleryGeometry(viewportWidth: 1224, size: .medium)
    private var count = 0
    private let rowGap: CGFloat = 20
    override func prepare() {
        super.prepare()
        geometry = GalleryGeometry(viewportWidth: collectionView?.enclosingScrollView?.contentSize.width ?? 1000, size: size)
        count = collectionView?.numberOfItems(inSection: 0) ?? 0
    }
    override var collectionViewContentSize: NSSize {
        let rows = max(0, (count + geometry.columns - 1) / geometry.columns)
        let height = CGFloat(rows) * (geometry.itemHeight + rowGap) - rowGap + 64
        return NSSize(width: collectionView?.enclosingScrollView?.contentSize.width ?? 1000,
                      height: max(collectionView?.enclosingScrollView?.contentSize.height ?? 0, height))
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < count else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        let column = indexPath.item % geometry.columns
        let row = indexPath.item / geometry.columns
        attributes.frame = NSRect(x: geometry.horizontalInset + CGFloat(column) * (geometry.itemWidth + geometry.gap),
                                  y: 32 + CGFloat(row) * (geometry.itemHeight + rowGap),
                                  width: geometry.itemWidth, height: geometry.itemHeight)
        return attributes
    }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let firstRow = max(0, Int((rect.minY - 32) / (geometry.itemHeight + rowGap)))
        let lastRow = max(firstRow, Int((rect.maxY - 32) / (geometry.itemHeight + rowGap)) + 1)
        let lower = min(count, firstRow * geometry.columns)
        let upper = min(count, (lastRow + 1) * geometry.columns)
        return (lower..<upper).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - collectionViewContentSize.width) > 0.5
    }
}

final class GalleryScrollView: NSScrollView {
    var onStep: ((Int) -> Void)?
    private var accumulator = ScrollStepAccumulator()
    override func scrollWheel(with event: NSEvent) {
        let result = accumulator.handle(delta: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                        control: !event.modifierFlags.intersection([.command, .control]).isEmpty,
                                        momentum: event.momentumPhase != [], began: event.phase.contains(.began),
                                        timestamp: event.timestamp)
        if result.consumed {
            if result.step != 0 { onStep?(result.step) }
        } else { super.scrollWheel(with: event) }
    }
}

final class GalleryCollectionView: NSCollectionView {
    var onOpen: (() -> Void)?
    var contextMenu: (() -> NSMenu)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onOpen?() } else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        if let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            selectItems(at: [indexPath], scrollPosition: [])
            delegate?.collectionView?(self, didSelectItemsAt: [indexPath])
        }
        return contextMenu?()
    }
}

final class GalleryTableView: NSTableView {
    var onOpen: (() -> Void)?
    var contextMenu: (() -> NSMenu)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onOpen?() } else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        if clicked >= 0 { selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false) }
        return contextMenu?()
    }
}

final class GalleryViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate,
                                   NSTableViewDataSource, NSTableViewDelegate {
    let state: AppState
    let collection = GalleryCollectionView()
    let layout = GalleryLayout()
    let gridScroll = GalleryScrollView()
    let table = GalleryTableView()
    let listScroll = NSScrollView()
    let empty = EmptyView(frame: .zero)
    var onOpen: (() -> Void)?
    var onOpenFiles: (() -> Void)?
    var contextMenu: (() -> NSMenu)?
    private var photos: [Photo] = []
    private var appliedSize: ThumbnailSize?
    private var syncingSelection = false
    private var resizeObserver: NSObjectProtocol?

    init(state: AppState) { self.state = state; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = SurfaceView(.textBackgroundColor)
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.backgroundColors = [.textBackgroundColor]
        collection.register(ThumbnailItem.self, forItemWithIdentifier: .init("photo"))
        collection.onOpen = { [weak self] in self?.onOpen?() }
        collection.contextMenu = { [weak self] in self?.contextMenu?() ?? NSMenu() }
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openSelected))
        doubleClick.numberOfClicksRequired = 2
        collection.addGestureRecognizer(doubleClick)
        gridScroll.documentView = collection
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.borderType = .noBorder
        gridScroll.drawsBackground = false
        gridScroll.onStep = { [weak self] in self?.state.stepSize($0) }
        collection.setAccessibilityLabel("图像图库")
        gridScroll.contentView.postsFrameChangedNotifications = true
        resizeObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: gridScroll.contentView, queue: .main) { [weak self] _ in
                self?.layout.invalidateLayout()
            }

        let columns = [("name", "名称", CGFloat(380)), ("rating", "评分", 80), ("dimensions", "尺寸", 170), ("size", "大小", 100), ("kind", "种类", 80)]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            column.minWidth = id == "name" ? 180 : 70
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 52
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.onOpen = { [weak self] in self?.onOpen?() }
        table.contextMenu = { [weak self] in self?.contextMenu?() ?? NSMenu() }
        table.setAccessibilityLabel("图像列表")
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        empty.demo.isHidden = true
        empty.formats.isHidden = true
        empty.onOpen = { [weak self] in self?.onOpenFiles?() }
        for subview in [gridScroll, listScroll, empty] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    deinit { if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) } }
    @objc private func openSelected() { onOpen?() }

    func reload() {
        loadViewIfNeeded()
        let changed = photos != state.visiblePhotos
        let anchor = captureAnchor()
        syncingSelection = true
        photos = state.visiblePhotos
        if changed {
            collection.reloadData()
            layout.invalidateLayout()
        }
        table.reloadData()
        for case let item as ThumbnailItem in collection.visibleItems() {
            if let photo = item.thumbnail.photo { item.thumbnail.rating = state.rating(for: photo.id) }
        }
        updatePreferences()
        updateSelection()
        if changed {
            view.layoutSubtreeIfNeeded()
            if let anchor, photos.contains(where: { $0.id == anchor.id }) { restoreAnchor(anchor) }
            else { gridScroll.contentView.scroll(to: .zero); gridScroll.reflectScrolledClipView(gridScroll.contentView) }
        }
        empty.heading.stringValue = state.query.isEmpty ? "没有图像" : "没有匹配的图像"
        empty.detail.stringValue = state.ratingFilter != .all ? "没有符合评分条件的照片，可切换为全部评分。" : state.query.isEmpty ? "打开其他文件夹，或将图片拖入窗口。" : "试试其他文件名，或清空搜索。"
        empty.open.isHidden = !state.query.isEmpty
        empty.shortcut.isHidden = !state.query.isEmpty
    }

    func updatePreferences() {
        loadViewIfNeeded()
        if appliedSize != state.thumbnailSize {
            let anchor = captureAnchor()
            let wasSyncing = syncingSelection
            syncingSelection = true
            layout.size = state.thumbnailSize
            appliedSize = state.thumbnailSize
            collection.reloadData()
            layout.invalidateLayout()
            collection.layoutSubtreeIfNeeded()
            if let anchor { restoreAnchor(anchor) }
            updateSelection()
            syncingSelection = wasSyncing
        }
        gridScroll.isHidden = state.listMode || photos.isEmpty
        listScroll.isHidden = !state.listMode || photos.isEmpty
        empty.isHidden = !photos.isEmpty
    }

    func updateSelection(reveal: Bool = false) {
        guard isViewLoaded else { return }
        syncingSelection = true
        if let index = photos.firstIndex(where: { $0.id == state.selectedID }) {
            let indexPath = IndexPath(item: index, section: 0)
            collection.selectionIndexPaths = [indexPath]
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            if reveal {
                collection.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
                collection.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
                table.scrollRowToVisible(index)
            }
        } else { collection.selectionIndexPaths = []; table.deselectAll(nil) }
        syncingSelection = false
    }

    struct Anchor { let id: String; let offset: CGFloat }
    func captureAnchor() -> Anchor? {
        guard !photos.isEmpty, isViewLoaded else { return nil }
        let visible = gridScroll.contentView.bounds
        let selected = photos.firstIndex(where: { $0.id == state.selectedID }).flatMap { index -> Int? in
            guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame,
                  frame.intersects(visible) else { return nil }
            return index
        }
        let first = collection.indexPathsForVisibleItems().sorted { $0.item < $1.item }.first?.item
        guard let index = selected ?? first, index < photos.count,
              let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return nil }
        return Anchor(id: photos[index].id, offset: frame.minY - visible.minY)
    }

    func restoreAnchor(_ anchor: Anchor) {
        guard let index = photos.firstIndex(where: { $0.id == anchor.id }) else { return }
        collection.layoutSubtreeIfNeeded()
        guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return }
        let maxY = max(0, layout.collectionViewContentSize.height - gridScroll.contentSize.height)
        gridScroll.contentView.scroll(to: NSPoint(x: 0, y: min(maxY, max(0, frame.minY - anchor.offset))))
        gridScroll.reflectScrolledClipView(gridScroll.contentView)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { photos.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("photo"), for: indexPath) as! ThumbnailItem
        item.configure(photos[indexPath.item], rating: state.rating(for: photos[indexPath.item].id))
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !syncingSelection, let index = indexPaths.first?.item, index < photos.count else { return }
        state.select(photos[index].id)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { photos.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let photo = photos[row]
        switch tableColumn?.identifier.rawValue {
        case "name":
            let cell = NSTableCellView()
            let text = label(photo.name)
            let image = NSImageView()
            image.imageScaling = .scaleProportionallyUpOrDown
            image.frame = NSRect(x: 8, y: 6, width: 52, height: 40)
            text.frame = NSRect(x: 74, y: 17, width: max(100, tableColumn!.width - 85), height: 18)
            text.autoresizingMask = [.width]
            cell.addSubview(image); cell.addSubview(text)
            cell.textField = text
            cell.imageView = image
            Task { [weak image] in image?.image = await ImagePipeline.shared.image(for: photo, maxPixels: 160) }
            return cell
        default:
            let value: String
            switch tableColumn?.identifier.rawValue {
            case "rating": value = PhotoRating(state.rating(for: photo.id)).title
            case "dimensions": value = "\(photo.metadata.pixelWidth) × \(photo.metadata.pixelHeight)"
            case "size": value = photo.metadata.fileSize
            default: value = photo.metadata.format
            }
            let cell = NSTableCellView()
            let text = label(value, color: .secondaryLabelColor)
            text.frame = NSRect(x: 8, y: 17, width: max(50, (tableColumn?.width ?? 100) - 16), height: 18)
            text.autoresizingMask = [.width]
            cell.addSubview(text)
            cell.textField = text
            return cell
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection, table.selectedRow >= 0, table.selectedRow < photos.count else { return }
        state.select(photos[table.selectedRow].id)
    }
}
