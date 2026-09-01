# GlossyBar

A menu bar re-skinner for macOS, in the spirit of *Lickable Menu Bar*: it brings
back the Mac OS X 10.4 Tiger Aqua gradient that Apple flattened out after OS X
Mountain Lion. One look, measured off Lickable itself (see below).

## Build and run

```sh
./build.sh --run     # builds GlossyBar.app and launches it
```

The status item has almost nothing in it on purpose: on/off, bar tone, shadow,
Open at Login, Quit. Everything else is fixed — the Tiger curve at full strength, on
every display, with the keep-alive always running.

## How it works

The menu bar isn't themable, so GlossyBar doesn't try to replace it. It puts
borderless, click-through windows one level above the menu bar
(`kCGMainMenuWindowLevel + 1`) and blends gradients into whatever the system
already drew. A second, much simpler window hangs below the bar down at desktop
level for the shadow — plain alpha, no filter, so none of what follows applies
to it.

Getting a window to alter the pixels behind it is the whole trick, and most of
the obvious routes don't work. Measured on macOS 27:

| Approach | Result |
| --- | --- |
| `compositingFilter` on a **sublayer** | Blends against its siblings inside the window only; paints an opaque strip over the menu bar |
| `compositingFilter` on the **frame view's** layer | Ignored; window renders opaque |
| `backgroundFilters` on the content layer | Silent no-op, even with `CIColorInvert` |
| **`compositingFilter` on the content view's own root layer** | **Works** — the window server blends it against the desktop |

So the gradient has to *be* the root layer's `contents`, with the filter on that
same layer.

Two filtered windows stacked to get two blend modes also fails, but slowly: the
blend is correct for a second, then the live display path stops honouring the
filters and the raw gradient shows through — while screenshots still look right,
because they go through the software compositor. Hence one window with one
`hardLight` filter, whose curve covers both directions, and `keepAlive` to nudge
the window every 0.4s so the window server never files it as idle. Per-frame
nudging off a display link works too and costs ~3% CPU; 0.4s costs ~0.25%.

Idleness is not the only thing that takes the filter away — see
[Transitions](#transitions).

### Transitions

The filter is dropped during **Mission Control** and during a **space slide**,
and the raw gradient shows through as a flat grey strip across the bar. Two
causes, and neither has an event to react to, so `CompositingMonitor` watches for
both off a per-frame `DisplayLink`.

**Mission Control** was partly self-inflicted. The overlay asked for
`NSWindow.CollectionBehavior.stationary`, documented as *"unaffected by Exposé;
it stays visible and stationary"* — so it stayed up through the whole of it.
`.transient` is the documented opposite, *"floats in Spaces and is hidden by
Exposé"*, and the window server does honour it, but not promptly: it takes about
0.7s to take the window away, which is long enough to watch the bar go grey and
come back. Sampling the window list through Mission Control cycles:

| Collection behaviour | Overlay window on screen |
| --- | --- |
| `.stationary` | 100% of the cycle |
| `.transient` | ~21% — the opening animation, then gone |

So `.transient` stays, as a backstop that costs nothing, and the monitor covers
the opening. Mission Control puts up full-width `WindowManager` windows below the
menu bar level — layers 14 and 19 as measured — from its very first frame, and
neither appears at rest nor during a space slide.

**Space slides** cannot be fixed with a collection behaviour at all. The window
server folds every menu-bar-level window into the *outgoing* space's scene and
animates it off to the side; there are two real menu bars mid-slide, one per
space, and the overlay rides the one it was already over. It is never pinned and
never duplicated into the incoming space, under any combination of
`canJoinAllSpaces` / `managed` / `transient` / `stationary`. The tell is that a
real menu bar leaves its screen's left edge, on the first frame of the slide.

Measured against that first frame, for the signals that might have saved a poll:

| Signal | When it fires |
| --- | --- |
| `activeSpaceDidChange` | ~0.49s in — *after* the ~0.47s animation has ended |
| overlay's `didChangeOcclusionState` | frame 0 on some transitions, +0.3s on others |
| overlay's `didMove` / `didResize` / `didChangeScreen` | never |

Hence the display link. It drives the *watch* only — the keep-alive nudge stays
on its own 0.4s timer, which is a separate job. One window-list pass per frame
answers both questions, and the gloss comes off the layer on the frame the
transition starts: measured at -0.014s for Mission Control and ±0.001s across
space slides, against 0.29s and ~0.47s of grey before. The link runs at a
measured 16.7ms, p99 16.7ms, nothing over 25ms, so one frame is the whole of the
detection lag — and one frame is also the floor, because the transition can only
be seen after the window server has already begun it.

Suspending is not simply a matter of not drawing, though, and three things
around it each put the grey back:

- **The keep-alive has to go on running.** Stop nudging for the duration and the
  window is idle inside a second, so a Mission Control of any length ends with
  the filter already dropped and the first frame back is grey — up to 0.4s of it,
  until the next nudge. The gradient is therefore swapped for an invisible pair
  rather than removed, and the nudge carries on through the suspension.
- **Coming back has to lag.** The window server stays in its transition path for
  a moment after the geometry settles, so the gloss waits
  `CompositingMonitor.settleDelay` (0.15s) of clear frames before returning.
  Suspending stays instant: the two directions are not worth the same, since a
  bar that stays plain a few frames too long is invisible and one that returns a
  frame early is the flash.
- **Ordering has to be left alone.** `refresh()` used to haul the window back
  with `orderFrontRegardless` every third of a second, which during Mission
  Control is a fight with the `.transient` that is trying to take it away. It now
  leaves the ordering be while suspended — and `kick()`s the layer whenever the
  window *is* ordered back, because a window that has been off screen has had no
  updates the window server counts and its filter will have lapsed too.

The cost is all in asking the window server anything at all: ~138µs for the IPC
round trip whatever is asked, so neither `CGWindowListCreateDescriptionFromArray`
(which returns nothing on macOS 27) nor anchoring with `optionIncludingWindow`
beats a filtered scan by much. What is left to control is how much of the reply
gets bridged into Swift, which is why the reads are at CoreFoundation level —
bridging to `[[String: Any]]` deep-converts every window's dictionary and costs
more than the round trip that fetched it. Per 60Hz tick:

| | CPU |
| --- | --- |
| bare tick, no query | 0.20% |
| + one query, read at CoreFoundation level | 1.11% |
| + the same reply bridged to `[[String: Any]]` | 2.39% |

Whole app, measured the same way throughout:

| | Idle | Continuous input |
| --- | --- | --- |
| Before, with the bug | 0.25% | 0.30% |
| Now | 1.61% | 1.70% |

That is the price of watching every frame, and it is deliberate: an earlier
version gated the query on recent input to idle at 0.50%, which is cheaper but
leans on the assumption that transitions only ever follow input. Lickable Menu
Bar reaches the same place by the same route — its binary carries a
`MissionControlMonitor` built on a polling monitor, a `MenuBarStyler`
`isMissionControlActive` flag, space-change and occlusion observers, and a
`CVDisplayLink` — which is some comfort that there is no cleverer trick being
missed. It uses `setCompositingFilter:` too, and only *reads* the wallpaper
(`desktopImageURLForScreen:`), so the effect is not baked into the desktop
picture.

### Why hard light

The real menu titles have to survive, which rules out a translucent overlay — it
would wash them out. Both blend modes are chosen for what they do to text, and
which one is safe depends on the bar:

- **light bar, black titles:** darkening leaves black untouched, so it can run the
  whole height. Lightening would lift the glyphs, so the sheen stops above the
  rows they sit in.
- **dark bar, white titles:** exactly inverted. Lightening leaves white untouched
  and runs the full height; darkening is confined to the rows below the glyphs.

Each style therefore ships two variants, and `MenuBarProbe` picks between them.
It doesn't guess from the wallpaper's brightness — it asks a status item, because
AppKit already computes this to decide whether template icons invert: the
button's effective appearance comes back *VibrantDark* over a dark bar even while
the app itself is in Aqua. Override it with **Bar Tone** if you want.

**The full Tiger look needs a light desktop.** macOS picks the menu bar's text
colour from the wallpaper, and nothing an overlay does can change it. Over a dark
wallpaper the titles are white, so the bar has to stay dark to keep them legible
and you get a graphite Aqua instead of a silver one. Lickable has the same
constraint.

### The curve is measured, not guessed

`GlossStyle.glossy`'s dark variant is Lickable Menu Bar's own output. Capture the
bar with and without it running, then solve hard light per device row —
`tone = out / (2 * base)` where it darkened, `1 - (1 - out) / (2 * (1 - base))`
where it lightened — and the profile falls out:

| Region | Tone |
| --- | --- |
| Top hairline | 0.700 (bright) |
| Upper half | 0.602 → 0.526, near-linear |
| Break, at exactly 50% | jumps to 0.453 |
| Lower half | 0.453 → 0.526, ease-out |

The effect is perfectly neutral: solving per channel gives the same tone for R, G
and B to three decimals, which is what justifies a greyscale gradient.

Two deliberate departures:

- **No bottom hairline.** Lickable finishes the bar with a light 0.575 line on
  its bottom edge. Dropped, so the gradient just runs out at the last row.
- **A much lighter drop shadow.** Lickable puts 20pt of shadow under the bar in
  a second window at layer -2147483602 — above the wallpaper and the desktop
  icons, below every app window, so it falls on the desktop and is covered by
  anything in front of it. Same window and same layer here, but 16pt peaking at
  0.10 alpha and easing to nothing, because Lickable's reads as a band of
  darkness across the top of the desktop rather than an edge. `Shadow` in
  `Style.swift` holds the profile. **Shadow** in the menu turns it on and off;
  how heavy it is stays out of the menu, but
  `defaults write com.glossybar.GlossyBar shadowStrength -float 0.5` halves it
  and `2` doubles it, applying within a second. Toggling the menu item gives back
  whatever the strength was tuned to.

The light variant follows the same shape, but spends its upper-half lightening
before the glyph rows (~0.20). Lickable lightens straight through them, which is
free over white titles; over black ones the same curve would lift them to a
washed grey.

`Sources/GlossyBar/Style.swift` holds the gradient stops — that file is the whole
design, and it's the only thing to edit to invent a new style.

### Measuring the bar

Menu bar height is not one number: a notched MacBook's bar is much taller than an
ordinary display's, and a MacBook driving an external monitor has both at once.
So every screen is resolved from its own geometry:

1. **Notched screens** state their height outright via `safeAreaInsets.top`.
2. **Everything else** uses its own `frame.maxY - visibleFrame.maxY`. This is
   what Lickable Menu Bar uses, so the two agree by construction.

Other sources read differently and were tried: the status item's own window
reports 2pt more than `visibleFrame`, and a menu drops 4pt below it (Tahoe leaves
a gap under the bar). Both were rejected in favour of matching Lickable.

Note that `visibleFrame`'s answer is not fixed for a given display: it read 30pt
early in development and 31pt later, stable across app restarts either way, with
no dock or resolution change in between. Nothing here holds a cached copy, so the
bar follows whatever the system currently says. There is no menu item for this, but there is an escape hatch:
`defaults write com.glossybar.GlossyBar heightAdjustment -float -1` (applies within
a second, no restart).

### Details it handles

- Gradients are built in device pixels, so the top hairline lands on a pixel
  instead of being interpolated into a smudge.
- Overlays per display, rebuilt on display reconfiguration.
- Hides itself when the menu bar isn't there: full-screen spaces, or
  "Automatically hide and show the menu bar". Full-screen detection reads only
  window bounds from `CGWindowListCopyWindowInfo`, so no Screen Recording
  permission is needed.
- Punches out the camera housing on notched displays, where blending over pure
  black would show as a grey band.
- Never takes focus, never takes clicks, and stays below open menus and alerts.
- Casts a soft edge onto the desktop below the bar, hidden by any window in
  front of it.
- Pulls the gloss on the frame a space slide or Mission Control starts, because
  the filter survives neither, and puts it back on the frame they end.

## Notes

The build is signed ad-hoc, so Gatekeeper will want a right-click → Open the
first time if you move the app somewhere else.
