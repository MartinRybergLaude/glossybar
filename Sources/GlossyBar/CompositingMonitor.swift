import AppKit

/// Reports when the window server is compositing through a path that ignores
/// `compositingFilter`, so the gloss can be pulled before it lands as a flat
/// grey strip. Two states do it, and both are read off the same per-frame
/// window list.
///
/// **A space slide.** The window server folds every menu-bar-level window —
/// ours included — into the *outgoing* space's scene and animates it off to the
/// side. The blend is then evaluated against that offscreen scene rather than
/// the desktop, the filter is dropped, and the raw gradient shows through.
/// Measured on macOS 27: the overlay is never pinned and never duplicated into
/// the incoming space under any combination of `canJoinAllSpaces` / `managed` /
/// `transient` / `stationary`, so there is nothing to fix in how the window is
/// configured. It has to stop drawing instead. The tell is that a real menu bar
/// leaves its screen's left edge, on the very first frame of the slide.
///
/// **Mission Control.** `.transient` gets the window server to take the overlay
/// off screen (see `OverlayWindow`), but it does so ~0.29s after Mission Control
/// begins — measured — and that is long enough to see. Mission Control puts up
/// full-width `WindowManager` windows below the menu bar level, at layers 14 and
/// 19 as measured, and those are up from its first frame. Neither appears at
/// rest nor during a space slide.
///
/// There is no event to hang any of this off. Measured against the first frame
/// of a slide, which runs ~0.47s:
///
/// | Signal | When it fires |
/// | --- | --- |
/// | `activeSpaceDidChange` | ~0.49s in — *after* the animation has ended |
/// | overlay's `didChangeOcclusionState` | frame 0 on some transitions, +0.3s on others |
/// | overlay's `didMove` / `didResize` / `didChangeScreen` | never |
///
/// So it polls, every frame, off a `DisplayLink`. Asking the window server
/// anything costs ~138µs whatever is asked — that is the IPC round trip, not the
/// query — which puts the floor for per-frame polling at around 1.5% CPU. The
/// reply is read at CoreFoundation level because bridging it to
/// `[[String: Any]]` deep-converts every window's dictionary and costs more than
/// the round trip that fetched it: 2.39% against 1.56% per 60Hz tick.
final class CompositingMonitor {
    /// Called when the answer changes. True means "stop drawing".
    var onChange: ((Bool) -> Void)?

    /// How long the coast has to stay clear before the gloss goes back on.
    ///
    /// Suspending is instant and coming back is deliberately not: the window
    /// server stays in its transition path for a moment after the geometry has
    /// settled, and the two are not worth the same. A bar that stays plain a few
    /// frames too long is invisible; a bar that comes back one frame early is
    /// the grey flash this whole file exists to remove.
    static let settleDelay: TimeInterval = 0.15

    private(set) var shouldSuspend = false
    private var link: DisplayLink?
    private var clearSince: Date?

    private static let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    private static let windowServer = "Window Server" as CFString
    private static let windowManager = "WindowManager" as CFString

    func start() {
        guard link == nil else { return }
        let link = DisplayLink { [weak self] in self?.check() }
        link.start()
        self.link = link
    }

    func stop() {
        link?.stop()
        link = nil
        clearSince = nil
        if shouldSuspend {
            shouldSuspend = false
            onChange?(false)
        }
    }

    func screensChanged() { link?.restart() }

    private func check() {
        guard !CompositingMonitor.filterIsIgnored() else {
            clearSince = nil
            guard !shouldSuspend else { return }
            shouldSuspend = true
            onChange?(true)
            return
        }
        guard shouldSuspend else { return }

        let now = Date()
        guard let since = clearSince else {
            clearSince = now
            return
        }
        guard now.timeIntervalSince(since) >= CompositingMonitor.settleDelay else { return }
        clearSince = nil
        shouldSuspend = false
        onChange?(false)
    }

    /// One window-list pass answering both questions.
    private static func filterIsIgnored() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID)
        else { return false }

        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return false }

        for i in 0..<CFArrayGetCount(list) {
            let info = dict(list, i)
            guard let layer = int(info, kCGWindowLayer),
                  let owner = value(info, kCGWindowOwnerName),
                  let bounds = rect(info, kCGWindowBounds)
            else { continue }
            let name = unsafeBitCast(owner, to: CFString.self)

            // A menu bar away from its screen's left edge — only so mid-slide.
            // Only x matters: the slide is horizontal, and a menu bar's x always
            // equals its screen's in CoreGraphics' global space.
            if layer == menuBarLevel,
               CFStringCompare(name, windowServer, []) == .compareEqualTo,
               !screens.contains(where: { abs($0.minX - bounds.minX) <= 1 }) {
                return true
            }

            // Mission Control's backdrop and its strip of spaces. Matched by
            // shape rather than by the exact layer numbers, which are Apple's to
            // change.
            if layer > 0, layer < menuBarLevel,
               CFStringCompare(name, windowManager, []) == .compareEqualTo,
               screens.contains(where: { bounds.width >= $0.width - 1 }) {
                return true
            }
        }
        return false
    }

    // MARK: - CoreFoundation-level reads

    @inline(__always)
    private static func dict(_ array: CFArray, _ i: Int) -> CFDictionary {
        unsafeBitCast(CFArrayGetValueAtIndex(array, i), to: CFDictionary.self)
    }

    @inline(__always)
    private static func value(_ d: CFDictionary, _ key: CFString) -> UnsafeRawPointer? {
        CFDictionaryGetValue(d, unsafeBitCast(key, to: UnsafeRawPointer.self))
    }

    @inline(__always)
    private static func int(_ d: CFDictionary, _ key: CFString) -> Int? {
        guard let v = value(d, key) else { return nil }
        var out = 0
        CFNumberGetValue(unsafeBitCast(v, to: CFNumber.self), .nsIntegerType, &out)
        return out
    }

    @inline(__always)
    private static func rect(_ d: CFDictionary, _ key: CFString) -> CGRect? {
        guard let v = value(d, key) else { return nil }
        return CGRect(dictionaryRepresentation: unsafeBitCast(v, to: CFDictionary.self))
    }
}
