import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var hotKey: HotKey?
    private var permissionRetry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ProfileStore.shared
        ScreenManager.shared.refresh()

        statusBar = StatusBarController()

        // Toggle the zone editor with ⌃⌥Z.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_Z),
                        modifiers: UInt32(controlKey | optionKey)) {
            ZoneEditorController.shared.toggle()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if Permissions.isTrusted {
            EventTapController.shared.start()
        } else {
            showFirstRunPermissionPrompt()
            Permissions.requestIfNeeded()
            startPermissionRetry()
        }
    }

    @objc private func screensChanged() {
        ScreenManager.shared.refresh()
    }

    /// MacZones is a menu-bar app (no Dock icon). When it's launched again from
    /// the Applications folder while already running, show the menu so it's
    /// obvious where the controls live.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.showMenu()
        return true
    }

    /// Until Accessibility is granted we can't install the event tap. Poll only
    /// during this initial window; once granted we start the tap and stop the
    /// timer, after which the app is fully event-driven (~0% CPU at idle).
    private func startPermissionRetry() {
        permissionRetry?.invalidate()
        permissionRetry = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard Permissions.isTrusted else { return }
            if EventTapController.shared.start() {
                timer.invalidate()
                self?.permissionRetry = nil
            }
        }
    }

    private func showFirstRunPermissionPrompt() {
        let alert = NSAlert()
        alert.messageText = "MacZones benötigt die Bedienungshilfen"
        alert.informativeText = """
        Damit MacZones Fenster verschieben und Mausgesten erkennen kann, aktiviere \
        es bitte in:

        Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen

        Danach funktioniert MacZones sofort – kein Neustart nötig.
        """
        alert.addButton(withTitle: "Einstellungen öffnen")
        alert.addButton(withTitle: "Später")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openAccessibilitySettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventTapController.shared.stop()
        permissionRetry?.invalidate()
    }
}
