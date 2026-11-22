import AppKit
import LumaCore

final class CroppedImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let crop = NSSize(width: bounds.width / scale, height: bounds.height / scale)
        let source = NSRect(x: (image.size.width - crop.width) / 2, y: (image.size.height - crop.height) / 2,
                            width: crop.width, height: crop.height)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds, from: source, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

final class ThumbnailView: FlippedView {
    let preview = CroppedImageView()
    let selectionRing = NSView()
    let filename = label(size: 12)
    let ratingBadge = label(size: 10, color: .white, weight: .medium)
    var rating = 0 {
        didSet {
            ratingBadge.stringValue = "★ \(rating)"
            ratingBadge.isHidden = rating == 0
        }
    }
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
        ratingBadge.alignment = .center
        ratingBadge.wantsLayer = true
        ratingBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        ratingBadge.layer?.cornerRadius = 5
        ratingBadge.layer?.masksToBounds = true
        ratingBadge.isHidden = true
        addSubview(ratingBadge)
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
        preview.frame = NSRect(x: filmstrip ? 2 : 0, y: 0, width: max(1, bounds.width - (filmstrip ? 4 : 0)), height: maxHeight)
        preview.layer?.cornerRadius = filmstrip ? 6 : 10
        selectionRing.frame = preview.frame.insetBy(dx: -2, dy: -2)
        selectionRing.layer?.cornerRadius = filmstrip ? 8 : 12
        filename.font = .systemFont(ofSize: filmstrip ? 9 : 12)
        filename.stringValue = filmstrip ? (photo?.name as NSString?)?.deletingPathExtension ?? "" : photo?.name ?? ""
        let nameWidth = min(bounds.width, filename.intrinsicContentSize.width + 16)
        filename.frame = NSRect(x: (bounds.width - nameWidth) / 2, y: maxHeight + 5, width: nameWidth, height: filmstrip ? 16 : 22)
        ratingBadge.frame = NSRect(x: 8, y: 7, width: 36, height: 18)
    }
}

final class ThumbnailItem: NSCollectionViewItem {
    var thumbnail: ThumbnailView { view as! ThumbnailView }
    private var imageTask: Task<Void, Never>?
    override func loadView() { view = ThumbnailView(frame: .zero) }
    override var isSelected: Bool { didSet { if isViewLoaded { thumbnail.selected = isSelected } } }

    func configure(_ photo: Photo, filmstrip: Bool = false, rating: Int = 0) {
        imageTask?.cancel()
        thumbnail.photo = photo
        thumbnail.filmstrip = filmstrip
        thumbnail.rating = rating
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
