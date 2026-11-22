import AppKit
import LumaCore

final class FilmstripLayout: NSCollectionViewLayout {
    override var collectionViewContentSize: NSSize {
        let count = collectionView?.numberOfItems(inSection: 0) ?? 0
        return NSSize(width: max(collectionView?.enclosingScrollView?.contentSize.width ?? 0, CGFloat(count) * 100 + 28), height: 94)
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < (collectionView?.numberOfItems(inSection: 0) ?? 0) else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = NSRect(x: 20 + CGFloat(indexPath.item) * 100, y: 8, width: 88, height: 76)
        return attributes
    }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let count = collectionView?.numberOfItems(inSection: 0) ?? 0
        let first = min(count, max(0, Int((rect.minX - 20) / 100)))
        let last = min(count, max(first, Int(rect.maxX / 100) + 1))
        return (first..<last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }
}

final class ViewerViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let state: AppState
    let canvas = ImageCanvas(frame: .zero)
    let inspector: InspectorView
    let filmstrip = NSCollectionView()
    let filmScroll = NSScrollView()
    private let filmMaterial = NSVisualEffectView()
    private let background = NSImageView()
    private let host = WorkspaceView(frame: .zero)
    private let separator = NSBox()
    private let imageError = label("无法读取此图像", size: 15, color: .secondaryLabelColor)
    private let spinner = NSProgressIndicator()
    private(set) var photos: [Photo] = []
    private var imageTask: Task<Void, Never>?
    private var displayedID: String?
    private var syncingSelection = false
    private var hud: NSView!
    private var filenameGlass: NSView!
    private let filename = label(size: 12)
    private let position = label(size: 12)
    private let zoom = label(size: 12)
    private let favoriteButton = ActionButton(symbol: "heart", title: "收藏")
    private let exitButton = ActionButton(symbol: "arrow.down.right.and.arrow.up.left", title: "退出全屏")
    private var hudControls: [NSView] = []
    var isFullscreen = false { didSet { updateLayout() } }
    var onZoom: ((CGFloat) -> Void)?
    var onShare: (() -> Void)?
    var onReveal: (() -> Void)?
    var onToggleFullscreen: (() -> Void)?

    init(state: AppState) { self.state = state; inspector = InspectorView(state: state); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = host
        view.appearance = NSAppearance(named: .darkAqua)
        background.imageScaling = .scaleAxesIndependently
        background.alphaValue = 0.28
        host.addSubview(background)
        host.addSubview(canvas)
        filmstrip.collectionViewLayout = FilmstripLayout()
        filmstrip.backgroundColors = [.clear]
        filmstrip.isSelectable = true
        filmstrip.dataSource = self
        filmstrip.delegate = self
        filmstrip.register(ThumbnailItem.self, forItemWithIdentifier: .init("film"))
        filmstrip.setAccessibilityLabel("缩略图胶片栏")
        filmScroll.frame = NSRect(x: 0, y: 0, width: 1168, height: 94)
        filmScroll.scrollerStyle = .overlay
        filmScroll.documentView = filmstrip
        filmScroll.drawsBackground = false
        filmScroll.hasHorizontalScroller = true
        filmScroll.autohidesScrollers = true
        filmMaterial.material = .sidebar
        filmMaterial.blendingMode = .withinWindow
        filmMaterial.state = .active
        host.addSubview(filmMaterial)
        filmMaterial.addSubview(filmScroll)
        host.addSubview(inspector)
        separator.boxType = .separator
        host.addSubview(separator)
        inspector.onReveal = { [weak self] in self?.onReveal?() }
        canvas.onZoom = { [weak self] scale in
            self?.zoom.stringValue = "\(Int((scale * 100).rounded()))%"
            self?.onZoom?(scale)
        }
        imageError.alignment = .center
        imageError.isHidden = true
        host.addSubview(imageError)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        host.addSubview(spinner)
        configureHUD()
        host.onLayout = { [weak self] in self?.updateLayout() }
    }

    private func glass(content: NSView, radius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.tintColor = NSColor.black.withAlphaComponent(0.3)
            glass.cornerRadius = radius
            glass.contentView = content
            return glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow
            material.blendingMode = .withinWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = radius
            material.layer?.masksToBounds = true
            material.addSubview(content)
            content.autoresizingMask = [.width, .height]
            return material
        }
    }

    private func configureHUD() {
        let controls = NSView()
        func button(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> ActionButton {
            ActionButton(symbol: symbol, title: title, action: action)
        }
        let previous = button("chevron.left", "上一张") { [weak self] in self?.state.navigate(-1) }
        let next = button("chevron.right", "下一张") { [weak self] in self?.state.navigate(1) }
        let minus = button("minus", "缩小") { [weak self] in self?.canvas.zoom(by: 1 / 1.25) }
        let plus = button("plus", "放大") { [weak self] in self?.canvas.zoom(by: 1.25) }
        let fit = button("rectangle.expand.vertical", "适合窗口") { [weak self] in self?.canvas.fit() }
        let rotate = button("arrow.counterclockwise", "向左旋转") { [weak self] in self?.canvas.rotate() }
        let share = button("square.and.arrow.up", "共享") { [weak self] in self?.onShare?() }
        let exit = button("arrow.down.right.and.arrow.up.left", "退出全屏") { [weak self] in self?.onToggleFullscreen?() }
        favoriteButton.actionHandler = { [weak self] in self?.state.toggleFavorite() }
        position.alignment = .center
        zoom.alignment = .center
        hudControls = [previous, position, next, minus, zoom, plus, fit, favoriteButton, rotate, share, exit]
        for control in hudControls { controls.addSubview(control) }
        controls.frame = NSRect(x: 0, y: 0, width: 584, height: 56)
        hud = glass(content: controls, radius: 28)
        host.addSubview(hud)
        filename.alignment = .center
        let nameHost = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 34))
        nameHost.addSubview(filename)
        filenameGlass = glass(content: nameHost, radius: 17)
        host.addSubview(filenameGlass)
        exitButton.actionHandler = { [weak self] in self?.onToggleFullscreen?() }
        host.addSubview(exitButton)
    }

    func updateLayout() {
        guard isViewLoaded else { return }
        let bounds = host.bounds
        let inspectorWidth: CGFloat = !isFullscreen && state.inspectorVisible ? 272 : 0
        let stripHeight: CGFloat = isFullscreen ? 0 : 94
        let width = bounds.width - inspectorWidth
        background.frame = bounds
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height - stripHeight)
        filmMaterial.frame = NSRect(x: 0, y: bounds.height - 94, width: width, height: 94)
        filmScroll.frame = filmMaterial.bounds
        inspector.frame = NSRect(x: width, y: 0, width: inspectorWidth, height: bounds.height)
        separator.frame = NSRect(x: width - 1, y: 0, width: 1, height: bounds.height)
        filmMaterial.isHidden = isFullscreen
        inspector.isHidden = inspectorWidth == 0
        separator.isHidden = inspectorWidth == 0
        hud.isHidden = !isFullscreen
        filenameGlass.isHidden = !isFullscreen
        exitButton.isHidden = !isFullscreen
        hud.frame = NSRect(x: (bounds.width - 584) / 2, y: bounds.height - 98, width: 584, height: 56)
        let widths: [CGFloat] = [32, 54, 32, 32, 54, 32, 32, 32, 32, 32, 32]
        var x: CGFloat = 12
        for (index, control) in hudControls.enumerated() {
            if [3, 7].contains(index) { x += 12 }
            control.frame = NSRect(x: x, y: control is NSTextField ? 19 : 12, width: widths[index], height: control is NSTextField ? 18 : 32)
            x += widths[index] + 10
        }
        filenameGlass.frame = NSRect(x: (bounds.width - 240) / 2, y: 20, width: 240, height: 34)
        filename.frame = NSRect(x: 14, y: 8, width: 212, height: 18)
        exitButton.frame = NSRect(x: 20, y: 20, width: 32, height: 32)
        imageError.frame = NSRect(x: 30, y: canvas.frame.midY - 10, width: width - 60, height: 24)
        spinner.frame = NSRect(x: width / 2 - 10, y: canvas.frame.midY - 10, width: 20, height: 20)
    }

    func reload() {
        loadViewIfNeeded()
        syncingSelection = true
        if photos != state.visiblePhotos {
            photos = state.visiblePhotos
            filmstrip.reloadData()
        }
        syncingSelection = false
        updateSelection()
        updateLayout()
    }
    func updateSelection() {
        guard isViewLoaded, let photo = state.selectedPhoto else { return }
        if let index = state.selectedIndex {
            syncingSelection = true
            let path = IndexPath(item: index, section: 0)
            filmstrip.selectionIndexPaths = [path]
            filmstrip.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            syncingSelection = false
            position.stringValue = "\(index + 1) / \(photos.count)"
        }
        filename.stringValue = photo.name
        favoriteButton.image = NSImage(systemSymbolName: state.isFavorite ? "heart.fill" : "heart", accessibilityDescription: "收藏")
        favoriteButton.contentTintColor = state.isFavorite ? .systemPink : .labelColor
        inspector.update(photo)
        for case let item as ThumbnailItem in filmstrip.visibleItems() {
            if let photo = item.thumbnail.photo { item.thumbnail.rating = state.rating(for: photo.id) }
        }
        guard displayedID != photo.id else { return }
        displayedID = photo.id
        canvas.display(photo)
        imageError.isHidden = true
        spinner.startAnimation(nil)
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let image = await ImagePipeline.shared.image(for: photo, maxPixels: max(photo.metadata.pixelWidth, photo.metadata.pixelHeight), original: true)
            guard let self, !Task.isCancelled, self.displayedID == photo.id else { return }
            self.canvas.image = image
            self.background.image = image
            self.spinner.stopAnimation(nil)
            self.imageError.isHidden = image != nil
        }
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { photos.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("film"), for: indexPath) as! ThumbnailItem
        item.configure(photos[indexPath.item], filmstrip: true, rating: state.rating(for: photos[indexPath.item].id))
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !syncingSelection, let index = indexPaths.first?.item, index < photos.count else { return }
        state.select(photos[index].id)
    }
}
