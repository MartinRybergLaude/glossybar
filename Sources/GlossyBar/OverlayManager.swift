import AppKit

/// Owns one overlay window per screen and keeps them in sync with the screen
/// layout, the current space, and the settings.
final class OverlayManager {
    private var windows: [OverlayWindow] = []
    private var timer: Timer?

    /// Set before `start()`. Reports the menu bar's real light/dark polarity.
    var probe: MenuBarProbe?

    func start() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(refresh),
                       name: Settings.didChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // The menu bar can come and go without any notification (auto-hide,
        // full-screen reveal on hover), so poll as a backstop.
        let t = Timer(timeInterval: 0.35, target: self, selector: #selector(refresh),
                      userInfo: nil, repeats: true)
        t.tolerance = 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t

        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        teardown()
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    @objc private func refresh() {
        let settings = Settings.shared
        guard settings.enabled else {
            teardown()
            return
        }

        let screens = NSScreen.screens
        let windowBounds = MenuBarGeometry.onScreenWindowBounds()
        let polarity = settings.polarity(measured: probe?.polarity ?? .light)

        while windows.count < screens.count { windows.append(OverlayWindow()) }
        while windows.count > screens.count { windows.removeLast().orderOut(nil) }

        for (window, screen) in zip(windows, screens) {
            guard MenuBarGeometry.menuBarIsShowing(on: screen),
                  !MenuBarGeometry.menuBarCovered(on: screen, windowBounds: windowBounds) else {
                window.orderOut(nil)
                continue
            }

            let height = MenuBarGeometry.menuBarHeight(
                for: screen, adjustment: CGFloat(settings.heightAdjustment))

            let frame = MenuBarGeometry.overlayFrame(for: screen, height: height)
            if window.frame != frame { window.setFrame(frame, display: false) }
            window.gloss.paintableRects = MenuBarGeometry.paintableRects(for: screen, overlay: frame)
            window.gloss.polarity = polarity

            if !window.isVisible { window.orderFrontRegardless() }
        }
    }
}
