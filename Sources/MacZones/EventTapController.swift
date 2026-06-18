import Cocoa
import ApplicationServices

/// The single source of runtime activity. A passive session-level CGEventTap
/// listening ONLY to mouse button + drag events. It produces no callbacks when
/// no button is held, so the app costs ~nothing at idle.
///
/// During a normal LEFT-button window drag, zones can be summoned two ways:
///  - Shake the window (if enabled).
///  - Tap the RIGHT button (if enabled): tap = toggle zones on/off, hold = build
///    a multi-zone selection (released → frozen).
/// Releasing the left button over a highlighted zone snaps the window there.
final class EventTapController {
    static let shared = EventTapController()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Marks events we synthesise so we never re-process our own injected clicks.
    fileprivate let syntheticMarker: Int64 = 0x4D43_5A4F_4E45   // arbitrary sentinel

    // Left-drag / snap-session state
    private var lmbDown = false
    private var snapArmed = false             // zones currently shown
    private var snapWindow: AXUIElement?      // the window to snap
    private let shake = ShakeDetector()

    // Right-button modifier state
    private var rightHeld = false
    private var rightDownTime: TimeInterval = 0
    private var zonesOnAtRightDown = false
    private var swallowRightUp = false        // we own this right gesture → swallow its up/drag

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: maczonesEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: Event handling (runs on the main run loop)

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // Re-enable if macOS disabled us (timeout / user input).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        // Ignore our own synthesised clicks.
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return pass
        }

        // Never interfere while the zone editor is open.
        if ZoneEditorController.shared.isOpen {
            return pass
        }

        switch type {
        case .rightMouseDown:    return onRightDown(event)
        case .rightMouseDragged: return onRightDragged(event)
        case .rightMouseUp:      return onRightUp(event)
        case .leftMouseDown:     return onLeftDown(event)
        case .leftMouseDragged:  return onLeftDragged(event)
        case .leftMouseUp:       return onLeftUp(event)
        default:                 return pass
        }
    }

    // MARK: Left-button drag (hosts both triggers)

    private func onLeftDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        lmbDown = true
        snapArmed = false
        snapWindow = nil
        rightHeld = false
        swallowRightUp = false
        shake.reset()
        // Left clicks/drags are never altered.
        return Unmanaged.passUnretained(event)
    }

    private func onLeftDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard lmbDown else { return pass }
        let loc = event.location

        // Shake toggles the zones (works even while already shown).
        if ProfileStore.shared.shakeEnabled {
            let now = ProcessInfo.processInfo.systemUptime
            if shake.feed(x: loc.x, time: now) {
                if snapArmed { dismissZones() } else { revealZones(at: loc) }
            }
        }

        // Drive the highlight from the left-drag stream (macOS suppresses
        // rightMouseDragged while the left button is held).
        if snapArmed {
            SnapSession.shared.update(globalPoint: loc, multi: rightHeld)
        }
        return pass
    }

    private func onLeftUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        defer {
            lmbDown = false
            let rightStillHeld = rightHeld
            rightHeld = false
            // If the right button is still down, its rightMouseUp is still
            // coming — keep swallowing it so no context menu pops after the snap.
            if !rightStillHeld { swallowRightUp = false }
            shake.reset()
        }
        if snapArmed {
            let target = SnapSession.shared.end()
            if let target = target, let win = snapWindow {
                // Let the app finish its own drag first, then snap.
                DispatchQueue.main.async { AX.setFrame(target, for: win) }
            }
            snapArmed = false
            snapWindow = nil
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Right-button modifier

    private func onRightDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Only act as a zone modifier during a left-drag, and only if enabled.
        guard ProfileStore.shared.rightClickDragEnabled, lmbDown else {
            return Unmanaged.passUnretained(event)
        }
        let loc = event.location
        let wasArmed = snapArmed
        if !snapArmed {
            revealZones(at: loc)
            guard snapArmed else {
                // Nothing snappable under the cursor — let the click behave normally.
                return Unmanaged.passUnretained(event)
            }
        }
        rightHeld = true
        rightDownTime = ProcessInfo.processInfo.systemUptime
        zonesOnAtRightDown = wasArmed
        swallowRightUp = true
        SnapSession.shared.beginMulti(at: loc)
        return nil   // swallow → no context menu mid-drag
    }

    private func onRightDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Usually not delivered while the left button is held, but swallow and
        // update defensively if it is.
        guard swallowRightUp else { return Unmanaged.passUnretained(event) }
        if snapArmed { SnapSession.shared.update(globalPoint: event.location, multi: true) }
        return nil
    }

    private func onRightUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard swallowRightUp else { return Unmanaged.passUnretained(event) }
        swallowRightUp = false
        rightHeld = false
        guard snapArmed else { return nil }   // left-up may have already ended the session

        let duration = ProcessInfo.processInfo.systemUptime - rightDownTime
        let outcome = classifyRightRelease(holdDuration: duration,
                                           didExpand: SnapSession.shared.didExpand,
                                           zonesWereOnBeforePress: zonesOnAtRightDown)
        switch outcome {
        case .dismiss:
            dismissZones()
        case .singleFollow, .freezeMulti:
            SnapSession.shared.endMulti()
        }
        return nil   // swallow
    }

    // MARK: Helpers

    /// Summon the zones and capture the window to snap. The dragged window always
    /// sits under the cursor, so capturing at the CURRENT location grabs the right
    /// window (capturing at the mouse-down location would grab whatever now sits
    /// at that vacated spot — the old "random other window" bug).
    private func revealZones(at loc: CGPoint) {
        guard let win = AX.windowUnderCursor(at: loc) else { return }
        snapWindow = win
        snapArmed = true
        SnapSession.shared.begin()
        SnapSession.shared.update(globalPoint: loc, multi: rightHeld)
    }

    private func dismissZones() {
        SnapSession.shared.cancel()
        snapArmed = false
        snapWindow = nil
    }
}

// C callback trampoline — captures nothing, forwards to the controller via refcon.
private func maczonesEventTapCallback(proxy: CGEventTapProxy,
                                    type: CGEventType,
                                    event: CGEvent,
                                    refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
