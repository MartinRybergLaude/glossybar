import AppKit

/// Owns one overlay window per screen — and one shadow window under it — and
/// keeps them in sync with the screen layout, the current space, and the
/// settings.
final class OverlayManager {
    private var windows: [OverlayWindow] = []
    private var shadows: [ShadowWindow] = []
    private var timer: Timer?

    /// Pulls the gloss whenever the window server is compositing through a path
    /// that ignores the filter — a space slide, or Mission Control.
    private let compositing = CompositingMonitor()

    /// Set before `start()`. Reports the menu bar's real light/dark polarity.
    var probe: MenuBarProbe?

    func start() {
        compositing.onChange = { [weak self] suspended in
            guard let self else { return }
            self.windows.forEach { $0.gloss.isSuspended = suspended }
            // Exposé may have taken the windows off screen while the gloss was
            // out. Put them back the moment it is due again, rather than leaving
            // it to the next poll a third of a second later.
            if !suspended { self.refresh() }
        }
        compositing.start()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged),
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
        compositing.stop()
        teardown()
    }

    @objc private func screensChanged() {
        compositing.screensChanged()
        refresh()
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        shadows.forEach { $0.orderOut(nil) }
        shadows.removeAll()
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
        while shadows.count < screens.count { shadows.append(ShadowWindow()) }
        while shadows.count > screens.count { shadows.removeLast().orderOut(nil) }

        let strength = CGFloat(settings.resolvedShadowStrength)

        for (index, screen) in screens.enumerated() {
            let window = windows[index]
            let shadow = shadows[index]

            guard MenuBarGeometry.menuBarIsShowing(on: screen),
                  !MenuBarGeometry.menuBarCovered(on: screen, windowBounds: windowBounds) else {
                window.orderOut(nil)
                shadow.orderOut(nil)
                continue
            }

            let height = MenuBarGeometry.menuBarHeight(
                for: screen, adjustment: CGFloat(settings.heightAdjustment))

            let frame = MenuBarGeometry.overlayFrame(for: screen, height: height)
            if window.frame != frame { window.setFrame(frame, display: false) }
            window.gloss.paintableRects = MenuBarGeometry.paintableRects(for: screen, overlay: frame)
            window.gloss.polarity = polarity
            window.gloss.isSuspended = compositing.shouldSuspend

            // Don't fight `.transient`. While suspended the window server may
            // have taken the window away for Exposé, and hauling it back on
            // every refresh only churns the ordering — nothing is being drawn
            // either way.
            if !compositing.shouldSuspend, !window.isVisible {
                window.orderFrontRegardless()
                window.gloss.kick()
            }

            // The shadow has no compositing filter, so it needs none of the
            // suspending the gloss does — plain alpha survives a space slide
            // and Mission Control on its own.
            guard strength > 0 else {
                shadow.orderOut(nil)
                continue
            }
            let below = MenuBarGeometry.shadowFrame(below: frame, height: Shadow.height)
            if shadow.frame != below { shadow.setFrame(below, display: false) }
            shadow.strength = strength
            if !shadow.isVisible { shadow.orderFrontRegardless() }
        }
    }
}
