import AppKit

/// Blends the gloss gradient into the real menu bar.
///
/// The mechanism is fussy and worth spelling out, because most of the obvious
/// routes silently fail. `CALayer.compositingFilter` blends a layer with the
/// content behind it — and for the layer that *is* a transparent window's
/// content view, "behind it" means the desktop, so the window server applies the
/// blend against whatever the menu bar already drew. What doesn't work:
///
///   - the gradient in a *sublayer*: it composites normally on top of the root's
///     blended result, painting an opaque strip over the menu bar. The gradient
///     has to be the root layer's own `contents`.
///   - the filter on the *frame view's* layer: ignored, window renders opaque.
///   - `backgroundFilters`: silent no-op, even with `CIColorInvert`.
///   - two filtered windows stacked to get two blend modes: the live display
///     path stops honouring the filters after a second or so and the raw
///     gradient shows through, even though screenshots still look right. Hence
///     one window, one filter, and `GlossVariant`'s single hard-light curve.
final class GlossView: NSView {
    /// Hard light: 0.5 is a no-op, below darkens, above lightens, and pure black
    /// and pure white both survive — so one curve covers the whole look.
    static let filterName = "hardLightBlendMode"

    /// Seconds between keep-alive nudges. The window server drops the
    /// compositing filter after about a second of idleness: the blend is correct
    /// at first, then the raw gradient shows through as a flat grey. A no-op
    /// content change puts the window back in the composited path, and doing it
    /// well inside that threshold stays ahead of it. Nudging per frame off a
    /// display link also works and costs ~3% CPU forever; this costs ~0.25%.
    static let keepAliveInterval: TimeInterval = 0.4

    private var builtFor: (height: CGFloat, scale: CGFloat, polarity: BarPolarity)?

    /// Two gradients differing by one step in a single invisible pixel.
    private var frames: (CGImage, CGImage)?
    private var showingSecondFrame = false
    private var keepAliveTimer: Timer?

    /// Regions (in view coordinates) that may be painted. Used to punch out the
    /// camera housing on notched displays, where blending over pure black would
    /// show up as a grey band.
    var paintableRects: [CGRect] = [] {
        didSet { if paintableRects != oldValue { needsLayout = true } }
    }

    var polarity: BarPolarity = .light {
        didSet { if polarity != oldValue { rebuild() } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        root.compositingFilter = GlossView.filterName
        // The gradient is one pixel wide and exactly as tall as the bar in
        // device pixels, so it maps 1:1 and the hairline stays a hairline.
        root.contentsGravity = .resize
        root.magnificationFilter = .nearest
        root.minificationFilter = .nearest
        layer = root
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func rebuild() {
        guard let root = layer, bounds.height > 0 else { return }
        let key = (bounds.height, backingScale, polarity)
        if let builtFor, builtFor == key { return }
        builtFor = key

        root.contentsScale = key.1
        frames = GradientImage.makePair(variant: Gloss.variant(for: polarity),
                                        height: key.0, scale: key.1)
        root.contents = frames?.0
    }

    override func layout() {
        super.layout()
        guard let root = layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Only mask when something actually needs punching out: a mask forces an
        // offscreen pass, which is wasted work on an ordinary display.
        if paintableRects.isEmpty {
            root.mask = nil
        } else {
            let mask = root.mask as? CAShapeLayer ?? CAShapeLayer()
            let path = CGMutablePath()
            for r in paintableRects { path.addRect(r) }
            mask.frame = bounds
            mask.path = path
            mask.fillColor = NSColor.black.cgColor
            root.mask = mask
        }

        CATransaction.commit()

        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        guard window != nil else { return }

        let timer = Timer(timeInterval: GlossView.keepAliveInterval, target: self,
                          selector: #selector(nudge), userInfo: nil, repeats: true)
        timer.tolerance = GlossView.keepAliveInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        keepAliveTimer = timer
    }

    @objc private func nudge() {
        guard let frames, let root = layer else { return }
        showingSecondFrame.toggle()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.contents = showingSecondFrame ? frames.1 : frames.0
        CATransaction.commit()
    }
}
