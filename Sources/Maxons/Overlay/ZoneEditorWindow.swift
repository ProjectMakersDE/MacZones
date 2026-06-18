import Cocoa

/// Borderless, interactive editor window covering one screen's visible frame.
final class ZoneEditorWindow: NSWindow {
    let screenKey: String
    let editorView: ZoneEditorView

    init(context: ScreenContext, zones: [Zone], onChange: @escaping ([Zone]) -> Void) {
        self.screenKey = context.key
        editorView = ZoneEditorView(frame: CGRect(origin: .zero, size: context.boundsSize))
        editorView.zones = zones
        editorView.onChange = onChange

        super.init(contentRect: context.cocoaVisibleFrame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = editorView
        setFrame(context.cocoaVisibleFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func reload(zones: [Zone]) {
        editorView.zones = zones
    }
}
