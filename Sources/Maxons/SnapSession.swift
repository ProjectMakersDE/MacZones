import Cocoa

/// Owns the on-screen zone overlays during a snap gesture and tracks which
/// zone(s) the cursor is over. Used by both trigger modes (right-click drag and
/// shake-while-dragging).
///
/// Multi-zone selection: the first zone entered becomes the "anchor". The snap
/// target is the bounding box of the anchor zone and the zone currently under
/// the cursor, so dragging across several adjacent zones spans them.
final class SnapSession {
    static let shared = SnapSession()

    private(set) var active = false

    private var overlays: [String: ZoneOverlayWindow] = [:]   // screenKey -> overlay

    private var anchorScreenKey: String?
    private var anchorZoneID: UUID?
    private var targetRectCG: CGRect?     // window frame to apply, or nil

    func begin() {
        guard !active else { return }
        ScreenManager.shared.refresh()
        active = true
        anchorScreenKey = nil
        anchorZoneID = nil
        targetRectCG = nil

        for ctx in ScreenManager.shared.contexts {
            let zones = ProfileStore.shared.zones(forScreen: ctx.key)
            guard !zones.isEmpty else { continue }
            let win = ZoneOverlayWindow(context: ctx, zones: zones)
            win.orderFrontRegardless()
            overlays[ctx.key] = win
        }
    }

    /// Feed the current global cursor position (Quartz / top-left coords).
    func update(globalPoint p: CGPoint) {
        guard active else { return }

        guard let loc = ScreenManager.shared.locate(p) else {
            clearHighlightOnly()
            return
        }
        let ctx = loc.ctx
        let zones = ProfileStore.shared.zones(forScreen: ctx.key)
        guard let hit = zones.first(where: { $0.contains(nx: loc.nx, ny: loc.ny) }) else {
            clearHighlightOnly()
            return
        }

        // (Re)anchor when starting fresh or moving onto a different screen.
        if anchorZoneID == nil || anchorScreenKey != ctx.key {
            anchorScreenKey = ctx.key
            anchorZoneID = hit.id
        }
        let anchor = zones.first(where: { $0.id == anchorZoneID }) ?? hit

        // Union for the real window (Quartz coords).
        let unionCG = ScreenManager.shared.cgRect(for: anchor, in: ctx)
            .union(ScreenManager.shared.cgRect(for: hit, in: ctx))
        targetRectCG = unionCG

        // Union for the highlight (view coords of this screen's overlay).
        let unionView = ScreenManager.shared.viewRect(for: anchor, boundsSize: ctx.boundsSize)
            .union(ScreenManager.shared.viewRect(for: hit, boundsSize: ctx.boundsSize))

        for (key, win) in overlays {
            win.setHighlight(key == ctx.key ? unionView : nil)
        }
    }

    /// Clear the visible highlight but keep the anchor, so re-entering a zone
    /// continues the same multi-zone selection.
    private func clearHighlightOnly() {
        targetRectCG = nil
        for (_, win) in overlays { win.setHighlight(nil) }
    }

    /// Tear down overlays and return the frame (Quartz coords) to snap to, if any.
    @discardableResult
    func end() -> CGRect? {
        let target = targetRectCG
        active = false
        for (_, win) in overlays { win.orderOut(nil) }
        overlays.removeAll()
        anchorScreenKey = nil
        anchorZoneID = nil
        targetRectCG = nil
        return target
    }

    func cancel() {
        targetRectCG = nil
        _ = end()
    }
}
