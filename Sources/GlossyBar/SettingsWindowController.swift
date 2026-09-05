import AppKit
import ServiceManagement
import Sparkle


/// The app's one window. GlossyBar has no status item, so this is where the
/// settings live. It opens on launch and again whenever the app is launched
/// while already running. While it is open the app has a Dock tile; closing it
/// turns the app back into a faceless accessory that only draws the gloss.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let updater: SPUUpdater
    private let probe: MenuBarProbe?

    /// Whoever was in front before we took over, so closing the window hands
    /// focus straight back instead of leaving an empty menu bar behind.
    private var previousApp: NSRunningApplication?

    private var glossCheck: NSButton!
    private var tonePopup: NSPopUpButton!
    private var shadowCheck: NSButton!
    private var loginCheck: NSButton!
    private var updateButton: NSButton!
    private var updaterObservation: NSKeyValueObservation?

    init(updater: SPUUpdater, probe: MenuBarProbe?) {
        self.updater = updater
        self.probe = probe

        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "GlossyBar"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        window.contentView = buildContent()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()

        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: Settings.didChange, object: nil)
        // Sparkle flips this off while a check is in flight.
        updaterObservation = updater.observe(\.canCheckForUpdates, options: [.initial]) { [weak self] updater, _ in
            self?.updateButton.isEnabled = updater.canCheckForUpdates
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Showing and hiding

    /// Brings the window up and gives the app a Dock tile for as long as it's open.
    func show() {
        if window?.isVisible != true {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        NSApp.setActivationPolicy(.regular)
        refresh()
        showWindow(nil)
        // Activating on the same turn as the policy change is unreliable: the
        // app's own menu bar goes missing, or the activation is dropped
        // entirely. A short beat later it takes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// The probe's status item only settles into the bar after a run-loop turn,
    /// so a reading taken while showing the window at launch can be stale.
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let previousApp, previousApp != .current, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    // MARK: - Content

    private func buildContent() -> NSView {
        glossCheck = NSButton(checkboxWithTitle: "Show the Aqua gloss",
                              target: self, action: #selector(toggleGloss))

        tonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for tone in Settings.Tone.allCases {
            tonePopup.addItem(withTitle: tone.name)
            tonePopup.lastItem?.representedObject = tone.rawValue
        }
        tonePopup.target = self
        tonePopup.action = #selector(selectTone)
        let toneRow = NSStackView(views: [label("Bar Tone:"), tonePopup])
        toneRow.orientation = .horizontal
        toneRow.spacing = 8

        shadowCheck = NSButton(checkboxWithTitle: "Cast a shadow below the bar",
                               target: self, action: #selector(toggleShadow))

        loginCheck = NSButton(checkboxWithTitle: "Open at Login",
                              target: self, action: #selector(toggleLoginItem))

        let note = label("GlossyBar has no menu bar icon. To change these settings later, open GlossyBar again.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 0
        note.preferredMaxLayoutWidth = 320

        updateButton = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdates))
        let quitButton = NSButton(title: "Quit GlossyBar", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let buttons = NSStackView(views: [updateButton, NSView(), quitButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        let stack = NSStackView(views: [
            glossCheck, toneRow, shadowCheck,
            separator(), loginCheck,
            separator(), note, buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(16, after: shadowCheck)
        stack.setCustomSpacing(16, after: loginCheck)
        stack.setCustomSpacing(16, after: note)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 360).isActive = true
        // Separators and the button row span the full width; everything else hugs the left.
        for view in stack.views where view === buttons || view is NSBox {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        return stack
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// Reads the settings back into the controls.
    @objc private func refresh() {
        let settings = Settings.shared
        glossCheck.state = settings.enabled ? .on : .off
        shadowCheck.state = settings.shadowEnabled ? .on : .off
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Automatic reads the bar itself and is nearly always right, but a wrong
        // guess is very visible, so it says what it decided.
        let autoIndex = tonePopup.indexOfItem(withRepresentedObject: Settings.Tone.auto.rawValue)
        if let auto = tonePopup.item(at: autoIndex) {
            let resolved = probe?.polarity ?? .light
            auto.title = "Automatic (\(resolved == .light ? "light" : "dark"))"
        }
        tonePopup.selectItem(at: tonePopup.indexOfItem(withRepresentedObject: settings.tone.rawValue))
    }

    // MARK: - Actions

    @objc private func toggleGloss() {
        Settings.shared.enabled = glossCheck.state == .on
    }

    @objc private func selectTone() {
        guard let raw = tonePopup.selectedItem?.representedObject as? String,
              let tone = Settings.Tone(rawValue: raw) else { return }
        Settings.shared.tone = tone
    }

    @objc private func toggleShadow() {
        Settings.shared.shadowEnabled = shadowCheck.state == .on
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if loginCheck.state == .on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change the login item"
            alert.runModal()
        }
        refresh()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }
}
