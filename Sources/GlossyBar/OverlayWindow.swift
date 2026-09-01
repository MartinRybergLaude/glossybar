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
        // Just above the menu bar. Open menus and alerts sit at higher levels,
        // so they still draw over us.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        contentView = gloss
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
