import AppKit

/// Whether the menu bar underneath is light with dark titles, or dark with
/// light titles. macOS picks this from the wallpaper, and it decides which
/// direction of shading is safe across the rows where the titles sit:
///
///   - light bar, black titles: darkening leaves black alone and can run the
///     full height; lightening would lift the glyphs, so the sheen has to stop
///     above them.
///   - dark bar, white titles: exactly inverted. Lightening leaves white alone
///     and can run the full height; darkening is confined to the rows below.
///
/// This is also why a dark wallpaper can't have a *light* Tiger bar: lifting the
/// bar to near-white would take the white titles with it.
enum BarPolarity {
    case light
    case dark
}

/// One polarity's worth of gradient, in "tone" space.
///
/// A tone is a grayscale value blended into the menu bar with hard light, which
/// makes 0.5 a no-op, darkens below it (multiplying by `2 * tone`) and lightens
/// above it (screening with `2 * tone - 1`). One curve therefore covers both
/// directions — and, crucially, needs only one blend mode, so the whole look
/// fits in a single window. See `GlossView` for why that matters.
///
/// Hard light also leaves both pure black and pure white untouched, which is
/// what keeps the menu titles crisp instead of washed out.
struct GlossVariant {
    typealias Stops = [(loc: CGFloat, tone: CGFloat)]

    /// The gradient, top → bottom.
    let tone: Stops

    /// 1pt specular line along the very top edge.
    let topHighlight: CGFloat

    /// The tone that leaves the menu bar untouched.
    static let neutral: CGFloat = 0.5
}

/// Mac OS X 10.4 Tiger's menu bar, composited over the real one.
///
/// The dark variant is not hand-tuned: it is Lickable Menu Bar's own output,
/// measured. Capturing the bar with and without it running and solving hard
/// light per device row gives a bright top hairline, a near-linear lightening
/// ramp down the upper half, a hard break at exactly 50%, and an ease-out back
/// toward neutral across the lower half. The stops below are those measurements.
/// Solving per channel gave the same tone for R, G and B to three decimals,
/// which is what justifies a greyscale gradient.
///
/// The light variant follows the same shape, but spends its upper-half
/// lightening before the glyph rows begin (~0.20). Lickable lightens straight
/// through them, which is free over white titles and costs nothing on a dark
/// bar; over black titles the same curve would lift them to a washed grey.
enum Gloss {
    static let light = GlossVariant(
        tone: [(0.0000, 0.6100), (0.1000, 0.5450), (0.2000, 0.5000),
               (0.4999, 0.5000), (0.5001, 0.4526), (0.5424, 0.4634),
               (0.6102, 0.4821), (0.6610, 0.4949), (0.7458, 0.5074),
               (0.8475, 0.5173), (0.9322, 0.5228), (1.0000, 0.5257)],
        topHighlight: 0.7000)

    static let dark = GlossVariant(
        tone: [(0.0000, 0.6015), (0.4915, 0.5258), (0.4999, 0.5258),
               (0.5001, 0.4526), (0.5424, 0.4634), (0.6102, 0.4821),
               (0.6610, 0.4949), (0.7458, 0.5074), (0.8475, 0.5173),
               (0.9322, 0.5228), (1.0000, 0.5257)],
        topHighlight: 0.7000)

    static func variant(for polarity: BarPolarity) -> GlossVariant {
        switch polarity {
        case .light: return light
        case .dark: return dark
        }
    }
}

/// The soft edge under the bar.
///
/// Lickable Menu Bar runs 20pt of shadow in a window of its own at
/// `desktopIconWindow + 1` — above the wallpaper and the desktop icons, below
/// every app window — so it falls on the desktop and is covered by anything in
/// front of it. Same placement here, and deliberately far lighter: Lickable's
/// reads as a band of darkness across the top of the desktop rather than an
/// edge. This one peaks at `peak` immediately under the bar and eases to
/// nothing over `height`, which is the shape a blurred edge actually has.
///
/// There is no menu item, the same as `heightAdjustment`, but there is an
/// escape hatch: `defaults write com.glossybar.GlossyBar shadowStrength -float 0`
/// turns it off, `2` doubles it, and it applies within a second.
enum Shadow {
    /// How far the shadow reaches below the bar, in points.
    static let height: CGFloat = 16

    /// Alpha immediately under the bar, before `shadowStrength` is applied.
    static let peak: CGFloat = 0.10

    /// Falloff top → bottom, as a fraction of `peak`.
    static let falloff: [(loc: CGFloat, level: CGFloat)] = [
        (0.00, 1.00), (0.15, 0.72), (0.35, 0.42),
        (0.60, 0.18), (0.80, 0.06), (1.00, 0.00),
    ]
}
