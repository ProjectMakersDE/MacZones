import Cocoa
import ServiceManagement

/// The menu-bar item and its menu. The menu is rebuilt on demand so toggles,
/// the active profile and permission state are always current.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MacZones") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "❖"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: Build menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = ProfileStore.shared

        add(menu, "Zonen bearbeiten", #selector(toggleEditor), key: "")
            .setShortcutHint(HotKey.defaultDescription)

        menu.addItem(.separator())

        // Profiles
        let profileItem = NSMenuItem(title: "Profil: \(store.currentName)", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu()
        for p in store.profiles {
            let item = NSMenuItem(title: p.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.state = (p.name == store.currentName) ? .on : .off
            profileMenu.addItem(item)
        }
        profileItem.submenu = profileMenu
        menu.addItem(profileItem)

        // Quick grid presets
        let gridItem = NSMenuItem(title: "Schnelles Raster (Bildschirm unter Maus)", action: nil, keyEquivalent: "")
        let gridMenu = NSMenu()
        for (title, c, r) in [("2 × 1", 2, 1), ("3 × 1", 3, 1), ("4 × 1", 4, 1),
                              ("1 × 2", 1, 2), ("2 × 2", 2, 2), ("3 × 2", 3, 2), ("2 × 3", 2, 3)] {
            let item = NSMenuItem(title: title, action: #selector(applyQuickGrid(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [c, r]
            gridMenu.addItem(item)
        }
        gridItem.submenu = gridMenu
        menu.addItem(gridItem)

        menu.addItem(.separator())

        add(menu, "Rechtsklick-Ziehen", #selector(toggleRightClick)).state = store.rightClickDragEnabled ? .on : .off
        add(menu, "Beim Fenster-Wackeln einrasten", #selector(toggleShake)).state = store.shakeEnabled ? .on : .off

        menu.addItem(.separator())

        let loginItem = add(menu, "Bei Anmeldung starten", #selector(toggleLaunchAtLogin))
        loginItem.state = launchAtLoginEnabled ? .on : .off

        // Permission is always reachable from the menu, showing its current state.
        let trusted = Permissions.isTrusted
        let permTitle = trusted
            ? "Bedienungshilfen-Berechtigung: aktiv ✓"
            : "⚠︎ Bedienungshilfen-Berechtigung erteilen …"
        let permItem = add(menu, permTitle, #selector(openAccessibility))
        if !trusted {
            permItem.attributedTitle = NSAttributedString(
                string: permTitle,
                attributes: [.foregroundColor: NSColor.systemRed])
        }

        menu.addItem(.separator())
        add(menu, "Über MacZones", #selector(about))
        add(menu, "MacZones beenden", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: Actions

    @objc private func toggleEditor() { ZoneEditorController.shared.toggle() }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        ProfileStore.shared.selectProfile(named: sender.title)
    }

    @objc private func applyQuickGrid(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Int], pair.count == 2 else { return }
        guard Permissions.isTrusted else { Permissions.requestIfNeeded(); return }
        ScreenManager.shared.refresh()
        guard let screen = screenUnderCursor() else { return }
        let key = ScreenManager.key(for: screen)
        ProfileStore.shared.setZones(Grid.zones(columns: pair[0], rows: pair[1]), forScreen: key)
    }

    @objc private func toggleRightClick() {
        ProfileStore.shared.rightClickDragEnabled.toggle()
    }
    @objc private func toggleShake() {
        ProfileStore.shared.shakeEnabled.toggle()
    }
    @objc private func openAccessibility() {
        Permissions.requestIfNeeded()
        Permissions.openAccessibilitySettings()
    }
    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "MacZones"
        alert.informativeText = """
        Leichtgewichtiges Fenster-Zonen-Snapping für macOS.

        • Rechte Maustaste über einem Fenster gedrückt halten und ziehen, \
        dann über einer Zone loslassen.
        • Oder ein Fenster ziehen und kurz wackeln – die Zonen erscheinen.
        • Mehrere benachbarte Zonen überstreichen, um sie zusammenzufassen.
        • Zonen bearbeiten: \(HotKey.defaultDescription)

        Im Leerlauf benötigt MacZones praktisch keine CPU.
        """
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Launch at login

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    /// Pop the menu open programmatically (used when the app is re-opened from
    /// the Applications folder while already running).
    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    // MARK: Helpers

    private func screenUnderCursor() -> NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) ?? NSScreen.main
    }
}

private extension NSMenuItem {
    /// Shows a greyed shortcut hint on the right of the item title.
    func setShortcutHint(_ hint: String) {
        let title = self.title
        let attr = NSMutableAttributedString(string: title + "   ")
        attr.append(NSAttributedString(string: hint, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.menuFont(ofSize: 0)
        ]))
        self.attributedTitle = attr
    }
}
