# Mapping an image onto a chosen palette

**Status: shipped as `ASCIIColorMode.palette(_:)`.** This note was the design;
what follows is it, updated where building it taught me something. Three things
did, and one of them reversed a recommendation.

## What existed, and the gap

`ASCIIColorMode` had four cases, and they form a ladder of **fidelity**, chosen
by what the terminal can display:

| | colours | chosen when |
|---|---|---|
| `.trueColor` | 16.7M | the terminal reports truecolor |
| `.ansi256` | 256 | it reports 256 |
| `.grayscale` | 24 greys | a deliberate stylistic choice |
| `.mono` | 2 | 16-colour terminals, `NO_COLOR`, `.noColor` |

`.effective(for:)` walks down that ladder automatically. What was missing is
orthogonal to it: a mode that says *use these colours*, chosen by intent rather
than by capability — an image drawn in the theme's palette, or in two or three
named colours, so it belongs to the app rather than sitting in it as a
photograph.

Between `.grayscale`'s 24 fixed greys and `.ansi256`'s everything, there was
nothing.

## The shape of the API

A fifth case carrying its own colours, `case palette(ASCIIPalette)`, and three
ways to build one:

```swift
.imageColorMode(.palette(ASCIIPalette([.black, .palette.accent, .white])))
.imageColorMode(.palette(.shades(5)))    // five greys
.imageColorMode(.palette(.sampled(8)))   // eight, spread over the gamut
```

- **`[Color]`, not `[RGBA]`.** A `Color` can be `.palette.accent`, so a palette
  built from the theme *follows the theme* — recolour the app and the image
  recolours with it. An `[RGBA]` would freeze the answer at construction.
  Resolution happens once per conversion, in `_ImageCore`, and deliberately
  **before the render cache is consulted**: the unresolved mode is identical
  either side of a theme change, so a cache keyed on that would serve the old
  colours forever.
- **The order does not matter.** The note originally proposed a dark → light
  convention borrowed from `ASCICharacterSet.customRamp(_:)`. Both mappings
  sort or ignore the order themselves, so a palette that had to be written in a
  particular order would be one more thing to get wrong for no gain.
- **`.effective(for:)` quantises the palette rather than abandoning it.** "16.7
  million colours" has no meaning on a 16-colour terminal and has to be given
  up; "these three colours" still means something. So the entries are
  downsampled and the intent survives — the right way round, since only the
  accuracy is lost. `ASCIIPalette.sgrParameters(at:background:)` then says each
  colour in whatever form it ended up in, which is both fewer bytes than an RGB
  triple and the only spelling a terminal at that depth understands.

`B` and `C1(b)` from the request — "greyscale with a configurable shade count"
and "a palette of N by subsampling" — are not separate features. **`.shades(_:)`
is a generated grey ramp and `.sampled(_:)` is a generated subsample**, and both
are ordinary palettes once generated. That collapse is most of why this cost two
files rather than the implied surface.

**`.sampled(_:)` is deliberately not a palette derived from the image.** That
(median cut, k-means) is a different feature — "reduce this image to N colours"
rather than "draw this image in MY colours" — and it would put an image-analysis
pass with its own cache lifetime inside a renderer whose job is mapping. With
dithering on, a gamut-spread sample gets most of the same look.

### Two generators, and why each is spaced the way it is

- **`.shades(_:)` is even in PERCEIVED lightness**, not in bytes. Five
  bytes-even greys are 0, 64, 128, 191, 255 — three of them in the bright half
  where the eye can least tell them apart. Even in OKLab's L puts the middle
  step at 128 → **its actual value is well below**, which is what makes a
  five-grey render read as five distinct tones. The inverse needed is only for
  neutrals, where OKLab's L is the cube root of the linear value, so it is a
  cube and a gamma encode — no matrix, and no general OKLab → sRGB conversion
  for this module to carry.
- **`.sampled(_:)` is farthest-point in OKLab** over the 240 colours of the
  256-palette. Every entry is one any 256-colour terminal renders exactly, so a
  palette chosen this way never shifts underfoot when the image is downsampled;
  and farthest-point covers the gamut where "every k-th index" clusters wherever
  the cube happens to be dense.

## The mapping, and the trap in it

The obvious implementation is nearest-neighbour in RGB per pixel. It is also
the one that produces the two failures worth designing around.

**Failure 1 — flattening.** Map a photograph onto three colours by nearest
neighbour and large regions collapse to one, because within a region every
pixel's nearest palette entry is the same. **Dithering answers this, not a
cleverer metric**: `quantizePixel` gained a `.palette` case, so the error
diffused between two entries is what makes a boundary read as a gradient
instead of a step.

**Failure 2 — the metric.** The instinct is to reach for a perceptual distance,
and there is one to hand — `hueWeightedDistanceSquared`. Do not. It is
load-bearing for `SystemPalette` derivation: `isVisiblySeparate` reads
*quantised* colours, so retuning that metric moves the whole surface walk. Three
attempts at retuning it during the gradient work each broke palette derivation
and each was reverted. The mapper uses **plain OKLab distance**, and
`Color.oklab(red:green:blue:)` became `package` rather than being copied — a
second set of those coefficients is a second place for them to drift.

### The recommendation that was wrong, and the case that proved it

The note recommended **luminance-ordered assignment, not nearest-RGB**, on the
grounds that it never flattens. Building it, that looked like an unnecessary
second rule: for a palette that is a ramp, nearest in OKLab *reduces* to nearest
in lightness, because the entries' `a` and `b` are equal and drop out of the
comparison. One rule, `.shades(_:)` needing no special case. So it shipped with
nearest-colour only.

Then the Example's own demo showed what that costs. `{black, accent, white}` in
the shipped green theme renders **black and white, and no accent at all** — the
accent sits at OKLab L 0.887 against white's 0.922, so every grey in a
photograph is closer to one of the other two. Three colours asked for, two
delivered, and nothing about the result says why.

So both rules ship, as `ASCIIPaletteMapping`:

| | what a pixel picks | right for |
|---|---|---|
| `.nearestColor` (default) | the entry it is closest to in OKLab | the palette standing IN for the image's colours — `.shades`, `.sampled`, hues chosen to match a subject |
| `.toneRamp` | the entry at its tonal RANK, dark to light | "draw this in my three colours", where every colour must be used |

The trade runs both ways, which is what makes it a choice rather than a default:
`.toneRamp` will recolour a flag, because rank ignores which colour a pixel
actually was. `.toneRamp` indexes by BT.601 luminance — the same measure every
other renderer in this module reads — so a colour ramp's steps fall where the
glyph ramps' do.

Note also what this settles from the original open questions: **the palette does
not include a background.** Its colours are inks on the app's background, like
`.grayscale`, not ink-and-paper like `.mono`. Consistent with every other
coloured mode, and "draw nothing here" is what `.mono` is for.

## What it does not do

- **Not a replacement for `.ansi256`.** This is intent, not capability. A user
  who wants the best available rendering should keep getting it.
- **Not automatic.** No "detect the theme and use it" default. An image in the
  theme's colours is a strong stylistic choice and should be asked for.
- **Not a recolouring.** `{black → white, white → black}` is not a two-entry
  palette; see below. The two compose: a curve says what the tones BECOME, a
  palette says which colours are available to say it in.

## The other half: recolouring, as a curve

`.imageToneCurve(_:)` takes pairs — "this becomes that" — and is the answer to
the request for a colour transformation expressed as a mapping.

```swift
.imageToneCurve(.inverted)
.imageToneCurve([(.rgb(0, 0, 0), .rgb(20, 20, 60)),        // navy shadows,
                 (.rgb(255, 255, 255), .rgb(255, 215, 130))])  // warm highlights
```

**It is not a palette, and implementing it as one would be a plausible-looking
wrong answer.** `{black → white, white → black}` asked for as a two-entry
palette gives a two-colour image; what it means is a *continuous* inversion in
which mid-grey comes back mid-grey. So the pairs are read as a transfer curve:
each pixel's tone picks a position, and the colour there replaces it. The image
keeps all of its depth and only changes what that depth is made of.

Two things it has to get right:

- **Where it lands in the pipeline.** Before everything — before the monochrome
  threshold, before dithering, before any palette mapping. An inversion moves
  where the ink/background split falls, so a threshold measured on the original
  would be measured on tones that no longer exist. There is a test for this
  through the whole converter rather than a comment claiming it: inverting the
  image inverts which cells are ink, and the two counts are complementary
  because Otsu re-measures.
- **One colour space, not two.** The first version indexed the curve by OKLab
  lightness and interpolated in linear light, and sent mid-grey to **170** under
  `.inverted` — a visibly washed-out negative, because 0.6 of the way
  perceptually is 0.6 of the *light* rather than 0.6 of the way to the other
  colour. Both the index and the interpolation are now ordinary gamma-encoded
  sRGB, indexed by this module's own BT.601 luminance, and `.inverted` sends 128
  to 127. Consistency with the module has a second payoff: the curve's positions
  agree with where `monoInkThreshold(for:)` will fall, and the curve runs
  immediately before it.

`.inverted` is spelled with explicit RGB rather than `.black` and `.white`,
because the named ANSI white is **229**, not 255 — it is a terminal colour, and
terminals reserve the top of the range for bright white. A negative stopping at
229 would quietly lose the last of its highlights.

A stop may name a theme colour, resolved the same way a palette entry is. An
unresolved stop drops out, and a curve left with fewer than two knots is inert
rather than wrong.

### Where a stop sits is a choice, and editing one has to show that

The `from` side of a pair is read for its **luminance and nothing else** — that
is what makes a curve a curve — so `ASCIIToneCurve.Stop` states it as a
position on the tone axis (`0` black … `1` white) via `Stop.position` and
`Stop(at:to:)`. A `from` written as any other colour still works; only its tone
was ever consulted, and a grey is the one spelling that says so.

Those positions used to be what distinguished this from a gradient. They are
not any more: a ``Gradient`` is stops at positions too, and
``GradientEditorPanel`` edits them. **What still separates the two is the
AXIS.** A gradient's positions are along the thing being painted — where a cell
sits in a box — so it answers "given a position, what colour?". A curve's
positions are on the *tone* axis of what is being sampled, so it answers "given
this pixel's brightness, what colour?". Same shape, different independent
variable, and nothing converts one into the other.

(Whether `ASCIIToneCurve` should therefore BE a `Gradient` read with a tone for
its parameter is a fair question, and not this document's: it would change the
image pipeline's public vocabulary for a saving that is real but small.)

`ToneCurveEditorPanel` is the editor that can say the general case. It draws
two aligned strips read **column by column** — the tone arriving above, the
colour leaving below — with a marker under each stop:

```
 in  ████████████████████████████████████
     ▲          ▲                  ▲
 out ████████████████████████████████████
```

Two properties are worth stating because they are what make it usable rather
than merely correct:

- **Adding a stop changes nothing.** A new stop takes the colour the curve
  already produces where it lands, so a curve can be refined rather than
  restarted. It lands halfway to the next stop, or halfway back to the
  previous one where there is no room after — which is the case that matters,
  because the last stop is almost always at white and "+" on it would
  otherwise put a second stop on top of it and appear to do nothing.
- **The selection follows the stop, not the slot.** Moving a stop past its
  neighbour re-sorts the list, and the panel re-finds the stop it was editing —
  otherwise dragging one across another would silently hand you a different
  stop to edit.

The lower strip goes through `ASCIIToneCurve.color(atTone:)`, which is
`apply(to:)` — the renderer's own path — rather than a second copy of the
interpolation. It deliberately does NOT use `Color.quantisedRamp`, which
repairs a gradient into a monotone one on a 256-colour terminal: a curve is not
required to be monotone, and a preview that banded differently from the picture
beside it would be worse than one that bands with it.

## Considered: a 3-D LUT (and what was built instead)

A 3-D LUT — the `.cube` file a colour grade ships as — maps *(R, G, B)* to
*(R, G, B)* through a cube of samples with trilinear interpolation between
them. It is the thing a tone curve is the one-dimensional case of, and the
question is whether it is worth having.

**Mechanically it is easy, and cheap.** It would sit exactly where the tone
curve does, in the `mapPixels` immediately after the box reduction — so it sees
the *sampling* grid, not the source image. That grid is `cols × grid.x` by
`rows × grid.y`: 25,600 pixels for braille at 80×40 cells, and 160,000 in the
heaviest case (the shape matcher's 5×10). A 33³ cube is 108 KB of bytes and a
trilinear read is a few dozen operations, so the whole pass is well under a
millisecond, behind a render memo that only re-runs when something changed.
Parsing `.cube` is about sixty lines of text handling and no new dependency.

**The reasons not to are about what it would be FOR.**

- **It cannot be authored here.** A 33³ cube is 35,937 entries. There is no
  terminal editor for that and there is not going to be one, so the feature is
  *load someone else's grade*, not *express a mapping* — a different feature
  from the one `.imageToneCurve` is, and a smaller one.
- **Most of its subtlety dies downstream.** A film LUT earns its keep in the
  last few percent of colour, and the default output here is a 6×6×6 cube of
  256 colours in a grid of character cells. On a truecolor terminal drawing
  braille or half blocks it would survive; on `.ansi256` almost none of it
  would, and the palette machinery already decides what colours are available.

**The middle rung is the interesting one, and it is the one that shipped:
per-channel curves.** Three transfer functions — `ASCIIToneCurve.Channels`,
one `Ramp` per channel — cover most of what "remap the colours" actually means
in practice: colour casts, cross-processing, split-toning, warm highlights over
cool shadows. They cannot rotate a hue or touch one colour selectively; only a
true cube can do that.

They also retired a wart. `.inverted` used to be a Boolean on the type
(`negatesChannels`) rather than a curve, and the doc comment said why: a
negative complements each channel independently, which *cannot be said as a
curve* when the curve is a function of luminance alone. It is now three
descending ramps, which is exactly what "complement every channel" means, and
the special case stopped being one. The arithmetic had to survive the move —
the old implementation was `255 &- v` and the new one interpolates through
`Double` — so there is a test over all 256 levels, beside the existing one that
a negative is its own inverse.

`ChannelCurveEditorPanel` edits them. A function of one variable is drawn as
one: input left to right, output bottom to top, filled height at a column is
what that input becomes.

```
                                 ▂▄▆█
                         ▂▄▆████████
                 ▂▄▆██████████████
         ▂▄▆██████████████████
 ▂▄▆██████████████████████
     ▲              ▲          ▲
```

A **fill** rather than a line, because a cell grid draws a fill honestly and a
line badly: a one-cell-thick diagonal through a 36×8 grid is a staircase with
gaps in it, and the eye reads the gaps as the data. Eight rows × eight sub-cell
levels is 64 steps, which is past what anyone reads off a terminal anyway. The
row builder is a static function rather than inline in the view, so the test
can assert the claim — filled height equals the ramp's value — without doing
substring arithmetic on a bordered, centred dialog; a separate test ties the
function to the view by finding its rows in the rendered buffer.

The remaining recommendation: **a 3-D LUT only ever as a `.cube` loader, never
as an editor**, and only if someone actually wants to apply a grade authored
elsewhere.

## `.ansi256` became one of these too

**Status: shipped 2026-09-04.** The ladder above described `.ansi256` as
"256 colours", and the way it reached them was the one thing in this module
that was not a palette search: each channel divided by 51 and rounded onto the
6×6×6 cube, with a near-grey short-circuit onto the 24-step ramp. It was the
cheapest mode by a distance, and the reason it was cheap was that it guessed.

What that bought was **a second quantiser on one screen**. `.effective(for:)`
sends every `.trueColor` image to `.ansi256` on a 256-colour terminal, and the
page the picture sits on is quantised to those very same 240 entries by
`Color.downsampledToPalette256()` — an OKLab search with hue weighted. The two
disagreed for **85%** of colours, and visibly: the framework's own warm cream
`#F2DEC9` came out `(255,215,215)`, a pink, in the picture and `(255,215,175)`,
warm, in the background behind it. The near-grey test compared red against green
and green against blue but never red against blue, so a pale blue `#C8D0D8` was
declared neutral and drawn as flat grey where the page beside it kept its tint.

`.ansi256` is now `ASCIIPalette.ansi256`, a palette of those 240 entries, and
`ASCIIColorMode.searchedPalette` returns it like any other. One palette answers
by `Color`'s rule rather than by this module's plain OKLab, which is the only
place in TUIkitImage that happens and is stated at the line: these colours are
not the app's, they are the terminal's, and the UI is already painted in them.
Measured against `Color`'s answer, plain OKLab over the same 240 entries would
still disagree for 31% of colours, so borrowing the rule — rather than
re-deriving a similar one — is the whole point.

**What it costs, measured in a release build** (`Tools/Profiling/ImageHarness`,
a 180×75 photograph, M-series):

| path | asks | before | after |
|---|---|---|---|
| glyph (`convert`, 120×50 cells) | twice per cell | 0.75 ms | 6.1 ms |
| pixel (`recoloured`, 960×850) | once per pixel | 11.7 ms | 9.3 ms |

The per-cell path pays for exactness — `Color`'s answer is a 240-entry scan at
about 450 ns, against a few nanoseconds of arithmetic — and gets it: the index
in a glyph's `38;5;n` is now bit-identical to the one the UI beside it is
painted with. That conversion is cached in `StateStorage` per view, so it is
paid when the picture, the size or the settings change, and `.trueColor` on the
same picture costs 4.4 ms for comparison.

The per-pixel path cannot pay for exactness — 800,000 pixels × 450 ns is
over a third of a second — so it takes the same table every other searched palette
takes, built once for the process because these 240 colours never change. It
comes out **faster** than the arithmetic it replaced, because a table lookup is
cheaper than three roundings and a branch. What the table costs in accuracy is
measured in `PaletteTableFidelityTests`, and it is still an order of magnitude
closer than the arithmetic was:

| | differs from the exact answer | mean excess distance | worst |
|---|---|---|---|
| the old cube arithmetic | 85.0% | 0.0447 | 0.157 |
| the table (pixel path) | 13.6% | 0.0044 | 0.142 |
| the exact search (glyph path) | 0% | 0 | 0 |

("Excess" is how much further the chosen entry sits from the pixel than the
exact answer does, in OKLab; two adjacent cube levels are about 0.13 apart.)

The table has no boundary fallback, which every other palette's does. That is
not an oversight: with 240 entries only 33% of cells have six agreeing
neighbours, so the fallback would fire for three pixels in four and cost more
than the search it was meant to avoid.

**A grey answers differently now, and better.** The old near-grey branch matched
against the 24-step ramp alone. The cube has six greys of its own — 0, 95, 135,
175, 215, 255 — and four of them fall between ramp steps, so `(92,92,92)` is
three units from the cube's `(95,95,95)` and four from the ramp's `(88,88,88)`.
Searching the whole 256 finds them. `(2,2,2)` moved too, from black to
`(8,8,8)`: sRGB's transfer function is steep in the shadows, so in perceived
lightness it is nearer the ramp's first rung than it is black, however the byte
values read.

## Still open

- **Should `.grayscale` become `.palette(.shades(24))` internally?** It is 24
  greys mapped by lightness, which is exactly what this does. Folding it in
  removes a code path; keeping it separate keeps a familiar case cheap and its
  output byte-identical. Worth doing after this has been looked at, not as part
  of the same change.
