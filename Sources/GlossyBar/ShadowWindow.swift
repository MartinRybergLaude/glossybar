import AppKit

/// The soft edge under the menu bar, hanging just below it.
///
/// A different kind of thing from the gloss, and much the simpler of the two: an
/// ordinary translucent overlay with no compositing filter, so none of
/// `GlossView`'s machinery applies. Nothing to keep alive, and nothing a space
/// slide or Mission Control can break, because plain alpha compositing is
/// honoured everywhere the filter is not.
///
/// It sits at `desktopIconWindow + 1`, which is where Lickable Menu Bar puts
/// its own: above the wallpaper and the desktop icons, below every app window.
/// So the shadow falls on the desktop and is hidden by anything in front of it,
/// which is what stops it dimming the top of every window on screen.
final class ShadowWindow: NSWindow {
    private let shadow = ShadowView()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        canHide = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        // `.stationary` is documented as behaving "like the desktop window",
        // which is exactly the company this window is keeping.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        contentView = shadow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var strength: CGFloat {
        get { shadow.strength }
        set { shadow.strength = newValue }
    }
}

private final class ShadowView: NSView {
    private var builtFor: (height: CGFloat, scale: CGFloat, strength: CGFloat)?

    var strength: CGFloat = 1 {
        didSet { if strength != oldValue { needsLayout = true } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        // One pixel wide and as tall as the shadow in device pixels, so it maps
        // 1:1 down the falloff.
        root.contentsGravity = .resize
        layer = root
        // The gradient is set straight into the root layer's `contents`, so
        // AppKit must never redraw the layer for us. Under `.onSetNeedsDisplay`
        // any `needsDisplay` — display sleep, a display coming or going, a
        // backing-store purge — has AppKit clear `contents` to nil on the next
        // display pass, and with no `draw(_:)` here nothing repaints it: the
        // window stays ordered in, fully transparent, until the app restarts.
        // The gloss has the same shape but its keep-alive reassigns `contents`
        // every 0.4s, which is why only the shadow ever stayed gone.
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let root = layer, bounds.height > 0 else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = (bounds.height, scale, strength)
        // Rebuild if the image was ever taken away, whatever the cache says.
        if let builtFor, builtFor == key, root.contents != nil { return }
        builtFor = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.contentsScale = scale
        root.contents = GradientImage.makeShadow(height: key.0, scale: key.1, strength: key.2)
        CATransaction.commit()
    }
}
