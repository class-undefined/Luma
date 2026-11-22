import AppKit
import LumaCore

final class InspectorView: NSVisualEffectView, NSTokenFieldDelegate {
    private let heading = label("信息", size: 13, weight: .semibold)
    private let close = ActionButton(symbol: "sidebar.right", title: "隐藏检查器")
    private let scroll = NSScrollView()
    private let document = FlippedView(frame: .zero)
    private let stack = NSStackView()
    private let location = label(size: 11, color: .secondaryLabelColor)
    private let reveal = ActionButton(symbol: "arrow.up.right.square", title: "在 Finder 中显示", size: 13)
    private let tags = NSTokenField()
    private var photoID: String?
    private let appState: AppState
    var onReveal: (() -> Void)?

    init(state: AppState) {
        self.appState = state
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .withinWindow
        stateOn()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 24, right: 20)
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        close.actionHandler = { [weak state] in state?.toggleInspector() }
        reveal.actionHandler = { [weak self] in self?.onReveal?() }
        tags.font = .systemFont(ofSize: 11)
        tags.placeholderString = "添加标签"
        tags.tokenStyle = .rounded
        tags.delegate = self
        tags.target = self
        tags.action = #selector(saveTags)
        tags.heightAnchor.constraint(equalToConstant: 30).isActive = true
        tags.setAccessibilityLabel("图像标签")
        for subview in [heading, close, scroll, location, reveal] { addSubview(subview) }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func stateOn() { self.state = .active }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 20, y: bounds.height - 32, width: 150, height: 20)
        close.frame = NSRect(x: bounds.width - 48, y: bounds.height - 37, width: 30, height: 30)
        scroll.frame = NSRect(x: 0, y: 62, width: bounds.width, height: max(0, bounds.height - 118))
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, stack.fittingSize.height))
        stack.frame.size.width = document.bounds.width
        location.frame = NSRect(x: 20, y: 22, width: bounds.width - 70, height: 18)
        reveal.frame = NSRect(x: bounds.width - 47, y: 17, width: 28, height: 28)
    }

    func update(_ photo: Photo?) {
        guard let photo else { return }
        guard photoID != photo.id else { return }
        // Commit the previous field before changing the selected photo.
        if photoID != photo.id { saveTags() }
        photoID = photo.id
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        func divider() {
            let line = NSBox(); line.boxType = .separator
            add(line); line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }
        func row(_ name: String, _ value: String) -> NSView {
            let pair = NSStackView(views: [label(name, color: .secondaryLabelColor), label(value)])
            pair.orientation = .horizontal
            pair.spacing = 12
            pair.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 60).isActive = true
            return pair
        }
        add(label(photo.name, size: 14, weight: .semibold))
        add(label("\(photo.metadata.format) 图像", size: 12, color: .secondaryLabelColor))
        divider()
        add(label("文件信息", size: 12, weight: .medium))
        add(row("尺寸", photo.metadata.dimensions))
        add(row("大小", photo.metadata.fileSize))
        add(row("色彩描述", photo.metadata.colorProfile))
        let date = photo.metadata.createdAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—"
        add(row("创建时间", date))
        divider()
        add(label("拍摄信息", size: 12, weight: .medium))
        if let camera = photo.metadata.camera {
            add(label(camera))
            if let lens = photo.metadata.lens { add(label(lens, size: 11, color: .secondaryLabelColor)) }
            add(row("焦距", photo.metadata.focalLength.map { "\(String(format: "%g", $0)) mm" } ?? "—"))
            add(row("光圈", photo.metadata.aperture.map { "ƒ/\(String(format: "%g", $0))" } ?? "—"))
            add(row("曝光时间", photo.metadata.exposure.map { $0 > 0 && $0 < 1 ? "1/\(Int((1 / $0).rounded())) s" : "\(String(format: "%g", $0)) s" } ?? "—"))
            add(row("ISO 速度", photo.metadata.iso.map(String.init) ?? "—"))
        } else {
            add(label("此图像未包含相机信息。", size: 11, color: .secondaryLabelColor))
        }
        divider()
        add(label("标签", size: 12, weight: .medium))
        tags.objectValue = appState.defaults.stringArray(forKey: "tags:\(photo.id)") ?? []
        add(tags)
        add(label("标签保存在 Luma 中。", size: 10, color: .tertiaryLabelColor))
        location.stringValue = appState.path
        location.toolTip = photo.url.path
        needsLayout = true
    }
    @objc private func saveTags() {
        guard let photoID else { return }
        let values = (tags.objectValue as? [String] ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        appState.defaults.set(values, forKey: "tags:\(photoID)")
    }
    func controlTextDidEndEditing(_ obj: Notification) { saveTags() }
}
