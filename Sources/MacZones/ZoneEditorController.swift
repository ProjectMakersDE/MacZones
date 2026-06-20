import Cocoa

/// Drives the zone editor: per-screen editor windows + the floating palette,
/// working on an in-memory copy that is committed to the ProfileStore on save.
final class ZoneEditorController {
    static let shared = ZoneEditorController()

    private(set) var isOpen = false

    private var windows: [ZoneEditorWindow] = []
    private var palette: EditorPalette?
    private var working: [String: [Zone]] = [:]   // screenKey -> zones

    func toggle() { isOpen ? close() : open() }

    // MARK: Open / close

    func open() {
        guard !isOpen else { return }
        guard Permissions.isTrusted else {
            Permissions.requestIfNeeded()
            return
        }
        isOpen = true
        ScreenManager.shared.refresh()
        ProfileStore.shared.seedDefaultsIfNeeded(ScreenManager.shared.defaultSeedSpecs())
        loadWorkingFromStore()

        // Become a regular app while editing so the palette and editor windows
        // are fully interactive (a menu-bar/accessory app can't reliably take
        // key focus). Reverted to accessory on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for ctx in ScreenManager.shared.contexts {
            let key = ctx.key
            let win = ZoneEditorWindow(context: ctx, zones: working[key] ?? []) { [weak self] zones in
                self?.working[key] = zones
            }
            win.orderFrontRegardless()
            windows.append(win)
        }

        // Palette is created last and sits above the editor windows, so it is
        // always clickable. We deliberately do NOT make an editor window key.
        let palette = EditorPalette()
        wirePalette(palette)
        palette.reloadProfiles(names: ProfileStore.shared.profiles.map { $0.name },
                               current: ProfileStore.shared.currentName)
        palette.show(near: screenUnderCursor() ?? NSScreen.main ?? NSScreen.screens[0])
        self.palette = palette
    }

    func close(save: Bool = true) {
        guard isOpen else { return }
        if save { commitWorking() }
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        palette?.close()
        palette = nil
        isOpen = false
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Working copy

    private func loadWorkingFromStore() {
        let profile = ProfileStore.shared.current
        working.removeAll()
        for ctx in ScreenManager.shared.contexts {
            working[ctx.key] = profile.screens[ctx.key] ?? []
        }
    }

    private func commitWorking() {
        ProfileStore.shared.mergeScreens(working)
    }

    private func reloadEditorViews() {
        for w in windows {
            w.reload(zones: working[w.screenKey] ?? [])
        }
    }

    // MARK: Palette wiring

    private func wirePalette(_ palette: EditorPalette) {
        palette.onSelectProfile = { [weak self] name in self?.switchProfile(to: name) }
        palette.onNewProfile = { [weak self] in self?.newProfile() }
        palette.onDeleteProfile = { [weak self] in self?.deleteProfile() }
        palette.onRenameProfile = { [weak self] in self?.renameProfile() }
        palette.onApplyGrid = { [weak self] c, r, gap in self?.applyGrid(columns: c, rows: r, gap: gap) }
        palette.onResetToSingle = { [weak self] in self?.resetScreenToSingle() }
        palette.onClearScreen = { [weak self] in self?.clearScreenUnderCursor() }
        palette.onSave = { [weak self] in self?.commitWorking() }
        palette.onDone = { [weak self] in self?.close(save: true) }
    }

    private func switchProfile(to name: String) {
        commitWorking()                       // keep current edits
        ProfileStore.shared.selectProfile(named: name)
        loadWorkingFromStore()
        reloadEditorViews()
    }

    private func newProfile() {
        guard let name = promptText(title: "Neues Profil", message: "Name des neuen Profils:") else { return }
        commitWorking()
        guard ProfileStore.shared.addProfile(named: name) else { return }
        loadWorkingFromStore()
        reloadEditorViews()
        palette?.reloadProfiles(names: ProfileStore.shared.profiles.map { $0.name },
                                current: ProfileStore.shared.currentName)
    }

    private func deleteProfile() {
        let current = ProfileStore.shared.currentName
        guard ProfileStore.shared.profiles.count > 1 else {
            NSSound.beep(); return
        }
        ProfileStore.shared.deleteProfile(named: current)
        loadWorkingFromStore()
        reloadEditorViews()
        palette?.reloadProfiles(names: ProfileStore.shared.profiles.map { $0.name },
                                current: ProfileStore.shared.currentName)
    }

    private func renameProfile() {
        let current = ProfileStore.shared.currentName
        guard let name = promptText(title: "Profil umbenennen", message: "Neuer Name:", default: current) else { return }
        ProfileStore.shared.renameProfile(from: current, to: name)
        palette?.reloadProfiles(names: ProfileStore.shared.profiles.map { $0.name },
                                current: ProfileStore.shared.currentName)
    }

    private func applyGrid(columns: Int, rows: Int, gap: Double) {
        guard let screen = screenUnderCursor() else { return }
        let key = ScreenManager.key(for: screen)
        working[key] = Grid.zones(columns: columns, rows: rows, gap: gap)
        reloadEditorViews()
    }

    private func resetScreenToSingle() {
        guard let screen = screenUnderCursor() else { return }
        let key = ScreenManager.key(for: screen)
        working[key] = [Zone(x: 0, y: 0, width: 1, height: 1)]
        reloadEditorViews()
    }

    private func clearScreenUnderCursor() {
        guard let screen = screenUnderCursor() else { return }
        let key = ScreenManager.key(for: screen)
        working[key] = []
        reloadEditorViews()
    }

    // MARK: Helpers

    private func screenUnderCursor() -> NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) ?? NSScreen.main
    }

    private func promptText(title: String, message: String, default def: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = def
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
