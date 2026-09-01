import AppKit
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let overlays = OverlayManager()
    private var statusItem: NSStatusItem!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate  // keep alive for the lifetime of the run loop
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        if let button = statusItem.button {
            overlays.probe = MenuBarProbe(view: button)
        }
        overlays.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlays.stop()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "menubar.rectangle",
                                accessibilityDescription: "GlossyBar")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = Settings.shared
        menu.removeAllItems()

        let toggle = NSMenuItem(title: settings.enabled ? "Turn Off" : "Turn On",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        // The only real choice left: which way the gloss shades. Automatic reads
        // it off the menu bar and is nearly always right, but a wrong guess is
        // very visible, so the override stays.
        menu.addItem(.separator())
        menu.addItem(sectionHeader("Bar Tone"))
        for tone in Settings.Tone.allCases {
            let item = NSMenuItem(title: tone.name, action: #selector(selectTone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tone.rawValue
            item.state = settings.tone == tone ? .on : .off
            if tone == .auto, let button = statusItem.button {
                let resolved = MenuBarProbe(view: button).polarity
                item.title = "Automatic (\(resolved == .light ? "light" : "dark"))"
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit GlossyBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
    }

    @objc private func selectTone(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tone = Settings.Tone(rawValue: raw) else { return }
        Settings.shared.tone = tone
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change the login item"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
