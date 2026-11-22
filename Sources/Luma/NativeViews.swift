import AppKit

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SurfaceView: FlippedView {
    var color: NSColor { didSet { needsDisplay = true } }
    init(_ color: NSColor) { self.color = color; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

func label(_ text: String = "", size: CGFloat = 12, color: NSColor = .labelColor,
           weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
}

final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?

    init(symbol: String, title: String, size: CGFloat = 16, action: (() -> Void)? = nil) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        symbolConfiguration = .init(pointSize: size, weight: .regular, scale: .small)
        imageScaling = .scaleProportionallyDown
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .toolbar
        toolTip = title
        setAccessibilityLabel(title)
        target = self
        self.action = #selector(invoke)
        actionHandler = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionHandler?() }
}

final class DropView: FlippedView {
    var onDrop: (([URL]) -> Void)?
    private var highlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func urls(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = !urls(sender).isEmpty
        needsDisplay = true
        return highlighted ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !urls(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        needsDisplay = true
        let dropped = urls(sender)
        guard !dropped.isEmpty else { return false }
        onDrop?(dropped)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            bounds.fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10)
            path.lineWidth = 3
            path.stroke()
        }
    }
}

final class EmptyView: FlippedView {
    let heading = label("未打开图像", size: 20, weight: .semibold)
    let detail = label("拖入图片或文件夹，或选择本地文件。", size: 13, color: .secondaryLabelColor)
    let icon = NSImageView()
    let open = NSButton(title: "打开…", target: nil, action: nil)
    let demo = NSButton(title: "打开示例图库", target: nil, action: nil)
    let formats = label("JPEG、PNG、HEIC、WebP、GIF、TIFF、RAW", size: 11, color: .tertiaryLabelColor)
    let shortcut = label("⌘O", size: 11, color: .tertiaryLabelColor)
    var onOpen: (() -> Void)?
    var onDemo: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
        icon.contentTintColor = .tertiaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        open.bezelStyle = .rounded
        open.controlSize = .large
        open.bezelColor = .controlAccentColor
        open.keyEquivalent = ""
        open.target = self
        open.action = #selector(openFiles)
        demo.bezelStyle = .inline
        demo.font = .systemFont(ofSize: 11)
        demo.contentTintColor = .secondaryLabelColor
        demo.target = self
        demo.action = #selector(openDemo)
        for v in [icon, heading, detail, open, demo, formats, shortcut] { addSubview(v) }
        heading.alignment = .center
        detail.alignment = .center
        formats.alignment = .center
        shortcut.alignment = .center
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func openFiles() { onOpen?() }
    @objc private func openDemo() { onDemo?() }
    override func layout() {
        super.layout()
        let center = bounds.midX
        let top = max(48, bounds.height * 0.27)
        icon.frame = NSRect(x: center - 32, y: top, width: 64, height: 56)
        heading.frame = NSRect(x: 20, y: top + 85, width: bounds.width - 40, height: 28)
        detail.frame = NSRect(x: 20, y: top + 124, width: bounds.width - 40, height: 22)
        open.frame = NSRect(x: center - 48, y: top + 174, width: 96, height: 34)
        shortcut.frame = NSRect(x: center - 40, y: top + 226, width: 80, height: 18)
        demo.frame = NSRect(x: center - 65, y: top + 261, width: 130, height: 24)
        formats.frame = NSRect(x: 20, y: bounds.height - 50, width: bounds.width - 40, height: 18)
    }
}
