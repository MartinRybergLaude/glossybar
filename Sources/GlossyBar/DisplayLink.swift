import AppKit

/// A tick on the main thread, once per displayed frame.
///
/// Used for work that has to keep pace with the window server rather than with
/// a clock of its own: a `Timer` at 1/60 drifts against the refresh and lands a
/// frame late as often as not, and on a display that isn't 60Hz it samples at
/// the wrong rate entirely.
///
/// `CADisplayLink` is the modern answer but arrived in macOS 14, so below that
/// this falls back to `CVDisplayLink`, whose callback comes in on its own thread
/// and is hopped across. Callers see the same thing either way.
final class DisplayLink: NSObject {
    private let tick: () -> Void
    /// `CADisplayLink` on macOS 14+, held untyped so the property itself does
    /// not need the availability the type does.
    private var ca: AnyObject?
    private var cv: CVDisplayLink?

    init(tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
    }

    deinit { stop() }

    func start() {
        guard ca == nil, cv == nil else { return }

        if #available(macOS 14.0, *), let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(fire(_:)))
            link.add(to: .main, forMode: .common)
            ca = link
            return
        }

        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let link else { return }
        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            DispatchQueue.main.async { self.tick() }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
        cv = link
    }

    func stop() {
        if #available(macOS 14.0, *), let link = ca as? CADisplayLink { link.invalidate() }
        ca = nil
        if let cv { CVDisplayLinkStop(cv) }
        cv = nil
    }

    /// Displays coming and going can leave the link bound to one that is no
    /// longer there.
    func restart() {
        stop()
        start()
    }

    @objc private func fire(_ sender: Any) { tick() }
}
