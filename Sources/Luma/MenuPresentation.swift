import AppKit

struct MenuAnchor {
    let view: NSView
    let point: NSPoint
    let rect: NSRect
    var preferredEdge: NSRectEdge { view.isFlipped ? .maxY : .minY }
    var screenPoint: NSPoint? { view.window?.convertPoint(toScreen: view.convert(point, to: nil)) }

    init(below view: NSView) {
        self.view = view
        rect = view.bounds
        let x = view.userInterfaceLayoutDirection == .rightToLeft ? view.bounds.maxX : view.bounds.minX
        point = NSPoint(x: x, y: view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4)
    }
    init(fallback view: NSView) {
        self.view = view
        point = NSPoint(x: view.bounds.midX, y: view.isFlipped ? view.bounds.minY + 8 : view.bounds.maxY - 8)
        rect = NSRect(origin: point, size: NSSize(width: 1, height: 1))
    }
}

final class MenuPresenter {
    var onTrackingChange: ((Bool) -> Void)?
    #if DEBUG
    var onWillPresent: ((NSMenu, MenuAnchor) -> Void)?
    #endif
    func present(_ menu: NSMenu, at anchor: MenuAnchor) {
        onTrackingChange?(true)
        defer { onTrackingChange?(false) }
        #if DEBUG
        onWillPresent?(menu, anchor)
        #endif
        menu.popUp(positioning: nil, at: anchor.point, in: anchor.view)
    }
}
