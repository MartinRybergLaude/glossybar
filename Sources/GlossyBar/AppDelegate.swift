import AppKit
import Sparkle

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlays = OverlayManager()
    private var settingsWindow: SettingsWindowController!

    /// Not shown to anyone: zero points wide, no image. It exists so
    /// `MenuBarProbe` has a view inside the menu bar to read the bar's
    /// appearance from — see the probe for why nothing else works.
    private var probeItem: NSStatusItem!

    // `startingUpdater: true` kicks off Sparkle's scheduled check loop.
    private let updater = SPUStandardUpdaterController(startingUpdater: true,
                                                       updaterDelegate: nil,
                                                       userDriverDelegate: nil)

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate  // keep alive for the lifetime of the run loop
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        probeItem = NSStatusBar.system.statusItem(withLength: 0)
        let probe = probeItem.button.map(MenuBarProbe.init)
        overlays.probe = probe
        overlays.start()

        NSApp.mainMenu = buildMainMenu()
        settingsWindow = SettingsWindowController(updater: updater.updater, probe: probe)

        // Opening the app by hand means "show me the settings". Coming up with
        // the session as a login item, it just quietly starts drawing.
        if !launchedAsLoginItem {
            settingsWindow.show()
        }
    }

    /// Launching the app while it's already running — from the Finder, Spotlight,
    /// or the Dock — lands here. That's the only way back to the settings once
    /// the window has been closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlays.stop()
    }

    /// Whether launchd started us as a login item rather than the user.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let prop = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return prop.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    // MARK: - Main menu

    /// Only visible while the settings window is open and the app is regular,
    /// but without it Cmd-W and Cmd-Q do nothing.
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About GlossyBar",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let update = appMenu.addItem(withTitle: "Check for Updates…",
                                     action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit GlossyBar",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}
