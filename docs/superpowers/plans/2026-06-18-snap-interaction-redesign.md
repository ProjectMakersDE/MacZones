# Snap Interaction Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make window snapping target the window actually being dragged, and drive zone reveal / multi-select with the right mouse button (tap = toggle, hold = multi-select) and shake, during a normal left-drag.

**Architecture:** A single CGEventTap left-drag hosts both triggers. Left-drag events drive all highlight updates (macOS suppresses `rightMouseDragged` while the left button is held). The right button's down/up only set/commit a multi-select anchor. The pure tap-vs-hold decision is extracted into a testable free function. The on-screen `SnapSession` gains single / multi / frozen selection modes.

**Tech Stack:** Swift 5.9, AppKit/Cocoa, ApplicationServices (Accessibility), CoreGraphics event taps, SwiftPM, XCTest.

## Global Constraints

- Platform floor: macOS 13 (`.macOS(.v13)`), Swift tools 5.9 — do not raise.
- Idle cost must stay ~zero: no timers/polling added; all logic runs only inside event-tap callbacks that fire while a mouse button is held.
- All AX/CGEvent rects are Quartz/AX global coordinates (top-left origin, y↓).
- UI strings are German (match existing menu/About copy).
- The executable product is named `MacZones` and is built by `swift build`; the dist/signing scripts must stay unaffected (a test target is only built by `swift test`).

---

## File Structure

- `Sources/MacZones/SnapGesture.swift` — **new.** Pure `RightReleaseOutcome` enum + `classifyRightRelease(...)`. No Cocoa singletons; unit-tested.
- `Sources/MacZones/SnapSession.swift` — **modify.** Add single/multi/frozen selection modes; `update(globalPoint:multi:)`, `beginMulti(at:)`, `endMulti()`, `didExpand`.
- `Sources/MacZones/EventTapController.swift` — **modify (rewrite handlers).** Remove the standalone right-drag mode; add the unified left-drag-hosted trigger model + the wrong-window bugfix.
- `Sources/MacZones/StatusBarController.swift` — **modify.** Update the right-button menu label and the About text.
- `Package.swift` — **modify.** Add a `MacZonesTests` test target.
- `Tests/MacZonesTests/SnapGestureTests.swift` — **new.** Tests for `classifyRightRelease`.

---

### Task 1: Pure right-button gesture classification (TDD)

**Files:**
- Create: `Sources/MacZones/SnapGesture.swift`
- Modify: `Package.swift`
- Test: `Tests/MacZonesTests/SnapGestureTests.swift`

**Interfaces:**
- Produces:
  - `enum RightReleaseOutcome: Equatable { case dismiss, singleFollow, freezeMulti }`
  - `func classifyRightRelease(holdDuration: TimeInterval, didExpand: Bool, zonesWereOnBeforePress: Bool, tapMax: TimeInterval = 0.25) -> RightReleaseOutcome`

- [ ] **Step 1: Add the test target to `Package.swift`**

Replace the whole file with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacZones",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacZones",
            path: "Sources/MacZones"
        ),
        .testTarget(
            name: "MacZonesTests",
            dependencies: ["MacZones"],
            path: "Tests/MacZonesTests"
        )
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/MacZonesTests/SnapGestureTests.swift`:

```swift
import XCTest
@testable import MacZones

final class SnapGestureTests: XCTestCase {
    func testTapWhileZonesOnDismisses() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 0.1, didExpand: false, zonesWereOnBeforePress: true),
            .dismiss)
    }

    func testTapWhileZonesOffKeepsSingle() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 0.1, didExpand: false, zonesWereOnBeforePress: false),
            .singleFollow)
    }

    func testHoldWithSweepFreezesMulti() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 1.0, didExpand: true, zonesWereOnBeforePress: true),
            .freezeMulti)
    }

    func testHoldWithSweepFromOffFreezesMulti() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 1.0, didExpand: true, zonesWereOnBeforePress: false),
            .freezeMulti)
    }

    func testLongHoldNoSweepKeepsSingle() {
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 1.0, didExpand: false, zonesWereOnBeforePress: true),
            .singleFollow)
    }

    func testFastReleaseWithSweepFreezesMulti() {
        // A quick but real multi-sweep must not be misread as a dismiss tap.
        XCTAssertEqual(
            classifyRightRelease(holdDuration: 0.1, didExpand: true, zonesWereOnBeforePress: true),
            .freezeMulti)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter SnapGestureTests`
Expected: FAIL — compile error "cannot find 'classifyRightRelease' in scope".

> Troubleshooting: if the failure is instead `no such module 'MacZones'` or `module 'MacZones' was not compiled for testing`, the executable target can't be `@testable`-imported on this toolchain. Fallback: create a library target `MacZonesCore` (`path: "Sources/MacZonesCore"`), move `SnapGesture.swift` there, add `MacZonesCore` to the executable target's `dependencies`, `import MacZonesCore` where `classifyRightRelease` is used, and depend the test target on `MacZonesCore`. Re-run.

- [ ] **Step 4: Implement `SnapGesture.swift`**

Create `Sources/MacZones/SnapGesture.swift`:

```swift
import Foundation

/// What a right-button release means while a left-drag snap session is (or was)
/// showing zones. Pure decision logic so it can be unit-tested without a display.
enum RightReleaseOutcome: Equatable {
    case dismiss        // turn zones off, no snap
    case singleFollow   // keep zones on; single zone under the cursor follows
    case freezeMulti    // keep zones on; freeze the multi-zone union as the selection
}

/// Classify a right-button press→release that happened during a left-drag.
///
/// - Parameters:
///   - holdDuration: seconds the right button was held.
///   - didExpand: true if, while held, the cursor reached a zone other than the anchor.
///   - zonesWereOnBeforePress: true if zones were already visible when the right button went down.
///   - tapMax: maximum duration that still counts as a "tap" (default 0.25s).
func classifyRightRelease(holdDuration: TimeInterval,
                          didExpand: Bool,
                          zonesWereOnBeforePress: Bool,
                          tapMax: TimeInterval = 0.25) -> RightReleaseOutcome {
    let isTap = holdDuration < tapMax && !didExpand
    if isTap && zonesWereOnBeforePress { return .dismiss }
    if didExpand { return .freezeMulti }
    return .singleFollow
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SnapGestureTests`
Expected: PASS — 6 tests succeed.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/MacZones/SnapGesture.swift Tests/MacZonesTests/SnapGestureTests.swift
git commit -m "Add testable right-button tap/hold classification"
```

---

### Task 2: SnapSession single / multi / frozen selection modes

**Files:**
- Modify: `Sources/MacZones/SnapSession.swift`

**Interfaces:**
- Consumes: existing `ScreenManager`, `ProfileStore`, `ZoneOverlayWindow`, `Zone.contains(nx:ny:)`.
- Produces (used by Task 3):
  - `func begin()` (unchanged signature)
  - `func update(globalPoint p: CGPoint, multi: Bool)`  — replaces `update(globalPoint:)`
  - `func beginMulti(at p: CGPoint)`
  - `func endMulti()`
  - `private(set) var didExpand: Bool`
  - `@discardableResult func end() -> CGRect?` and `func cancel()` (unchanged signatures)

- [ ] **Step 1: Replace the file contents**

Replace the whole of `Sources/MacZones/SnapSession.swift` with:

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. (Two call sites in `EventTapController` still use the old `update(globalPoint:)` signature and will be fixed in Task 3 — if you build the executable target only, expect errors there; that's fine, proceed to Task 3 and build at its end. To verify Task 2 in isolation, `swift build --target MacZonesTests` is not meaningful; rely on Task 3's build.)

> Note: because Task 3 rewrites the only callers of the changed methods, Tasks 2 and 3 share one green build at the end of Task 3. Commit Task 2 now as a checkpoint regardless.

- [ ] **Step 3: Commit**

```bash
git add Sources/MacZones/SnapSession.swift
git commit -m "SnapSession: single/multi/frozen selection modes"
```

---

### Task 3: EventTapController — unified trigger model + wrong-window bugfix

**Files:**
- Modify: `Sources/MacZones/EventTapController.swift`

**Interfaces:**
- Consumes: `classifyRightRelease(...)`, `RightReleaseOutcome` (Task 1); `SnapSession.begin/beginMulti(at:)/update(globalPoint:multi:)/endMulti/end/cancel/didExpand` (Task 2); `AX.windowUnderCursor(at:)`, `AX.setFrame(_:for:)`; `ProfileStore.shared.rightClickDragEnabled/shakeEnabled`.
- Produces: unchanged public surface (`start()`, `stop()`, `handle(type:event:)`).

- [ ] **Step 1: Replace the file contents**

Replace the whole of `Sources/MacZones/EventTapController.swift` with:

```swift
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
            rightHeld = false
            swallowRightUp = false
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
```

- [ ] **Step 2: Build to verify the whole executable compiles**

Run: `swift build`
Expected: `Build complete!` with no errors or warnings.

- [ ] **Step 3: Run the unit tests (still green)**

Run: `swift test --filter SnapGestureTests`
Expected: PASS — 6 tests.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacZones/EventTapController.swift
git commit -m "EventTapController: unified right/shake zone trigger + snap-correct-window fix"
```

---

### Task 4: Update menu label and About copy

**Files:**
- Modify: `Sources/MacZones/StatusBarController.swift`

**Interfaces:**
- Consumes: existing `ProfileStore.shared.rightClickDragEnabled`, `toggleRightClick`, `HotKey.defaultDescription`.
- Produces: none (UI strings only).

- [ ] **Step 1: Rename the right-button menu item**

In `Sources/MacZones/StatusBarController.swift`, replace this line (around line 71):

```swift
        add(menu, "Rechtsklick-Ziehen", #selector(toggleRightClick)).state = store.rightClickDragEnabled ? .on : .off
```

with:

```swift
        add(menu, "Rechte Maustaste: Zonen ein/aus & Mehrfachauswahl", #selector(toggleRightClick)).state = store.rightClickDragEnabled ? .on : .off
```

- [ ] **Step 2: Update the About text**

In the same file, replace the `informativeText` block in `about()` (lines ~159-169):

```swift
        alert.informativeText = """
        Leichtgewichtiges Fenster-Zonen-Snapping für macOS.

        • Rechte Maustaste über einem Fenster gedrückt halten und ziehen, \
        dann über einer Zone loslassen.
        • Oder ein Fenster ziehen und kurz wackeln – die Zonen erscheinen.
        • Mehrere benachbarte Zonen überstreichen, um sie zusammenzufassen.
        • Zonen bearbeiten: \(HotKey.defaultDescription)

        Im Leerlauf benötigt MacZones praktisch keine CPU.
        """
```

with:

```swift
        alert.informativeText = """
        Leichtgewichtiges Fenster-Zonen-Snapping für macOS.

        • Fenster mit der linken Maustaste ziehen und kurz wackeln – die Zonen erscheinen.
        • Oder während des Ziehens die rechte Maustaste kurz tippen: Zonen ein/aus.
        • Rechte Maustaste gedrückt halten und über mehrere Zonen ziehen, um sie \
        zusammenzufassen; loslassen friert die Auswahl ein.
        • Linke Maustaste über einer Zone loslassen schnappt das Fenster ein.
        • Zonen bearbeiten: \(HotKey.defaultDescription)

        Im Leerlauf benötigt MacZones praktisch keine CPU.
        """
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/MacZones/StatusBarController.swift
git commit -m "Menu + About copy for the new right-button zone controls"
```

---

### Task 5: Manual verification on the real system

No automated test can exercise the Accessibility API and live window dragging. Verify by hand and record results.

**Files:** none (verification only).

- [ ] **Step 1: Build and launch the app**

Run: `swift build -c release`
Then launch the built binary (or build the app bundle if the project's dist script is preferred):
Run: `.build/release/MacZones`
Grant Accessibility permission if prompted (the menu shows the permission state).

- [ ] **Step 2: Verify the wrong-window bugfix**

- Open two overlapping windows.
- Left-drag the front window a LONG way across the screen, then shake it.
- Expected: zones appear; on release the **dragged** window snaps. The other window never moves.

- [ ] **Step 3: Verify right-button toggle + multi-select**

- Left-drag a window. Tap the right button once → zones appear. Tap again → zones disappear.
- Left-drag a window, tap right to show zones, hover → only the single zone under the window is highlighted.
- Hold the right button and drag across several adjacent zones → bounding box spans them. Release the right button → the union stays (frozen). Release the left button → the window snaps into the combined area.

- [ ] **Step 4: Verify shake toggle and context menus**

- During a left-drag: shake → zones appear; shake again → zones disappear.
- Right-click on the desktop / a window WITHOUT dragging → the normal context menu appears (right clicks outside a drag are untouched).

- [ ] **Step 5: Confirm the key assumption / fallback**

- The model relies on `rightMouseDown` / `rightMouseUp` being delivered to the tap while the left button is held. Step 3 confirms this directly: if tapping/holding the right button during a left-drag does nothing, the assumption is false.
- If false: extend `handle(...)` to also route `.otherMouseDown` / `.otherMouseUp`, check the event's `.mouseEventButtonNumber` field (== 1 for the right button), and call the same `onRightDown` / `onRightUp` logic. Add `(1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)` to the tap mask. Re-test Step 3, then commit.

- [ ] **Step 6: Record the outcome**

Note in the PR/commit description which manual steps passed. If Step 5's fallback was needed, say so.

---

## Self-Review

**1. Spec coverage:**
- Wrong-window bugfix → Task 3 `revealZones(at:)` captures at current `loc`; verified Task 5 Step 2. ✓
- Right tap = toggle zones on/off → Task 1 `classifyRightRelease` (`.dismiss` / `.singleFollow`) + Task 3 `onRightDown`/`onRightUp`. ✓
- Right hold = multi-select, frozen on release → Task 2 `beginMulti`/`endMulti`/`didExpand`/`frozen` + Task 3. ✓
- Single zone by default → Task 2 `update(..., multi: false)`. ✓
- Shake toggles (on and off) → Task 3 `onLeftDragged`. ✓
- Left-up snaps / no-op rules → Task 3 `onLeftUp`. ✓
- Old right-drag mode removed; right clicks outside a drag untouched → Task 3 (guard `lmbDown`, no `RMBState`/resynthesise) + Task 5 Step 4. ✓
- Menu/About copy → Task 4. ✓
- ProfileStore keys unchanged (kept for compat) → no code task needed (spec says keep). ✓
- macOS-rightMouseDown-while-left-held assumption → Task 5 Step 5 with fallback. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"add validation". All code steps contain complete code. ✓

**3. Type consistency:** `classifyRightRelease(holdDuration:didExpand:zonesWereOnBeforePress:tapMax:)` and `RightReleaseOutcome { dismiss, singleFollow, freezeMulti }` are defined in Task 1 and called identically in Task 3. `SnapSession.update(globalPoint:multi:)`, `beginMulti(at:)`, `endMulti()`, `didExpand` defined in Task 2 and called identically in Task 3. `revealZones(at:)` / `dismissZones()` defined and used within Task 3. ✓
