import Cocoa

/// Floating control panel shown while editing zones: profile management,
/// auto-grid generation, split helpers and save / done.
final class EditorPalette: NSObject, NSWindowDelegate {
    let panel: NSPanel

    var onSelectProfile: ((String) -> Void)?
    var onNewProfile: (() -> Void)?
    var onDeleteProfile: (() -> Void)?
    var onRenameProfile: (() -> Void)?
    var onApplyGrid: ((Int, Int, Double) -> Void)?
    var onResetToSingle: (() -> Void)?
    var onClearScreen: (() -> Void)?
    var onSave: (() -> Void)?
    var onDone: (() -> Void)?

    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let columnsStepper = NSStepper()
    private let rowsStepper = NSStepper()
    private let gapStepper = NSStepper()
    private let columnsValue = NSTextField(labelWithString: "3")
    private let rowsValue = NSTextField(labelWithString: "2")
    private let gapValue = NSTextField(labelWithString: "0 %")

    private let maxDiv = Grid.maxDivisions   // 6

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()

        panel.title = "MacZones – Zonen bearbeiten"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // IMPORTANT: set the level LAST. `isFloatingPanel = true` resets the
        // level to .floating, which would put the palette *below* the editor
        // overlays (.popUpMenu). Assigning afterwards keeps it clearly on top.
        panel.level = EditorPalette.topLevel

        buildUI()
    }

    /// Above the editor overlay windows (which are at `.popUpMenu`).
    private static let topLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 10)

    private func buildUI() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        // ---- Profiles ----
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)
        let profileRow = hstack([
            label("Profil:"), profilePopup,
            button("Neu", #selector(newProfile)),
            button("Löschen", #selector(deleteProfile)),
            button("Umbenennen", #selector(renameProfile))
        ])

        content.addArrangedSubview(profileRow)
        content.addArrangedSubview(separator())

        // ---- Grid ----
        content.addArrangedSubview(sectionLabel("Automatisches Raster (max. \(maxDiv) × \(maxDiv))"))

        configureStepper(columnsStepper, value: 3)
        configureStepper(rowsStepper, value: 2)
        gapStepper.minValue = 0; gapStepper.maxValue = 8; gapStepper.increment = 1
        gapStepper.integerValue = 0; gapStepper.valueWraps = false
        gapStepper.target = self; gapStepper.action = #selector(gridStepperChanged)

        let gridRow = hstack([
            label("Spalten:"), columnsValue, columnsStepper,
            spacerSmall(),
            label("Zeilen:"), rowsValue, rowsStepper,
            spacerSmall(),
            label("Lücke:"), gapValue, gapStepper
        ])
        content.addArrangedSubview(gridRow)

        let presets: [(Int, Int)] = [(2, 2), (3, 2), (4, 2), (6, 2), (3, 3), (6, 6)]
        let presetRow = hstack(presets.map { presetButton($0.0, $0.1) })
        content.addArrangedSubview(label("Schnellauswahl:"))
        content.addArrangedSubview(presetRow)

        let applyBtn = button("Raster auf Bildschirm unter dem Mauszeiger anwenden", #selector(applyGrid))
        applyBtn.bezelStyle = .rounded
        content.addArrangedSubview(applyBtn)

        content.addArrangedSubview(separator())

        // ---- Manual / split ----
        content.addArrangedSubview(sectionLabel("Manuell"))
        let toolsRow = hstack([
            button("Auf eine Zone zurücksetzen", #selector(resetToSingle)),
            button("Bildschirm leeren", #selector(clearScreen))
        ])
        content.addArrangedSubview(toolsRow)

        let hint = NSTextField(wrappingLabelWithString:
            "In eine Zone klicken, um sie an dieser Stelle zu teilen (⌥ = horizontal). " +
            "Zone verschieben: ziehen · Größe: Ecke unten rechts · ✕: löschen · " +
            "Leere Fläche aufziehen: neue Zone.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 420
        content.addArrangedSubview(hint)

        content.addArrangedSubview(separator())

        // ---- Footer ----
        let saveBtn = button("Speichern", #selector(save))
        let doneBtn = button("Fertig", #selector(done))
        doneBtn.keyEquivalent = "\u{1b}" // esc
        doneBtn.bezelStyle = .rounded
        let footer = hstack([flexibleSpacer(), saveBtn, doneBtn])
        footer.distribution = .fill
        content.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor,
                                          constant: -(content.edgeInsets.left + content.edgeInsets.right))
        ])
        panel.contentView = container
        panel.setContentSize(content.fittingSize)
        gridStepperChanged()
    }

    // MARK: UI helpers

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: 12)
        return l
    }
    private func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.boldSystemFont(ofSize: 12)
        return l
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.setButtonType(.momentaryPushIn)
        return b
    }
    private func presetButton(_ c: Int, _ r: Int) -> NSButton {
        let b = button("\(c)×\(r)", #selector(presetClicked(_:)))
        b.tag = c * 10 + r
        return b
    }
    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 6
        s.alignment = .centerY
        return s
    }
    private func spacerSmall() -> NSView {
        let v = NSView()
        v.widthAnchor.constraint(equalToConstant: 10).isActive = true
        return v
    }
    private func flexibleSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
    private func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        return b
    }
    private func configureStepper(_ s: NSStepper, value: Int) {
        s.minValue = 1
        s.maxValue = Double(maxDiv)
        s.increment = 1
        s.integerValue = value
        s.valueWraps = false
        s.target = self
        s.action = #selector(gridStepperChanged)
    }

    // MARK: Actions

    @objc private func profileChanged() {
        if let title = profilePopup.selectedItem?.title { onSelectProfile?(title) }
    }
    @objc private func newProfile() { onNewProfile?() }
    @objc private func deleteProfile() { onDeleteProfile?() }
    @objc private func renameProfile() { onRenameProfile?() }
    @objc private func resetToSingle() { onResetToSingle?() }
    @objc private func clearScreen() { onClearScreen?() }
    @objc private func save() { onSave?() }
    @objc private func done() { onDone?() }

    @objc private func gridStepperChanged() {
        columnsValue.stringValue = "\(columnsStepper.integerValue)"
        rowsValue.stringValue = "\(rowsStepper.integerValue)"
        gapValue.stringValue = "\(gapStepper.integerValue) %"
    }

    @objc private func presetClicked(_ sender: NSButton) {
        columnsStepper.integerValue = sender.tag / 10
        rowsStepper.integerValue = sender.tag % 10
        gridStepperChanged()
        applyGrid()
    }

    @objc private func applyGrid() {
        onApplyGrid?(columnsStepper.integerValue,
                     rowsStepper.integerValue,
                     Double(gapStepper.integerValue) / 100.0)
    }

    // MARK: Public

    func reloadProfiles(names: [String], current: String) {
        profilePopup.removeAllItems()
        profilePopup.addItems(withTitles: names)
        profilePopup.selectItem(withTitle: current)
    }

    func show(near screen: NSScreen) {
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: f.midX - size.width / 2,
                                     y: f.maxY - size.height - 40))
        panel.level = EditorPalette.topLevel
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    // NSWindowDelegate — the panel's close box behaves like "Fertig".
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onDone?()
        return false
    }
}
