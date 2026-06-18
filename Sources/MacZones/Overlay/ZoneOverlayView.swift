import Cocoa

/// Draws the zone outlines and the currently targeted (highlighted) area.
/// Non-interactive — its window is click-through.
final class ZoneOverlayView: NSView {
    var zones: [Zone] = [] { didSet { needsDisplay = true } }
    /// Highlight rectangle in this view's coordinate space (already flipped).
    var highlightRect: CGRect? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }   // AppKit default (bottom-left)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        let accent = NSColor.controlAccentColor

        for zone in zones {
            let r = ScreenManager.shared.viewRect(for: zone, boundsSize: b.size).insetBy(dx: 3, dy: 3)
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)

            accent.withAlphaComponent(0.10).setFill()
            path.fill()
            accent.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 2
            path.stroke()
        }

        if let hl = highlightRect {
            let r = hl.insetBy(dx: 3, dy: 3)
            let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
            accent.withAlphaComponent(0.30).setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 4
            path.stroke()
        }

        ctx.flush()
    }
}
