import AppKit

/// A click-through, always-on-top strip sitting directly over the menu bar,
/// blended into it. See `GlossView` for how the blending is arranged.
final class OverlayWindow: NSWindow {
    let gloss = GlossView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        // A transparent window is what lets the blend see the menu bar behind.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        canHide = false
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true
        // This window is ordered out and back whenever the menu bar comes and
        // goes; AppKit's default show animation makes that a visible resize.
        animationBehavior = .none
        // Just above the menu bar. Open menus and alerts sit at higher levels,
        // so they still draw over us.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        // `.transient` rather than `.stationary`: stationary means "unaffected by
        // Exposé, stays visible", which is exactly wrong here. Mission Control
        // composites through a path that drops the filter, so a window that
        // stays up paints its raw gradient as a flat grey strip over the bar.
        //
        // Transient is the documented "hidden by Exposé" and the window server
        // does honour it, but it takes about 0.7s to act: measured over Mission
        // Control cycles, the overlay is on screen for ~21% of one under
        // `.transient` against 100% under `.stationary`. That opening is covered
        // by `CompositingMonitor`, which stops the drawing on frame one; this
        // stays as a backstop that costs nothing.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]
        contentView = gloss
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
