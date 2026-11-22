import AppKit
import LumaCore

final class ImageCanvas: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    private(set) var photo: Photo?
    private(set) var quarterTurns = 0
    private(set) var explicitScale: CGFloat?
    private(set) var pan = NSPoint.zero
    var onZoom: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    var orientedSize: NSSize {
        guard let photo else { return .zero }
        let size = NSSize(width: photo.metadata.pixelWidth, height: photo.metadata.pixelHeight)
        return quarterTurns % 2 == 0 ? size : NSSize(width: size.height, height: size.width)
    }
    var fitScale: CGFloat {
        let size = orientedSize
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(max(1, bounds.width - 32) / size.width, max(1, bounds.height - 32) / size.height)
    }
    var scale: CGFloat { explicitScale ?? fitScale }

    func display(_ photo: Photo) {
        if self.photo?.id != photo.id {
            self.photo = photo
            image = nil
            quarterTurns = 0
            explicitScale = nil
            pan = .zero
        }
        needsDisplay = true
        onZoom?(scale)
    }
    func zoom(by factor: CGFloat) {
        explicitScale = min(8, max(0.02, scale * factor))
        clampPan()
        needsDisplay = true
        onZoom?(scale)
    }
    func actualSize() { explicitScale = 1; pan = .zero; needsDisplay = true; onZoom?(scale) }
    func fit() { explicitScale = nil; pan = .zero; needsDisplay = true; onZoom?(scale) }
    func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
        pan = .zero
        needsDisplay = true
        onZoom?(scale)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        clampPan()
        needsDisplay = true
        onZoom?(scale)
    }
    private func clampPan() {
        let maxX = max(0, (orientedSize.width * scale - bounds.width + 32) / 2)
        let maxY = max(0, (orientedSize.height * scale - bounds.height + 32) / 2)
        pan.x = min(maxX, max(-maxX, pan.x))
        pan.y = min(maxY, max(-maxY, pan.y))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        bounds.fill()
        guard let image, let photo else { return }
        let context = NSGraphicsContext.current!
        context.saveGraphicsState()
        let transform = AffineTransform(translationByX: bounds.midX + pan.x, byY: bounds.midY + pan.y)
        (transform as NSAffineTransform).concat()
        let rotate = NSAffineTransform()
        rotate.rotate(byDegrees: CGFloat(quarterTurns) * 90)
        rotate.concat()
        let width = CGFloat(photo.metadata.pixelWidth) * scale
        let height = CGFloat(photo.metadata.pixelHeight) * scale
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        context.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            if explicitScale == nil { actualSize() } else { fit() }
            onDoubleClick?()
        }
    }
    override func mouseDragged(with event: NSEvent) {
        pan.x += event.deltaX
        pan.y -= event.deltaY
        clampPan()
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            zoom(by: pow(1.012, event.scrollingDeltaY))
        } else {
            pan.x += event.scrollingDeltaX
            pan.y -= event.scrollingDeltaY
            clampPan()
            needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) { zoom(by: 1 + event.magnification) }
    override func smartMagnify(with event: NSEvent) { if explicitScale == nil { actualSize() } else { fit() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: explicitScale == nil ? .arrow : .openHand) }
}
