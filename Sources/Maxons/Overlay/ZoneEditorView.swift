import Cocoa

/// Interactive editor for one screen's zones. Bottom-left (AppKit) coordinates.
final class ZoneEditorView: NSView {
    var zones: [Zone] = [] { didSet { needsDisplay = true } }
    var onChange: (([Zone]) -> Void)?

    private enum Mode {
        case none
        case moving(index: Int, offset: CGSize)
        case resizing(index: Int, fixedTopLeft: CGPoint)  // (minX, maxY) kept fixed
        case creating(start: CGPoint)
    }
    private var mode: Mode = .none
    private var creatingRect: CGRect = .zero

    private let handleSize: CGFloat = 18
    private let deleteSize: CGFloat = 22

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

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Dim the screen slightly so it's obvious we're in edit mode.
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        let accent = NSColor.controlAccentColor

        for (i, zone) in zones.enumerated() {
            let r = rect(for: zone).insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            accent.withAlphaComponent(0.18).setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 2
            path.stroke()

            drawCenteredNumber(i + 1, in: r)
            drawResizeHandle(in: handleRect(for: rect(for: zone)))
            drawDeleteButton(in: deleteRect(for: rect(for: zone)))
        }

        if case .creating = mode, creatingRect.width > 2, creatingRect.height > 2 {
            let path = NSBezierPath(roundedRect: creatingRect, xRadius: 10, yRadius: 10)
            accent.withAlphaComponent(0.25).setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
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
                mode = .moving(index: i, offset: CGSize(width: p.x - r.minX, height: p.y - r.minY))
                return
            }
        }
        mode = .creating(start: p)
        creatingRect = CGRect(origin: p, size: .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        switch mode {
        case .moving(let i, let offset):
            guard zones.indices.contains(i) else { return }
            let r = rect(for: zones[i])
            var newOrigin = CGPoint(x: p.x - offset.width, y: p.y - offset.height)
            newOrigin.x = min(max(newOrigin.x, 0), bounds.width - r.width)
            newOrigin.y = min(max(newOrigin.y, 0), bounds.height - r.height)
            commitRect(CGRect(origin: newOrigin, size: r.size), toIndex: i)
            needsDisplay = true

        case .resizing(let i, let fixed):
            guard zones.indices.contains(i) else { return }
            let minDim: CGFloat = 40
            // `fixed` is the top-left corner (minX, maxY); the cursor is the
            // new bottom-right corner.
            let right = max(p.x, fixed.x + minDim)
            let bottom = min(p.y, fixed.y - minDim)
            let newRect = CGRect(x: fixed.x,
                                 y: bottom,
                                 width: right - fixed.x,
                                 height: fixed.y - bottom)
            commitRect(newRect, toIndex: i)
            needsDisplay = true

        case .creating(let start):
            creatingRect = CGRect(x: min(start.x, p.x),
                                  y: min(start.y, p.y),
                                  width: abs(p.x - start.x),
                                  height: abs(p.y - start.y))
            needsDisplay = true

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .creating:
            if creatingRect.width >= 40, creatingRect.height >= 40 {
                let z = ScreenManager.shared.zone(fromViewRect: creatingRect, boundsSize: bounds.size)
                zones.append(z)
            }
            creatingRect = .zero
        default:
            break
        }
        mode = .none
        onChange?(zones)
        needsDisplay = true
    }
}
