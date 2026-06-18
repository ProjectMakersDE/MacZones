import Cocoa
import ApplicationServices

/// The single source of runtime activity. A passive session-level CGEventTap
/// listening ONLY to mouse button + drag events. It produces no callbacks when
/// no button is held, so the app costs ~nothing at idle.
///
/// Two trigger modes (each independently toggleable):
///  1. Right-button drag  — hold the right mouse button over a window and drag;
///     the window follows the cursor, zones appear, release snaps it.
///  2. Shake while dragging — drag a window normally and give it a quick shake;
///     zones appear, release over a zone snaps it.
final class EventTapController {
    static let shared = EventTapController()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Marks events we synthesise so we never re-process our own injected clicks.
    fileprivate let syntheticMarker: Int64 = 0x4D43_5A4F_4E45   // arbitrary sentinel
    private let dragThreshold: CGFloat = 6

    // Right-button drag state
    private enum RMBState { case idle, pending, moving }
    private var rmb: RMBState = .idle
    private var rmbDownLocation: CGPoint = .zero
    private var grabWindow: AXUIElement?
    private var grabOffset: CGSize = .zero

    // Left-drag / shake state
    private var lmbDown = false
    private var lmbDownLocation: CGPoint = .zero
    private var shakeActive = false
    private var shakeWindow: AXUIElement?
    private let shake = ShakeDetector()

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

    // MARK: Right-button drag mode

    private func onRightDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard ProfileStore.shared.rightClickDragEnabled else {
            return Unmanaged.passUnretained(event)
        }
        rmb = .pending
        rmbDownLocation = event.location
        grabWindow = nil
        // Swallow for now. If it turns out to be a plain click (no drag) we
        // re-synthesise the right-click on mouse-up so context menus still work.
        return nil
    }

    private func onRightDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard ProfileStore.shared.rightClickDragEnabled else {
            return Unmanaged.passUnretained(event)
        }
        let loc = event.location

        switch rmb {
        case .idle:
            return Unmanaged.passUnretained(event)

        case .pending:
            let moved = hypot(loc.x - rmbDownLocation.x, loc.y - rmbDownLocation.y)
            if moved >= dragThreshold {
                if let win = AX.windowUnderCursor(at: rmbDownLocation),
                   let frame = AX.frame(of: win) {
                    grabWindow = win
                    grabOffset = CGSize(width: rmbDownLocation.x - frame.minX,
                                        height: rmbDownLocation.y - frame.minY)
                    rmb = .moving
                    SnapSession.shared.begin()
                    moveGrabWindow(to: loc)
                    SnapSession.shared.update(globalPoint: loc)
                } else {
                    // Nothing grabbable under the cursor — give up on this gesture.
                    rmb = .idle
                }
            }
            return nil

        case .moving:
            moveGrabWindow(to: loc)
            SnapSession.shared.update(globalPoint: loc)
            return nil
        }
    }

    private func onRightUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard ProfileStore.shared.rightClickDragEnabled else {
            return Unmanaged.passUnretained(event)
        }
        switch rmb {
        case .idle:
            return Unmanaged.passUnretained(event)

        case .pending:
            // No drag happened → it was a normal right-click. Replay it.
            rmb = .idle
            resynthesizeRightClick(at: event.location)
            return nil

        case .moving:
            let target = SnapSession.shared.end()
            if let target = target, let win = grabWindow {
                AX.setFrame(target, for: win)
            }
            grabWindow = nil
            rmb = .idle
            return nil
        }
    }

    private func moveGrabWindow(to cursor: CGPoint) {
        guard let win = grabWindow else { return }
        let origin = CGPoint(x: cursor.x - grabOffset.width,
                             y: cursor.y - grabOffset.height)
        AX.setPosition(origin, for: win)
    }

    private func resynthesizeRightClick(at location: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown,
                              mouseCursorPosition: location, mouseButton: .right) {
            down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp,
                            mouseCursorPosition: location, mouseButton: .right) {
            up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            up.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: Shake-while-dragging mode

    private func onLeftDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if ProfileStore.shared.shakeEnabled {
            lmbDown = true
            lmbDownLocation = event.location
            shakeActive = false
            shakeWindow = nil
            shake.reset()
        }
        // Left clicks/drags are never altered.
        return Unmanaged.passUnretained(event)
    }

    private func onLeftDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard ProfileStore.shared.shakeEnabled, lmbDown else { return pass }
        let loc = event.location

        if shakeActive {
            SnapSession.shared.update(globalPoint: loc)
            return pass
        }

        let now = ProcessInfo.processInfo.systemUptime
        if shake.feed(x: loc.x, time: now) {
            if shakeWindow == nil {
                shakeWindow = AX.windowUnderCursor(at: lmbDownLocation)
            }
            if shakeWindow != nil {
                shakeActive = true
                SnapSession.shared.begin()
                SnapSession.shared.update(globalPoint: loc)
            }
        }
        return pass
    }

    private func onLeftUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        defer {
            lmbDown = false
            shake.reset()
        }
        guard ProfileStore.shared.shakeEnabled else {
            return Unmanaged.passUnretained(event)
        }
        if shakeActive {
            let target = SnapSession.shared.end()
            if let target = target, let win = shakeWindow {
                // Let the app finish its own drag first, then snap.
                DispatchQueue.main.async { AX.setFrame(target, for: win) }
            }
            shakeActive = false
            shakeWindow = nil
        }
        return Unmanaged.passUnretained(event)
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
