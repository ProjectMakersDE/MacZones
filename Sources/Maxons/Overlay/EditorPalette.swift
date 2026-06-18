import Cocoa

/// Floating control panel shown while editing zones: profile management,
/// auto-grid generation and save / done.
final class EditorPalette: NSObject, NSWindowDelegate {
    let panel: NSPanel

    var onSelectProfile: ((String) -> Void)?
    var onNewProfile: (() -> Void)?
    var onDeleteProfile: (() -> Void)?
    var onRenameProfile: (() -> Void)?
    var onApplyGrid: ((Int, Int, Double) -> Void)?
    var onClearScreen: (() -> Void)?
    var onSave: (() -> Void)?
    var onDone: (() -> Void)?

    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let columnsStepper = NSStepper()
    private let rowsStepper = NSStepper()
    private let gapStepper = NSStepper()
    private let columnsLabel = NSTextField(labelWithString: "3")
    private let rowsLabel = NSTextField(labelWithString: "2")
    private let gapLabel = NSTextField(labelWithString: "0 %")

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()

        panel.title = "Maxons – Zonen bearbeiten"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        buildUI()
    }

    private func buildUI() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        // Profile row
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)
        let newBtn = button("Neu", #selector(newProfile))
        let delBtn = button("Löschen", #selector(deleteProfile))
        let renBtn = button("Umbenennen", #selector(renameProfile))
        let profileRow = hstack([label("Profil:"), profilePopup, newBtn, delBtn, renBtn])

        // Grid row
        configureStepper(columnsStepper, min: 1, max: 12, value: 3, action: #selector(gridStepperChanged))
        configureStepper(rowsStepper, min: 1, max: 12, value: 2, action: #selector(gridStepperChanged))
        configureStepper(gapStepper, min: 0, max: 8, value: 0, action: #selector(gridStepperChanged))

        let gridRow = hstack([
            label("Spalten:"), columnsLabel, columnsStepper,
            label("Zeilen:"), rowsLabel, rowsStepper,
            label("Lücke:"), gapLabel, gapStepper
        ])

        let applyBtn = button("Raster auf Bildschirm unter dem Mauszeiger anwenden", #selector(applyGrid))
        applyBtn.keyEquivalent = "\r"
        let clearBtn = button("Bildschirm leeren", #selector(clearScreen))

        let hint = NSTextField(wrappingLabelWithString:
            "Zone hinzufügen: leere Fläche aufziehen · Verschieben: Zone ziehen · " +
            "Größe ändern: Ecke unten rechts · ✕: löschen")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        // Footer
        let saveBtn = button("Speichern", #selector(save))
        let doneBtn = button("Fertig", #selector(done))
        doneBtn.keyEquivalent = "\u{1b}" // esc
        let footer = hstack([NSView(), saveBtn, doneBtn])

        content.addArrangedSubview(profileRow)
        content.addArrangedSubview(gridRow)
        content.addArrangedSubview(applyBtn)
        content.addArrangedSubview(clearBtn)
        content.addArrangedSubview(hint)
        content.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container
        panel.setContentSize(content.fittingSize)
    }

    // MARK: UI helpers

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: 12)
        return l
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }
    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 6
        s.alignment = .centerY
        return s
    }
    private func configureStepper(_ s: NSStepper, min: Double, max: Double, value: Double, action: Selector) {
        s.minValue = min
        s.maxValue = max
        s.increment = 1
        s.integerValue = Int(value)
        s.valueWraps = false
        s.target = self
        s.action = action
    }

    // MARK: Actions

    @objc private func profileChanged() {
        if let title = profilePopup.selectedItem?.title { onSelectProfile?(title) }
    }
    @objc private func newProfile() { onNewProfile?() }
    @objc private func deleteProfile() { onDeleteProfile?() }
    @objc private func renameProfile() { onRenameProfile?() }
    @objc private func clearScreen() { onClearScreen?() }
    @objc private func save() { onSave?() }
    @objc private func done() { onDone?() }

    @objc private func gridStepperChanged() {
        columnsLabel.stringValue = "\(columnsStepper.integerValue)"
        rowsLabel.stringValue = "\(rowsStepper.integerValue)"
        gapLabel.stringValue = "\(gapStepper.integerValue) %"
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
        panel.orderFrontRegardless()
        panel.makeKey()
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
