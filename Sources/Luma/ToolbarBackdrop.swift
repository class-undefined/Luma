import AppKit

private final class ToolbarTintView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        NSColor(calibratedWhite: dark ? 0.10 : 0.97, alpha: opaque ? 1 : 0.97).setFill()
        bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class ToolbarBackdrop: NSVisualEffectView {
    private let tint = ToolbarTintView()
    private let separator = NSBox()
    private var hoverArea: NSTrackingArea?
    private(set) var isHovered = false
    private var trackedMenus = 0
    private(set) var showsBackground = false
    var onVisibilityChange: ((Bool) -> Void)?
    var isEnabled = true { didSet { updateVisibility(animated: false) } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .titlebar
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        alphaValue = 0
        addSubview(tint)
        separator.boxType = .separator
        addSubview(separator)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        tint.frame = bounds
        separator.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        refreshPointer()
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func updatePointer(_ location: NSPoint?) {
        setHovered(location.map { bounds.contains(convert($0, from: nil)) } ?? false)
    }
    func refreshPointer() { updatePointer(window?.mouseLocationOutsideOfEventStream) }
    func trackMenu(_ tracking: Bool) {
        trackedMenus = max(0, trackedMenus + (tracking ? 1 : -1))
        if !tracking { refreshPointer() }
        updateVisibility()
    }
    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateVisibility()
    }
    private func updateVisibility(animated: Bool = true) {
        let visible = isEnabled && (isHovered || trackedMenus > 0)
        guard visible != showsBackground else { return }
        showsBackground = visible
        onVisibilityChange?(visible)
        let opacity: CGFloat = visible ? 1 : 0
        if animated && window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                animator().alphaValue = opacity
            }
        } else { alphaValue = opacity }
    }
}
