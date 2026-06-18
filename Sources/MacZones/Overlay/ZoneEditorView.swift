import Cocoa

/// Interactive editor for one screen's zones. Bottom-left (AppKit) coordinates.
///
/// Primary interaction is *splitting*: click inside a zone to divide it at the
/// cursor (vertical by default, ⌥ for horizontal). You can also drag a zone to
/// move it, drag its bottom-right corner to resize, drag empty space to draw a
/// new zone, and click ✕ to delete.
final class ZoneEditorView: NSView {
    var zones: [Zone] = [] { didSet { needsDisplay = true } }
    var onChange: (([Zone]) -> Void)?

    private enum Mode {
        case none
        case pendingZone(index: Int, offset: CGSize)
        case pendingEmpty(start: CGPoint)
        case moving(index: Int, offset: CGSize)
        case resizing(index: Int, fixedTopLeft: CGPoint)
        case creating(start: CGPoint)
    }
    private var mode: Mode = .none
    private var creatingRect: CGRect = .zero
    private var mouseDownPoint: CGPoint = .zero
    private var dragOccurred = false
    private var splitVerticalPending = true

    private var hoverPoint: CGPoint?
    private var hoverSplitVertical = true

    private let handleSize: CGFloat = 18
    private let deleteSize: CGFloat = 22
    private let dragThreshold: CGFloat = 5
    private let minSide: CGFloat = 40

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry helpers

    private func rect(for zone: Zone) -> CGRect {
        ScreenManager.shared.viewRect(for: zone, boundsSize: bounds.size)
    }
    private func deleteRect(for r: CGRect) -> CGRect {
        CGRect(x: r.maxX - deleteSize - 6, y: r.maxY - deleteSize - 6, width: deleteSize, height: deleteSize)
    }
    private func handleRect(for r: CGRect) -> CGRect {
        CGRect(x: r.maxX - handleSize, y: r.minY, width: handleSize, height: handleSize)
    }
    private func commitRect(_ r: CGRect, toIndex i: Int) {
        guard zones.indices.contains(i) else { return }
        zones[i] = ScreenManager.shared.zone(fromViewRect: r, boundsSize: bounds.size, id: zones[i].id)
    }
    private func zoneIndex(at p: CGPoint) -> Int? {
        for i in stride(from: zones.count - 1, through: 0, by: -1) where rect(for: zones[i]).contains(p) {
            return i
        }
        return nil
    }

    // MARK: Tracking (for the split hover preview)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        hoverSplitVertical = !event.modifierFlags.contains(.option)
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        let accent = NSColor.controlAccentColor

        for (i, zone) in zones.enumerated() {
            let full = rect(for: zone)
            let r = full.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            accent.withAlphaComponent(0.18).setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 2
            path.stroke()

            drawCenteredNumber(i + 1, in: r)
            drawResizeHandle(in: handleRect(for: full))
            drawDeleteButton(in: deleteRect(for: full))
        }

        drawSplitPreview()

        if case .creating = mode, creatingRect.width > 2, creatingRect.height > 2 {
            let path = NSBezierPath(roundedRect: creatingRect, xRadius: 10, yRadius: 10)
            accent.withAlphaComponent(0.25).setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawSplitPreview() {
        guard let hp = hoverPoint, let idx = zoneIndex(at: hp) else { return }
        let r = rect(for: zones[idx])
        let line = NSBezierPath()
        line.lineWidth = 2
        line.setLineDash([7, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        if hoverSplitVertical {
            let x = min(max(hp.x, r.minX + minSide), r.maxX - minSide)
            line.move(to: CGPoint(x: x, y: r.minY + 6))
            line.line(to: CGPoint(x: x, y: r.maxY - 6))
        } else {
            let y = min(max(hp.y, r.minY + minSide), r.maxY - minSide)
            line.move(to: CGPoint(x: r.minX + 6, y: y))
            line.line(to: CGPoint(x: r.maxX - 6, y: y))
        }
        line.stroke()
    }

    private func drawCenteredNumber(_ n: Int, in r: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let s = "\(n)" as NSString
        let size = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawResizeHandle(in r: CGRect) {
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 2
        p.move(to: CGPoint(x: r.maxX - 3, y: r.minY + 3))
        p.line(to: CGPoint(x: r.maxX - 3, y: r.maxY - 3))
        p.line(to: CGPoint(x: r.minX + 3, y: r.maxY - 3))
        p.stroke()
    }

    private func drawDeleteButton(in r: CGRect) {
        NSColor.systemRed.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor.white.setStroke()
        let p = NSBezierPath()
        p.lineWidth = 2
        let inset = r.insetBy(dx: 6, dy: 6)
        p.move(to: CGPoint(x: inset.minX, y: inset.minY))
        p.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        p.move(to: CGPoint(x: inset.minX, y: inset.maxY))
        p.line(to: CGPoint(x: inset.maxX, y: inset.minY))
        p.stroke()
    }

    // MARK: Mouse handling

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseDownPoint = p
        dragOccurred = false
        splitVerticalPending = !event.modifierFlags.contains(.option)

        for i in stride(from: zones.count - 1, through: 0, by: -1) {
            let r = rect(for: zones[i])
            if deleteRect(for: r).contains(p) {
                zones.remove(at: i)
                onChange?(zones)
                needsDisplay = true
                return
            }
            if handleRect(for: r).contains(p) {
                mode = .resizing(index: i, fixedTopLeft: CGPoint(x: r.minX, y: r.maxY))
                return
            }
            if r.contains(p) {
                mode = .pendingZone(index: i, offset: CGSize(width: p.x - r.minX, height: p.y - r.minY))
                return
            }
        }
        mode = .pendingEmpty(start: p)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !dragOccurred, hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > dragThreshold {
            dragOccurred = true
        }

        switch mode {
        case .pendingZone(let i, let off):
            if dragOccurred { mode = .moving(index: i, offset: off); moveZone(i, to: p, offset: off) }
        case .pendingEmpty(let start):
            if dragOccurred { mode = .creating(start: start); updateCreating(to: p, start: start) }
        case .moving(let i, let off):
            moveZone(i, to: p, offset: off)
        case .resizing(let i, let fixed):
            resizeZone(i, to: p, fixed: fixed)
        case .creating(let start):
            updateCreating(to: p, start: start)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .pendingZone(let i, _):
            if !dragOccurred { split(zoneAt: i, at: mouseDownPoint, vertical: splitVerticalPending) }
        case .creating:
            if creatingRect.width >= minSide, creatingRect.height >= minSide {
                zones.append(ScreenManager.shared.zone(fromViewRect: creatingRect, boundsSize: bounds.size))
            }
            creatingRect = .zero
        default:
            break
        }
        mode = .none
        dragOccurred = false
        onChange?(zones)
        needsDisplay = true
    }

    // MARK: Edits

    private func moveZone(_ i: Int, to p: CGPoint, offset: CGSize) {
        guard zones.indices.contains(i) else { return }
        let r = rect(for: zones[i])
        var origin = CGPoint(x: p.x - offset.width, y: p.y - offset.height)
        origin.x = min(max(origin.x, 0), bounds.width - r.width)
        origin.y = min(max(origin.y, 0), bounds.height - r.height)
        commitRect(CGRect(origin: origin, size: r.size), toIndex: i)
        needsDisplay = true
    }

    private func resizeZone(_ i: Int, to p: CGPoint, fixed: CGPoint) {
        guard zones.indices.contains(i) else { return }
        let right = max(p.x, fixed.x + minSide)
        let bottom = min(p.y, fixed.y - minSide)
        commitRect(CGRect(x: fixed.x, y: bottom, width: right - fixed.x, height: fixed.y - bottom), toIndex: i)
        needsDisplay = true
    }

    private func updateCreating(to p: CGPoint, start: CGPoint) {
        creatingRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    /// Divide the zone at `index` into two at point `p` (view coords).
    private func split(zoneAt index: Int, at p: CGPoint, vertical: Bool) {
        guard zones.indices.contains(index) else { return }
        let r = rect(for: zones[index])
        let id = zones[index].id

        if vertical {
            guard p.x - r.minX >= minSide, r.maxX - p.x >= minSide else { NSSound.beep(); return }
            let left = CGRect(x: r.minX, y: r.minY, width: p.x - r.minX, height: r.height)
            let right = CGRect(x: p.x, y: r.minY, width: r.maxX - p.x, height: r.height)
            zones[index] = ScreenManager.shared.zone(fromViewRect: left, boundsSize: bounds.size, id: id)
            zones.insert(ScreenManager.shared.zone(fromViewRect: right, boundsSize: bounds.size), at: index + 1)
        } else {
            guard p.y - r.minY >= minSide, r.maxY - p.y >= minSide else { NSSound.beep(); return }
            // In bottom-left coords the upper part has the larger y.
            let top = CGRect(x: r.minX, y: p.y, width: r.width, height: r.maxY - p.y)
            let bottom = CGRect(x: r.minX, y: r.minY, width: r.width, height: p.y - r.minY)
            zones[index] = ScreenManager.shared.zone(fromViewRect: top, boundsSize: bounds.size, id: id)
            zones.insert(ScreenManager.shared.zone(fromViewRect: bottom, boundsSize: bounds.size), at: index + 1)
        }
        needsDisplay = true
    }
}
