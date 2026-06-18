import Cocoa

/// Owns the on-screen zone overlays during a snap gesture and tracks which
/// zone(s) the cursor is over. Used by both triggers (right-button modifier and
/// shake-while-dragging).
///
/// Selection modes:
///  - single: the zone under the cursor is highlighted and follows the cursor.
///  - multi:  the anchor zone is fixed; the highlight spans the bounding box of
///            anchor + current zone, so dragging across adjacent zones unions them.
///  - frozen: after a real multi sweep the union is locked and ignores further
///            cursor movement until the session ends or is cancelled.
final class SnapSession {
    static let shared = SnapSession()

    private(set) var active = false

    private var overlays: [String: ZoneOverlayWindow] = [:]   // screenKey -> overlay

    private var anchorScreenKey: String?
    private var anchorZoneID: UUID?
    private var targetRectCG: CGRect?     // window frame to apply, or nil

    private var frozen = false
    /// True once a multi selection reached a zone other than the anchor.
    private(set) var didExpand = false

    func begin() {
        guard !active else { return }
        ScreenManager.shared.refresh()
        active = true
        anchorScreenKey = nil
        anchorZoneID = nil
        targetRectCG = nil
        frozen = false
        didExpand = false

        for ctx in ScreenManager.shared.contexts {
            let zones = ProfileStore.shared.zones(forScreen: ctx.key)
            guard !zones.isEmpty else { continue }
            let win = ZoneOverlayWindow(context: ctx, zones: zones)
            win.orderFrontRegardless()
            overlays[ctx.key] = win
        }
    }

    /// Begin a multi-zone selection anchored at the cursor's current zone.
    func beginMulti(at p: CGPoint) {
        guard active else { return }
        frozen = false
        didExpand = false
        anchorScreenKey = nil
        anchorZoneID = nil
        update(globalPoint: p, multi: true)
    }

    /// End a multi-zone selection. Freeze the union if it actually spanned more
    /// than the anchor; otherwise let single-zone following resume.
    func endMulti() {
        frozen = didExpand
    }

    /// Feed the current global cursor position (Quartz / top-left coords).
    /// `multi == true` keeps the anchor fixed and unions anchor → current zone;
    /// `multi == false` lets the single highlighted zone follow the cursor.
    func update(globalPoint p: CGPoint, multi: Bool) {
        guard active else { return }
        if frozen { return }   // locked selection ignores movement

        guard let loc = ScreenManager.shared.locate(p) else {
            if !multi { clearHighlightOnly() }
            return
        }
        let ctx = loc.ctx
        let zones = ProfileStore.shared.zones(forScreen: ctx.key)
        guard let hit = zones.first(where: { $0.contains(nx: loc.nx, ny: loc.ny) }) else {
            if !multi { clearHighlightOnly() }
            return
        }

        if multi {
            // Anchor once, then keep it fixed; note when the selection expands.
            if anchorZoneID == nil || anchorScreenKey != ctx.key {
                anchorScreenKey = ctx.key
                anchorZoneID = hit.id
            }
            if hit.id != anchorZoneID { didExpand = true }
        } else {
            // Single zone follows the cursor.
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

    /// Clear the visible highlight but keep the anchor.
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
        frozen = false
        didExpand = false
        return target
    }

    func cancel() {
        targetRectCG = nil
        _ = end()
    }
}
