# Compressed image transfer — investigated 2026-09-02, DECLINED

**Status: not doing this, for now.** The Kitty graphics protocol can take a
picture as a PNG (`f=100`) or as a zlib-compressed payload (`o=z`), and TUIkit
sends neither: it decodes an image, resamples it to the placement's pixel size,
and transmits raw RGB/RGBA. This document records why that stays true, what was
measured on the way to deciding, and what would make it worth reopening.

Two things were asked, and they have different answers.

- **Implementing compression in TUIkit** — writing or vendoring a deflate
  encoder, or opening the system zlib opportunistically at runtime. Ruled out
  by the project owner before it was costed. The framework has a reasonable
  fallback (send it uncompressed) and this is not where its complexity budget
  should go.
- **Passing through PNG bytes TUIkit was already given** — no encoder, no
  dependency, just not throwing away a compressed file the app handed us.
  Investigated properly. It works, the premise it rests on is sound, and it is
  still not worth it yet. That is the substance of this document.

`Documentation/Terminal graphics protocols.md` §4.2 currently muses that `o=z`
is "the standard library's `compress` away". That was written before this
decision and is superseded by it.

---

## 1. The premise holds: the terminal really does rescale

The idea only works if the terminal, handed a picture at some arbitrary
resolution, will fit it to the `c=` × `r=` cell box TUIkit declares. It will.
This is the best-evidenced claim in the whole investigation, confirmed three
independent ways:

- kitty's released documentation for the placement keys;
- kitty's own implementation (`graphics.c`, `// Fit the image to the box while
  preserving aspect ratio`, with explicit `x_offset` / `y_offset` centring);
- Ghostty's separate implementation (`src/terminal/kitty/graphics_unicode.zig`,
  "preserving aspect ratio. We will center the image horizontally/vertically").

So TUIkit's placement, placeholder and id-encoding code would need no change at
all. Whatever else is wrong with the idea, this part is not.

### 1.1 …but it FITS and CENTRES, it does not FILL

The verb matters, and this codebase had it wrong.
`Sources/TUIkit/Views/Image+TerminalGraphics.swift` said "the terminal scales
the picture to **fill** them". It does not: it preserves the source aspect
ratio and centres the result, leaving bars on one axis when the box's aspect
differs from the picture's.

**Today that is harmless**, and that is exactly why it went unnoticed — TUIkit
resamples to the box before transmitting, so the picture handed over is already
box-shaped and the fit is exact. Passthrough is what would make it
load-bearing: an unresampled source whose aspect does not match the cell box
would letterbox. The comment is corrected in the same commit as this file.

---

## 2. The catch: the two payloads scale with different things

This is the argument that decides it, and it is not obvious until stated.

**Today's payload scales with the CELL BOX.** TUIkit resamples down first, so a
huge photograph in a small box costs what the small box costs. **Passthrough's
payload scales with the SOURCE FILE**, which has no relationship to the box at
all. So passthrough is not a straight improvement; it is a different curve that
crosses today's somewhere.

Measured, on the PNGs this repository actually contains, at Ghostty's measured
16×34 pixel cell, stride 4 (all three have alpha extrema, so none takes the
three-byte `f=24` path). Ratio is passthrough bytes ÷ today's bytes:

| file (measured size) | 12×4 cells | 40×14 | 80×24 | break-even |
|---|---|---|---|---|
| `.github/assets/github-banner.png` — 950×480, 252,411 B | 2.4× worse | **4.8× better** | **5.7× better** | 116 cells |
| `TUIkit.docc/Resources/tuikit-logo.png` — 1024×1024, 888,147 B | 8.5× worse | **1.4× better** | **3.4× better** | 408 cells |
| `.github/assets/spotnik_1.png` — 4276×2266, 4,052,719 B | 38.8× worse | 3.3× worse | **1.03× better** | 1,862 cells |

A 2 MiB PNG in a 12×4 box is **20.1× worse**. At the 8×16 fallback cell every
break-even moves out about 4.25× in area.

So it is a real win at panel and full-screen sizes, a bad loss at thumbnail
sizes, and the crossover depends entirely on the file. Any honest version needs
a gate, and the gate is where the difficulty lives:

```
pass through iff  pngByteCount < placementPixels * (isOpaque ? 3 : 4)
```

Two of those terms are not in hand at the natural decision site.
`pngByteCount` requires retaining the file's bytes through loading. `isOpaque`
does not exist as a value at all — it is decided *inside*
`_ImageCore.pixelBytes`, by scanning for `a != .max`, within the `pixels`
closure that `TerminalImageStore` evaluates only on a cache miss, i.e. *after*
the decision would have been made. Until that flag is cached on `RGBAImage` at
decode, the crossover is uncertain by 33% in precisely the marginal cases.

### 2.1 And the demo cannot show it

`f=100` is PNG-only. The only raster the Example renders is
`Sources/Example/Resources/demo-image.jpg` — a baseline JPEG. The other rasters
in the tree are DocC and `.github` assets. So the framework's own demo could
not exercise this feature without a new asset, and it would ship outside the
project's live-app smoke discipline.

---

## 3. Pros and cons

### For

- **No dependency, no encoder, no new format code.** The bytes are already
  compressed; the work is not throwing them away. This is the whole appeal.
- **Big wins where images are big.** 3–6× less on the wire for a banner or a
  logo at panel size, and the win grows with the box.
- **Skips a decode and a resample** for the graphics path — real CPU, though
  see the caveat in §5 about the number usually quoted for it.
- **The premise is solid** (§1) and needs nothing from the terminal that is not
  already relied on.
- **Fails safe by construction.** Every disqualifier degrades to the path that
  exists today, not to a broken picture.

### Against

- **It is a narrow win, not a broad one** (§2). It loses badly at small sizes,
  which is where a list of thumbnails lives.
- **The gate is not free.** It needs retained file bytes, a cached opacity
  flag, and a disqualification list that must not drift (§4).
- **A new capability probe is needed and is not cheap.** Answering the graphics
  handshake does not imply PNG decoding — Ghostty's PNG decoder is a nullable
  function pointer that is null in library builds, with a source comment saying
  so. The existing probe transmits `f=32` and proves nothing about `f=100`, and
  `TerminalGraphicsQuery.parse` returns on the first `OK` because the design
  deliberately arranges for one speaker; a second probe means rewriting it.
- **Colour management diverges between hosts.** Today's decode goes through
  `CGColorSpaceCreateDeviceRGB`. Passed through, kitty applies sRGB/gAMA/iCCP
  via lcms2 and Ghostty applies none. A tagged photo would look different the
  two ways — and would change appearance *mid-drag* when a resize crosses the
  crossover.
- **Unmeasured letterbox behaviour** (§5, blocker 1).
- **Terminal-side memory gets worse, not better.** kitty charges
  `4 × width × height` at *source* resolution for a PNG. Passing a 4276×2266
  photo through charges ~38.8 MB against the image store for a picture TUIkit
  would have sent as a few hundred KB. Eviction is silent under `q=2`.
- **Downscaling quality moves to the terminal**, and which filter each host
  uses is not something this project controls or has measured.
- **No live coverage** without a new Example asset (§2.1).
- **`.url` sources are a separate problem** — retaining bytes there means
  retaining them in `URLImageCache`, which is public, process-wide, and
  documented never to shrink.

---

## 4. The disqualification list, if it is ever built

Passthrough is only correct when nothing modifies the pixels. Recorded here so
the analysis is not repeated:

1. **Not a PNG**, by 8-byte signature sniff — never by file extension.
2. **IHDR dimensions disagree with the decoded image**, or exceed 10,000 on
   either axis (both terminals refuse).
3. **Any pixel-modifying converter setting.** The accurate predicate, read off
   `ASCIIConverter+Recolouring.swift`, is
   `colorMode == .trueColor && (toneCurve?.isIdentity ?? true) && edgeContrast <= 0 && dithering == .none`.
   Note both traps: a non-nil *identity* tone curve is a no-op, and a negative
   `edgeContrast` is too, so the obvious `toneCurve == nil && edgeContrast == 0`
   is wrong in both directions.
4. **`imageAspectRatio != nil`.** `.aspectRatio(_:contentMode:)` replaces the
   source ratio and `scaledBilinear` then stretches the picture into the box.
   That distortion is the modifier's entire point, and passthrough would
   silently make it inert. `.fill` is *not* a disqualifier — both `targetSize`
   branches preserve the corrected ratio, so it changes the box's size and not
   its aspect.
5. **Box aspect ≠ source aspect** beyond whatever tolerance blocker 1 licenses.
6. **Below the size crossover** (§2).

Free, from the existing structure: `context.isMeasuring`, `.terminalGraphics(false)`,
the 297-cell extent cap, and `.url` sources.

**Keeping it from drifting** is its own problem, and the answer is not a longer
list. Prove the predicate instead — a property test asserting
`converter.leavesPixelsUnchanged == (converter.recoloured(image, …) == image)`
over a matrix of settings is what catches a new stage added to `recoloured`.
And keep *every* signature field in both payload cases: a forgotten knob should
cost a redundant transmit, never a stale picture.

---

## 5. What would have to be measured first

Neither of these is answerable from a spec, and the gate cannot be written
without the first.

1. **What does a terminal paint in a placeholder cell the centred fit did not
   cover?** `placeholderRows` stamps U+10EEEE plus diacritics into *every* cell
   of the box, carrying the image id in the foreground. A bar cell maps outside
   the image. Whether the terminal blanks it or paints a missing-glyph box in
   an id-derived colour decides the aspect tolerance — and is the difference
   between a letterbox and visible garbage. Extend
   `Tools/TerminalProbes/placement_probe.py` with a deliberately
   aspect-mismatched PNG under `U=1`, and read it with `Tools/Smoke/raw_probe.py`
   (pyte cannot see an APC payload).
2. **Does a Display-P3 or gAMA-tagged photo visibly change colour** between
   passed-through and resampled, on Ghostty?

**A correction to an existing figure while we are here.** The "43 ms for a
full-screen image" in `Terminal graphics protocols.md` §8 comes from
`timed_transmit` in `placement_probe.py`, which sends `q=0` and blocks until the
terminal replies. It measures the write *plus* the terminal's full ingest *plus*
a round trip. The production path sends `q=2` and never waits, so that number is
not an app-side stall and must not be quoted as one. Nobody has measured the
app-side write cost separately.

---

## 6. The separable win, which is not about PNG at all

The one finding here worth acting on independently.

`TerminalImageSignature` carries `columns`, `rows`, `cellWidth` and
`cellHeight` alongside the content fields. So **a resize invalidates the
signature and runs delete + re-transmit + place**, on every step of a drag, for
bytes the terminal already holds — provably identical bytes whenever the
picture is clamped to the source resolution.

Splitting the signature into *content* (what the terminal must hold) and *box*
(where it goes), so that a box-only change emits `KittyGraphics.placement(…)`
alone and rebuilds the placeholder rows, is a change in one file. It needs no
PNG, no new probe, and no new terminal behaviour, and it pays on the path that
exists today. `TerminalImageStoreTests` already greps `takePending()` for the
transmit escape, so the assertion has somewhere obvious to go.

This is recorded rather than done, on the same "revisit when there is a
specific need" basis as the rest.

---

## 7. What would make this worth reopening

Any one of:

- **A concrete complaint** about image transmission cost that the §6 signature
  split does not fix.
- **An app that shows large PNGs at large sizes** — the regime where the
  measured win is 3–6× rather than a loss.
- **Both blockers in §5 answered**, at which point the clamped-regime subset
  (`shrink < 1.0`: pass through only when the box already asks for at least the
  source's pixels) becomes a small, self-contained change with no stride
  problem, no crossover churn, and no gate arithmetic.
- **A protocol or host change** that removes the terminal-side memory penalty
  of storing a PNG at source resolution.

Absent one of those, the framework sends raw pixels, and that is a defensible
place to be: it is correct on every host that does graphics at all, it is the
smallest thing that works, and it costs a resample nobody has yet shown to
matter.

---

## 8. Rejected outright, with reasons

- **`o=z` zlib compression** — needs a deflate encoder, which is the thing
  that was ruled out. Vendoring one, hand-rolling one, or `dlopen`-ing the
  system zlib are all more machinery than this feature is worth.
- **`t=f` / `t=t` / `t=s` (file path, temp file, shared memory)** — the spec
  says outright that a client has no a-priori way to know it shares a
  filesystem with its terminal, so each needs its own startup probe, disabled
  under tmux, and a positive probe on `/tmp` does not license the app's own
  path. Under `q=2` a per-file refusal is silent. They save only the 4/3 of
  base64. And `t=f` decouples what the terminal draws from what TUIkit
  measured, since the terminal re-reads the path at its own moment.
- **A `.png` case on `KittyGraphics.PixelFormat`** — that enum's documented
  contract is that the case *is* the byte stride, and `stride` would have to
  lie. A separate payload spelling is the honest shape if this is ever built.
- **Hysteresis at the crossover** ("once passed through, never go back") — it
  makes the rendered picture a function of resize *history*, so two identical
  views at identical sizes render differently depending on whether the window
  was ever dragged larger. Unreproducible by construction and invisible to the
  golden-snapshot harness. A symmetric byte deadband, still pure in the current
  inputs, is the shape to use if churn ever matters.
- **Skipping the decode entirely and reading only the IHDR** — a real
  optimisation and a separate one. `sizeThatFits` needs dimensions, the
  measuring render sites force the glyph converter, `.terminalGraphics` is a
  live toggle, and any placement over 297 cells falls back to glyphs. It must
  not be entangled with this.
