import AppKit

enum MenuBarGeometry {
    /// Whether the menu bar is currently showing on `screen`. It isn't when
    /// auto-hide is on, or when a full-screen space owns the display.
    static func menuBarIsShowing(on screen: NSScreen) -> Bool {
        if screen.safeAreaInsets.top > 0 { return true }
        let gap = screen.frame.maxY - screen.visibleFrame.maxY
        // A dock pinned to the top also eats into visibleFrame, but it is much
        // taller than a menu bar, so a plausible range keeps that case out.
        return gap >= 18 && gap <= 60
    }

    /// Height to draw on `screen`, resolved from that screen's own geometry —
    /// menu bars are not the same height everywhere, and a notched MacBook
    /// driving an external display has two different ones at once.
    ///
    /// This is the same 30pt (on an ordinary display) that Lickable Menu Bar
    /// uses. The status item's window reports 32pt and a menu drops 34pt down,
    /// but matching Lickable won out; `Settings.heightAdjustment` covers taste.
    static func menuBarHeight(for screen: NSScreen, adjustment: CGFloat) -> CGFloat {
        // A notched display states its height outright, and it's a good deal
        // taller than an ordinary one.
        if screen.safeAreaInsets.top > 0 {
            return max(1, screen.safeAreaInsets.top + adjustment)
        }
        return max(1, (screen.frame.maxY - screen.visibleFrame.maxY) + adjustment)
    }

    /// Screen-coordinate rect the overlay window should occupy.
    static func overlayFrame(for screen: NSScreen, height: CGFloat) -> CGRect {
        CGRect(x: screen.frame.minX,
               y: screen.frame.maxY - height,
               width: screen.frame.width,
               height: height)
    }

    /// Screen-coordinate rect for the shadow, hanging directly under the bar.
    /// Full width even on a notched display: the notch is at the top, so the
    /// bar's bottom edge runs straight across.
    static func shadowFrame(below overlay: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: overlay.minX, y: overlay.minY - height,
               width: overlay.width, height: height)
    }

    /// Sub-rects of the overlay that are safe to paint, in top-left-origin view
    /// coordinates. On a notched display this is the two areas flanking the
    /// camera housing; elsewhere it's the whole strip.
    static func paintableRects(for screen: NSScreen, overlay: CGRect) -> [CGRect] {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return [] }
        return [left, right].map { area in
            CGRect(x: area.minX - screen.frame.minX,
                   y: 0,
                   width: area.width,
                   height: overlay.height)
        }
    }

    /// True when a full-screen window covers the menu bar strip on this screen.
    /// Only window bounds and layer are read, so no screen-recording permission
    /// is required.
    /// Snapshot of on-screen normal-layer window bounds, in CoreGraphics'
    /// flipped global space. Taken once per refresh and shared across screens.
    static func onScreenWindowBounds() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let dict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return bounds
        }
    }

    static func menuBarCovered(on screen: NSScreen, windowBounds: [CGRect]) -> Bool {
        guard let main = NSScreen.screens.first else { return false }
        let flipTop = main.frame.maxY
        // Screen rect in CoreGraphics' flipped global space.
        let target = CGRect(x: screen.frame.minX,
                            y: flipTop - screen.frame.maxY,
                            width: screen.frame.width,
                            height: screen.frame.height)

        for bounds in windowBounds {
            if abs(bounds.minY - target.minY) <= 1,
               abs(bounds.height - target.height) <= 1,
               bounds.width >= target.width - 1 {
                return true
            }
        }
        return false
    }
}
