import AppKit

/// Reports whether the menu bar currently has dark titles on a light bar or
/// light titles on a dark bar.
///
/// There's no API for the menu bar's own text colour, and the wallpaper's
/// brightness is only a guess at it. But AppKit already solves this problem for
/// status item template images, which invert to match the bar — so a status
/// item's button carries the answer: its effective appearance comes back
/// *VibrantDark* over a dark bar even while the app itself is in Aqua.
///
/// The signal is global rather than per-display, so a multi-display setup with
/// very different wallpapers may want the manual override.
final class MenuBarProbe {
    private weak var view: NSView?

    init(view: NSView) {
        self.view = view
    }

    var polarity: BarPolarity {
        guard let view else { return .light }
        let match = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }
}
