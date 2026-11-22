import AppKit
import LumaCore

final class MetadataRow: FlippedView {
    let name: NSTextField
    let value: NSTextField

    init(_ title: String, _ text: String) {
        name = label(title, size: 11, color: .secondaryLabelColor)
        value = label(text, size: 12)
        super.init(frame: .zero)
        value.isSelectable = true
        value.usesSingleLineMode = false
        value.maximumNumberOfLines = 0
        value.lineBreakMode = .byWordWrapping
        value.cell?.wraps = true
        value.cell?.isScrollable = false
        value.toolTip = text
        addSubview(name)
        addSubview(value)
        setAccessibilityLabel("\(title)：\(text)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func preferredHeight(width: CGFloat) -> CGFloat { max(22, wrappedHeight(value, width: width - 82) + 4) }
    override func layout() {
        super.layout()
        name.frame = NSRect(x: 0, y: 3, width: 72, height: 16)
        value.frame = NSRect(x: 82, y: 2, width: max(1, bounds.width - 82), height: max(18, bounds.height - 4))
    }
}

private func wrappedHeight(_ field: NSTextField, width: CGFloat) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let rect = (field.stringValue as NSString).boundingRect(
        with: NSSize(width: max(1, width), height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: field.font ?? NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph])
    return ceil(rect.height) + 2
}

final class InspectorView: NSVisualEffectView, NSTokenFieldDelegate {
    private let heading = label("照片信息", size: 12, weight: .medium)
    private let close = ActionButton(symbol: "sidebar.right", title: "隐藏检查器", size: 13)
    private let scroll = NSScrollView()
    private let document = FlippedView(frame: .zero)
    private let location = label(size: 10, color: .secondaryLabelColor)
    private let reveal = ActionButton(symbol: "arrow.up.right.square", title: "在 Finder 中显示", size: 12)
    private let tags = NSTokenField()
    let ratingMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appState: AppState
    private var renderedPhoto: Photo?
    private struct Block {
        let view: NSView
        let height: (CGFloat) -> CGFloat
        let gap: CGFloat
    }
    private var blocks: [Block] = []
    private(set) var rows: [MetadataRow] = []
    private(set) var displayedName = ""
    var onReveal: (() -> Void)?

    init(state: AppState) {
        appState = state
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .withinWindow
        self.state = .active
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        close.actionHandler = { [weak state] in state?.toggleInspector() }
        reveal.actionHandler = { [weak self] in self?.onReveal?() }
        tags.font = .systemFont(ofSize: 12)
        tags.placeholderString = "添加标签"
        tags.tokenStyle = .rounded
        tags.delegate = self
        tags.target = self
        tags.action = #selector(saveTags)
        tags.setAccessibilityLabel("照片标签")
        ratingMenu.font = .systemFont(ofSize: 12)
        ratingMenu.controlSize = .small
        for score in 0...9 { ratingMenu.addItem(withTitle: score == 0 ? "未评分" : "★  \(score) 级") }
        ratingMenu.target = self
        ratingMenu.action = #selector(rate)
        ratingMenu.setAccessibilityLabel("照片评分")
        for view in [heading, close, scroll, location, reveal] { addSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 20, y: bounds.height - 33, width: bounds.width - 76, height: 18)
        close.frame = NSRect(x: bounds.width - 45, y: bounds.height - 38, width: 28, height: 28)
        scroll.frame = NSRect(x: 0, y: 48, width: bounds.width, height: max(0, bounds.height - 94))
        let width = max(1, scroll.contentSize.width - 40)
        var y: CGFloat = 10
        for block in blocks {
            let height = block.height(width)
            block.view.frame = NSRect(x: 20, y: y, width: width, height: height)
            if let host = block.view as? RatingHostView { host.arrange(width: width) }
            if let host = block.view as? DimensionsView { host.arrange(width: width) }
            y += height + block.gap
        }
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, y + 18))
        location.frame = NSRect(x: 20, y: 16, width: bounds.width - 70, height: 18)
        reveal.frame = NSRect(x: bounds.width - 45, y: 12, width: 28, height: 28)
    }

    func update(_ photo: Photo?) {
        guard let photo else { return }
        ratingMenu.selectItem(at: appState.rating(for: photo.id))
        guard renderedPhoto != photo else { return }
        saveTags()
        renderedPhoto = photo
        displayedName = photo.name
        for block in blocks { block.view.removeFromSuperview() }
        blocks.removeAll()
        rows.removeAll()
        func add(_ view: NSView, height: CGFloat, gap: CGFloat = 8) {
            document.addSubview(view)
            blocks.append(Block(view: view, height: { _ in height }, gap: gap))
        }
        func section(_ title: String) {
            let divider = NSBox()
            divider.boxType = .separator
            add(divider, height: 1, gap: 16)
            add(label(title, size: 11, color: .secondaryLabelColor, weight: .medium), height: 18, gap: 8)
        }
        func row(_ title: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            let row = MetadataRow(title, value)
            rows.append(row)
            document.addSubview(row)
            blocks.append(Block(view: row, height: { row.preferredHeight(width: $0) }, gap: 4))
        }
        func date(_ value: Date?) -> String? {
            guard let value else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            return formatter.string(from: value)
        }
        let name = label(photo.name, size: 15, weight: .semibold)
        name.isSelectable = true
        name.usesSingleLineMode = false
        name.maximumNumberOfLines = 3
        name.lineBreakMode = .byWordWrapping
        name.cell?.wraps = true
        name.toolTip = photo.url.lastPathComponent
        document.addSubview(name)
        blocks.append(Block(view: name, height: { min(60, max(22, wrappedHeight(name, width: $0))) }, gap: 6))
        let metadata = photo.metadata
        add(label(metadata.typeDescription + (metadata.bitDepth.map { " · \($0) 位" } ?? ""), size: 11, color: .secondaryLabelColor), height: 18, gap: 16)
        add(DimensionsView(metadata: metadata), height: 28, gap: 20)
        section("评分")
        add(RatingHostView(menu: ratingMenu), height: 30, gap: 18)
        section("图像")
        row("文件大小", metadata.fileSize)
        row("色彩空间", metadata.colorProfile)
        section("拍摄")
        let hasCapture = metadata.camera != nil || metadata.lens != nil || metadata.capturedAt != nil || metadata.exposureDescription != nil || metadata.iso != nil
        if hasCapture {
            row("拍摄时间", date(metadata.capturedAt))
            row("相机", metadata.camera)
            row("镜头", metadata.lens)
            row("焦距", metadata.focalLength.map { String(format: "%g mm", $0) })
            row("光圈", metadata.aperture.flatMap { $0 > 0 ? String(format: "ƒ/%g", $0) : nil })
            row("快门", metadata.exposureDescription)
            row("ISO", metadata.iso.map(String.init))
            row("曝光补偿", metadata.exposureBias.map { String(format: "%+.1f EV", $0) })
        } else {
            add(label("未记录拍摄信息", size: 11, color: .tertiaryLabelColor), height: 20, gap: 10)
        }
        section("文件")
        row("创建时间", date(metadata.createdAt))
        row("修改时间", date(metadata.modifiedAt))
        row("位置", photo.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        section("标签")
        tags.objectValue = appState.defaults.stringArray(forKey: "tags:\(photo.id)") ?? []
        add(tags, height: 30)
        location.stringValue = appState.path
        location.toolTip = photo.url.path
        scroll.contentView.scroll(to: .zero)
        needsLayout = true
    }
    @objc private func rate() { appState.setRating(ratingMenu.indexOfSelectedItem) }
    @objc private func saveTags() {
        guard let id = renderedPhoto?.id, FileManager.default.fileExists(atPath: id) else { return }
        let values = (tags.objectValue as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        appState.defaults.set(values, forKey: "tags:\(id)")
    }
    func controlTextDidEndEditing(_ obj: Notification) { saveTags() }
}

private final class RatingHostView: FlippedView {
    let picker: NSPopUpButton
    let shortcut = label("⌃0～9", size: 11, color: .tertiaryLabelColor)
    init(menu: NSPopUpButton) {
        self.picker = menu
        super.init(frame: .zero)
        addSubview(menu); addSubview(shortcut)
        shortcut.alignment = .right
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func arrange(width: CGFloat) {
        picker.frame = NSRect(x: 0, y: 1, width: 152, height: 26)
        shortcut.frame = NSRect(x: 168, y: 7, width: max(0, width - 168), height: 18)
    }
}

private final class DimensionsView: FlippedView {
    let pixels: NSTextField
    let megapixels: NSTextField
    init(metadata: ImageMetadata) {
        pixels = label("\(metadata.pixelWidth) × \(metadata.pixelHeight)", size: 18, weight: .medium)
        megapixels = label(metadata.megapixels, size: 11, color: .secondaryLabelColor)
        super.init(frame: .zero)
        megapixels.alignment = .right
        addSubview(pixels); addSubview(megapixels)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func arrange(width: CGFloat) {
        pixels.frame = NSRect(x: 0, y: 1, width: max(0, width - 72), height: 26)
        megapixels.frame = NSRect(x: width - 70, y: 8, width: 70, height: 18)
    }
}
