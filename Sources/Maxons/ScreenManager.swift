import Cocoa

/// One screen, captured in both coordinate systems we need:
///  - Cocoa (bottom-left origin) for placing AppKit overlay windows / drawing
///  - Quartz/AX (top-left origin) for snapping real windows & hit-testing the cursor
struct ScreenContext {
    let screen: NSScreen
    let key: String
    let cocoaVisibleFrame: CGRect   // bottom-left origin (AppKit)
    let cgVisibleRect: CGRect       // top-left origin (Quartz / AX)

    var boundsSize: CGSize { CGSize(width: cocoaVisibleFrame.width, height: cocoaVisibleFrame.height) }
}

final class ScreenManager {
    static let shared = ScreenManager()

    private(set) var contexts: [ScreenContext] = []

    init() { refresh() }

    func refresh() {
        // Height of the screen whose origin is (0,0) — the menu-bar screen.
        let zeroHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0

        contexts = NSScreen.screens.map { screen in
            let vf = screen.visibleFrame
            // Cocoa (bottom-left) -> Quartz (top-left) global flip.
            let cg = CGRect(x: vf.minX,
                            y: zeroHeight - vf.maxY,
                            width: vf.width,
                            height: vf.height)
            return ScreenContext(screen: screen,
                                 key: ScreenManager.key(for: screen),
                                 cocoaVisibleFrame: vf,
                                 cgVisibleRect: cg)
        }
    }

    func context(forKey key: String) -> ScreenContext? {
        contexts.first(where: { $0.key == key })
    }

    /// Stable per-display identifier (survives reboots / reconnection).
    static func key(for screen: NSScreen) -> String {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(num.uint32Value)
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID) {
                let uuid = uuidRef.takeRetainedValue()
                if let str = CFUUIDCreateString(nil, uuid) {
                    return str as String
                }
            }
        }
        let f = screen.frame
        return "screen-\(Int(f.width))x\(Int(f.height))@\(Int(f.minX)),\(Int(f.minY))"
    }

    // MARK: Zone <-> coordinates

    /// Zone -> Quartz/AX rect (for snapping a real window).
    func cgRect(for zone: Zone, in ctx: ScreenContext) -> CGRect {
        let r = ctx.cgVisibleRect
        return CGRect(x: r.minX + zone.x * r.width,
                      y: r.minY + zone.y * r.height,
                      width: zone.width * r.width,
                      height: zone.height * r.height)
    }

    /// Zone -> rect inside an overlay/editor view whose bounds == visible frame size.
    func viewRect(for zone: Zone, boundsSize b: CGSize) -> CGRect {
        CGRect(x: zone.x * b.width,
               y: (1 - zone.y - zone.height) * b.height,   // flip y for AppKit
               width: zone.width * b.width,
               height: zone.height * b.height)
    }

    /// View rect (AppKit, bottom-left) -> normalised Zone.
    func zone(fromViewRect r: CGRect, boundsSize b: CGSize, id: UUID = UUID()) -> Zone {
        guard b.width > 0, b.height > 0 else { return Zone(id: id, x: 0, y: 0, width: 0.2, height: 0.2) }
        var z = Zone(id: id,
                     x: Double(r.minX / b.width),
                     y: Double((b.height - r.maxY) / b.height),
                     width: Double(r.width / b.width),
                     height: Double(r.height / b.height))
        z.normalize()
        return z
    }

    /// Locate a global Quartz point: which screen, and normalised position within it.
    func locate(_ p: CGPoint) -> (ctx: ScreenContext, nx: Double, ny: Double)? {
        for ctx in contexts {
            let r = ctx.cgVisibleRect
            if r.contains(p) {
                return (ctx,
                        Double((p.x - r.minX) / r.width),
                        Double((p.y - r.minY) / r.height))
            }
        }
        return nil
    }
}
