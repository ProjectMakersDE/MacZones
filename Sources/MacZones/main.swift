import Cocoa

// MacZones — a deliberately tiny macOS window-zone snapper.
//
// Design goal: ~0% CPU at idle. There are no timers and no polling anywhere.
// Everything is driven by a single passive CGEventTap that only fires while a
// mouse button is actually held down (down / up / dragged). Moving the mouse
// without a button held produces no events for us at all.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar agent: no Dock icon, no app menu.
app.setActivationPolicy(.accessory)
app.run()
