import AppKit
import LumaCore

final class ThumbnailView: FlippedView {
    let preview = NSImageView()
    let selectionRing = NSView()
    let filename = label(size: 12)
    var photo: Photo? { didSet { needsLayout = true; setAccessibilityLabel(photo?.name) } }
    var selected = false { didSet { updateSelection() } }
    var filmstrip = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.masksToBounds = true
        selectionRing.wantsLayer = true
        selectionRing.layer?.borderWidth = 2
        selectionRing.layer?.cornerRadius = 12
        selectionRing.isHidden = true
        filename.alignment = .center
        filename.wantsLayer = true
        filename.layer?.cornerRadius = 4
        filename.layer?.masksToBounds = true
        addSubview(selectionRing)
        addSubview(preview)
        addSubview(filename)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateSelection() {
        selectionRing.isHidden = !selected
        selectionRing.layer?.borderColor = NSColor.controlAccentColor.cgColor
        filename.textColor = selected && !filmstrip ? .white : .labelColor
        filename.layer?.backgroundColor = selected && !filmstrip ? NSColor.controlAccentColor.cgColor : .clear
        setAccessibilitySelected(selected)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSelection() }
    override func layout() {
        super.layout()
        let maxHeight = max(1, bounds.height - (filmstrip ? 22 : 32))
        let ratio = photo?.metadata.aspectRatio ?? 1.5
        let width = min(bounds.width - (filmstrip ? 4 : 0), maxHeight * ratio)
        let height = width / ratio
        preview.frame = NSRect(x: (bounds.width - width) / 2, y: (maxHeight - height) / 2, width: width, height: height)
        preview.layer?.cornerRadius = filmstrip ? 6 : 10
        selectionRing.frame = preview.frame.insetBy(dx: -2, dy: -2)
        selectionRing.layer?.cornerRadius = filmstrip ? 8 : 12
        filename.font = .systemFont(ofSize: filmstrip ? 9 : 12)
        filename.stringValue = filmstrip ? (photo?.name as NSString?)?.deletingPathExtension ?? "" : photo?.name ?? ""
        let nameWidth = min(bounds.width, filename.intrinsicContentSize.width + 16)
        filename.frame = NSRect(x: (bounds.width - nameWidth) / 2, y: maxHeight + 5, width: nameWidth, height: filmstrip ? 16 : 22)
    }
}

final class ThumbnailItem: NSCollectionViewItem {
    var thumbnail: ThumbnailView { view as! ThumbnailView }
    private var imageTask: Task<Void, Never>?
    override func loadView() { view = ThumbnailView(frame: .zero) }
    override var isSelected: Bool { didSet { if isViewLoaded { thumbnail.selected = isSelected } } }

    func configure(_ photo: Photo, filmstrip: Bool = false) {
        imageTask?.cancel()
        thumbnail.photo = photo
        thumbnail.filmstrip = filmstrip
        thumbnail.selected = isSelected
        thumbnail.preview.image = nil
        imageTask = Task { [weak self] in
            let image = await ImagePipeline.shared.image(for: photo, maxPixels: filmstrip ? 240 : 1024)
            guard !Task.isCancelled, self?.thumbnail.photo?.id == photo.id else { return }
            self?.thumbnail.preview.image = image
        }
    }
    override func prepareForReuse() { super.prepareForReuse(); imageTask?.cancel(); thumbnail.preview.image = nil }
}
