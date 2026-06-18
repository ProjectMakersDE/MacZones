import Cocoa

/// A transparent, click-through window that shows the zones for one screen
/// during a snap gesture.
final class ZoneOverlayWindow: NSWindow {
    private let overlayView: ZoneOverlayView

    init(context: ScreenContext, zones: [Zone]) {
        overlayView = ZoneOverlayView(frame: CGRect(origin: .zero, size: context.boundsSize))
        overlayView.zones = zones

        super.init(contentRect: context.cocoaVisibleFrame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true            // fully click-through
        level = .popUpMenu                   // above normal windows
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = overlayView
        setFrame(context.cocoaVisibleFrame, display: false)
    }

    func setHighlight(_ rect: CGRect?) {
        overlayView.highlightRect = rect
    }
}
