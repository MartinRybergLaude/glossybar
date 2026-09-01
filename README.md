# GlossyBar

A menu bar re-skinner for macOS, in the spirit of *Lickable Menu Bar*: it brings
back the Mac OS X 10.4 Tiger Aqua gradient that Apple flattened out after OS X
Mountain Lion. One look, measured off Lickable itself (see below).

## Build and run

```sh
./build.sh --run     # builds GlossyBar.app and launches it
```

The status item has almost nothing in it on purpose: on/off, bar tone, Open at
Login, Quit. Everything else is fixed — the Tiger curve at full strength, on
every display, with the keep-alive always running.

## How it works

The menu bar isn't themable, so GlossyBar doesn't try to replace it. It puts
borderless, click-through windows one level above the menu bar
(`kCGMainMenuWindowLevel + 1`) and blends gradients into whatever the system
already drew.

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
- **No drop shadow.** Lickable also puts a 20pt shadow under the bar in a second
  window at layer -2147483602, below app windows but above the wallpaper. Left
  out by choice.

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

## Notes

The build is signed ad-hoc, so Gatekeeper will want a right-click → Open the
first time if you move the app somewhere else.
