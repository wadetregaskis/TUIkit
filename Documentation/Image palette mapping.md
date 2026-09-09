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
.imageColorMode(.palette(.spread(8)))    // eight, spread over the gamut
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
is a generated grey ramp and `.spread(_:)` is a generated subsample**, and both
are ordinary palettes once generated. That collapse is most of why this cost two
files rather than the implied surface.

**`.spread(_:)` is deliberately not a palette derived from the image.** That
(median cut, k-means) is a different feature — "reduce this image to N colours"
rather than "draw this image in MY colours" — and it would put an image-analysis
pass with its own cache lifetime inside a renderer whose job is mapping. With
dithering on, a gamut-spread sample gets most of the same look.

> That separate feature was later built, as `ASCIIPalette.adaptive(_:by:target:)`
> — including the image-analysis pass, which is per conversion and cached with
> the conversion. The generator this note designed as `.sampled(_:)` has been
> `.spread(_:)` since 2026-09-04 (`b50d5114`) — "which N colours, out of what" —
> which is the name used above; the two sit side by side in the Example's colour
> controls precisely because they answer different questions. See "An adaptive
> palette has to know what the terminal can draw" below.

### Two generators, and why each is spaced the way it is

- **`.shades(_:)` is even in PERCEIVED lightness**, not in bytes. Five
  bytes-even greys are 0, 64, 128, 191, 255 — three of them in the bright half
  where the eye can least tell them apart. Even in OKLab's L puts the middle
  step at 128 → **its actual value is well below**, which is what makes a
  five-grey render read as five distinct tones. The inverse needed is only for
  neutrals, where OKLab's L is the cube root of the linear value, so it is a
  cube and a gamma encode — no matrix, and no general OKLab → sRGB conversion
  for this module to carry.
- **`.spread(_:)` is farthest-point in OKLab** over the 240 colours of the
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

*The trap inside the answer (2026-09-05).* Error diffusion hands each pixel's
shortfall to its neighbours on the assumption that they can make it up, and
a palette that lacks a hue cannot. A dark blue through greys leaves a
blue-channel error of +75; the neighbour takes it and is bluer still, and so
on along the row until the channel pins at 255 and the pixel is a saturated
blue whose *lightness* is far above the original's — so every grey chosen
from there on is too light. Measured on the demo photograph through 134
greys: +4 levels on average, +41 where the drift peaked, a haze that read as a
shadow beside every dark shape; through the demo's eight-entry "Ice" palette,
+33 on average and +102 at the peak. So a chosen palette (`.palette`) now
carries its error in **OKLab**, the space the nearest search decides in, and
clamps the carried colour per axis to the least and greatest its entries
reach: lightness is carried in full, an axis the palette does not span stops
at its edge. Greys read +0.02 after that, "Ice" −0.3. The terminal's own
palettes (`.ansi256`, `.ansi16`) keep the sRGB carry byte-for-byte — they
span the gamut, so there is no direction the error cannot go — and skip the
OKLab round trip, which costs the chosen-palette dither about 12 ns a pixel
on 256 greys and 58 on a 64-entry adaptive palette (`ImageHarness`, pixel
path, release).

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
| `.nearestColor` (default) | the entry it is closest to in OKLab | the palette standing IN for the image's colours — `.shades`, `.spread`, hues chosen to match a subject |
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

**Status: shipped 2026-09-04; the rule corrected the same day.** The ladder
above described `.ansi256` as "256 colours", and the way it reached them was the
one thing in this module that was not a palette search: each channel divided by
51 and rounded onto the 6×6×6 cube, with a near-grey short-circuit onto the
24-step ramp. It was the cheapest mode by a distance, and the reason it was
cheap was that it guessed.

`.ansi256` is now `ASCIIPalette.ansi256`, a palette of those 240 entries, and
`ASCIIColorMode.searchedPalette` returns it like any other — mapped by nearest
in OKLab, like every other palette here.

### Three rules for one palette, and which question each answers

It took two attempts to get this right, so it is worth writing down what the
choices actually are. All three pick from the **same 240 colours**; they differ
only in what they mean by "best".

**1. Truncation — divide by 51 and round.** O(1), no search. Its trouble is not
that it is approximate but that it is approximate *per channel independently*,
which is not how anyone sees colour: rounding red up and blue down rotates the
hue, and it does so worst where the cube is coarsest, in the pale range. The
framework's own warm cream `#F2DEC9` came out `(255,215,215)`, a pink. It also
cannot see the grey ramp except through a hand-written short-circuit, and that
one compared red against green and green against blue but never red against
blue — so a pale blue `#C8D0D8` was declared neutral and drawn flat grey. The
divisor is not even the right arithmetic: the cube's levels are 0, 95, 135, 175,
215, 255, which are not multiples of 51.

**2. Nearest in OKLab.** Convert the pixel and every candidate to a space built
so that equal distances look equally different, and take the closest. This is
"which of these 240 colours is a person least likely to notice the substitution
of". It uses the grey ramp when the ramp is nearest — which for a photograph is
often, because the ramp's 24 rungs are ten units apart where the cube's six are
forty, and a photograph's metals, skies and shadows live near the neutral axis.
This is what every other `ASCIIPalette` uses, and it is what an image wants.

**3. `Color.downsampledToPalette256()`, the UI's quantiser.** Deliberately *not*
nearest. It weights hue ×4, charges chroma LOSS ×4, and applies a gate:
a colour with any chroma at all (OKLab ≥ 0.01) may not quantise to a grey. That
is a rule about colour **identity**, and the UI needs it — a designed colour is a
semantic thing, and the gate is what stops a fading accent from stepping red,
red, red, GREY, grey, black.

The mistake worth naming is the one made on the way here: **`.ansi256` briefly
borrowed rule 3**, on the argument that one screen should not answer the same
RGB two ways. That conflates sharing a *palette* with sharing a *rule*. Sharing
the palette is what makes a screen coherent, and both do. Sharing the rule makes
the picture wrong, because the two callers are asking different questions — the
UI about a few dozen colours that each mean something, the image about a million
that mean nothing individually and whose residual error dithering exists to
spread.

Measured, applying rule 3 per pixel:

| | rule 2 (nearest) | rule 3 (the UI's) |
|---|---|---|
| colours denied the grey ramp by the gate | none | **99.8%** |
| random sweep answered from the ramp | 6.4% | **0.23%** |
| mean OKLab error, random sweep | 0.0384 | 0.0433 |
| mean OKLab error, near-neutral band | 0.0124 | **0.0260** (2.1×) |
| `demo-image.jpg` at 220×220, mean OKLab error | 0.0225 | **0.0381** (1.7×) |

The near-neutral row is the one that matters, because that is what a photograph
is mostly made of. A dark blue-grey `(96,100,106)` — ten units of spread between
its channels — comes back `(95,95,135)` under rule 3, a navy with forty. The
picture's greys **invent a hue**: on `demo-image.jpg` the brushed-metal ring
broke into flat teal and lavender patches. The number that names the cause is
the first row: the gate fires for essentially every pixel that is not exactly
neutral, so the only fine-grained tonal detail this palette has is unreachable.

The 31% figure once cited for "plain OKLab still disagrees with the UI" was
never error. It is the size of rule 3's deliberate bias, measured.

### What it costs, measured in a release build

`Tools/Profiling/ImageHarness`, a 180×75 photograph, M-series, three alternating
reps of paired binaries:

| path | asks | cube arithmetic | rule 3 | rule 2 (shipped) |
|---|---|---|---|---|
| glyph (`convert`, 120×50 cells) | twice per cell | 0.75 ms | 6.3 ms | 4.5 ms |
| pixel (`recoloured`, 960×850) | once per pixel | 11.7 ms | 9.5 ms | 9.5 ms |

The per-cell path pays for searching and gets a right answer for it. It is 28%
cheaper than rule 3 was — a plain three-term distance against a gate, a chroma
split and two extra weights — and that conversion is cached in `StateStorage`
per view, so it is paid when the picture, the size or the settings change rather
than per frame. `.trueColor` on the same picture costs 4.4 ms, so the searched
mode is now the same order as the default rather than a fifth of `.ansi16`.

The per-pixel path cannot search at all — 800,000 pixels against 240 entries — so
it takes the same quantisation table every other searched palette takes, and is
unchanged by the rule (the work is a table lookup either way). It is still
**faster than the arithmetic it replaced**, because one array read beats three
roundings and a branch.

Two things that table does differently from every other palette's, both forced by
having 240 entries where the next largest here has 16:

- **Built once for the process**, not per conversion. A table is 32,768 exact
  answers, so this one is fifteen times the work `ansi16`'s is — and it is the
  same table every time, because these 240 colours are the terminal's and not
  the app's.
- **No boundary fallback.** The `trusted` mask exists so a cell straddling two
  entries is looked up exactly instead of guessed. With 240 entries only 33% of
  cells have six agreeing neighbours, so the fallback would fire for three
  pixels in four, each walking 240 entries — most of a second for a megapixel.

What that costs is measured in `PaletteTableFidelityTests`:

| | differs from the exact answer | mean excess distance | worst |
|---|---|---|---|
| the old cube arithmetic | 85.0% | 0.0447 | 0.157 |
| the table under rule 3 | 13.6% | 0.0044 | 0.142 |
| the table under rule 2 | 13.4% | 0.0041 | **0.027** |
| the exact search (glyph path) | 0% | 0 | 0 |

("Excess" is how much further the chosen entry sits from the pixel than the
exact answer does, in OKLab; two adjacent cube levels are about 0.13 apart.)

The worst case improved 5× along with the rule, and for a reason worth keeping:
rule 3 forbids a tinted colour the grey ramp, so its regions are not contiguous
in OKLab and two adjacent table cells can answer with entries nowhere near each
other. Rule 2 has no holes, so a cell's neighbours really are its neighbours and
a miss is always a near tie.

**A grey answers differently than the arithmetic gave, and better.** The old
near-grey branch matched against the 24-step ramp alone. The cube has six greys
of its own — 0, 95, 135, 175, 215, 255 — and four of them fall between ramp
steps, so `(92,92,92)` is three units from the cube's `(95,95,95)` and four from
the ramp's `(88,88,88)`. Searching the whole 256 finds them. `(2,2,2)` moved too,
from black to `(8,8,8)`: sRGB's transfer function is steep in the shadows, so in
perceived lightness it is nearer the ramp's first rung than it is black, however
the byte values read.

### The per-cell search stops walking — 2026-09-04

The table above answers the per-pixel path; the per-cell path kept its walk
for exactness, and once the glyph renderer's colour SPELLING was fixed (the
per-cell escape strings were 97% of a truecolor frame; `ANSIRowBuilder`) the
walk was what remained: 513 ns a cell at `.ansi256`, 606 at `.shades(256)`.

`ASCIIPalette.SearchIndex` keeps the exact answer and drops the walk. Over
the same perceptually-spaced 5-bit grid as the table, each cell lists the
entries that can be nearest to some colour inside it — everything within
`|nearest(centre) − centre| + 2·radius` of the centre, the radius being the
cell's farthest sRGB corner in OKLab, widened a tenth for the curvature
between corners (widening only adds candidates). The bound is a triangle
inequality and the tie-break is the walk's, so the answers are the walk's;
`PaletteSearchIndexTests` says so at every corner of every populated cell
and across a stride of the gamut, for four palettes. Palettes of more than
sixteen entries use it; `ansi16` and smaller still walk, which is faster
for them. One index per set of colours, cached process-wide and memoised
per palette instance. The table's boundary fallback uses it too, so a
palette the pixel path cannot trust everywhere no longer pays a walk on the
cells it distrusts.

`ImageHarness`, release, base and new binaries back to back:

| | before | after |
|---|---|---|
| glyph `.ansi256` | 749 ns/cell | 112 |
| glyph `.shades(256)` | 1,486 | 252 |
| glyph adaptive 64 (least error) | 832 | 360 |
| glyph adaptive 256 | 2,252 | 1,092 |
| pixel adaptive 64 (table + fallback) | 63 ns/pixel | 34 |
| pixel `.ansi256` (table, no fallback) | 12.7 | 10.5 |

The `.ansi256` pixel path's own gain is not the index — that table trusts
every cell and never searches — but the per-pixel loop no longer copying the
palette out of an enum payload (`PixelQuantiser`); the day the palette gained
its index reference, that copy measured +35% on a lookup nothing had changed.

## An adaptive palette has to know what the terminal can draw

**Status: shipped 2026-09-08.** Reported as three separate complaints, all one
bug: "going from 4 to 5 colours with Least error changes nothing in the image,
same for 8 to 9 and 9 to 10", and "Least error with 256 colours looks noticeably
different from — worse than — plain 256-colour mode in Terminal.app".

`ASCIIConverter.convert(_:width:height:)` did
`effectiveMode.derived(from: scaled).effective(for: depth)`: **derive first,
quantise second.** The derivation is textbook and correct — median cut plus
Lloyd in OKLab, and it does produce `n` distinct colours for every `n` — but it
ran in continuous colour, and the snap afterwards **collapsed entries onto each
other**. Asking for five gave a palette bit-identical to the one four gave.
Asking for 256 gave 51.

The fix is to choose from the target's own colours in the first place:
`ASCIIPalette.AdaptationTarget`, an associated value on the request, with
`.automatic` (whatever the output is) and `.depth(_:)` for each of the four.
Measured on `demo-image.jpg` (1101×1080, 5,078 populated 5-bit cells), weighted
mean OKLab error at `.palette256`, `.leastError`:

| n | 4 | 5 | 8 | 9 | 10 | 16 | 32 | 64 | 128 | 256 |
|---|---|---|---|---|----|----|----|----|-----|-----|
| distinct, blind | 4 | **4** | 7 | **7** | **7** | 12 | 17 | 23 | 35 | **51** |
| distinct, aware | 4 | 5 | 8 | 9 | 10 | 16 | 32 | 64 | 128 | **240** |
| error, blind | .04983 | .04983 | .03878 | .03878 | .03878 | .03646 | .03424 | .03083 | .02725 | .02422 |
| error, aware | .04486 | .03814 | .03034 | .02954 | .02890 | .02582 | .02295 | .02158 | .02131 | .02125 |
| better by | 10.0% | 23.5% | 21.8% | 23.8% | 25.5% | 29.2% | 33.0% | 30.0% | 21.8% | 12.3% |

Plain `.ansi256`'s error on the same picture is **0.02125**. So the second
complaint is answered exactly: at 256 the aware palette reaches that figure to
five decimal places, because 240 colours chosen from a 240-colour lattice *is*
that palette. Blind, it lost to it by 14%.

### How it chooses

`ASCIIPalette.representable(at:)` answers the lattice with palettes this module
already has — `.ansi256` (240 entries), `.ansi16` (the sixteen names),
`.shades(2)` for `.noColor`, and `nil` for `.truecolor`, which constrains
nothing. Reusing them is the point: a constrained adaptive palette picks from the
very entries the non-adaptive palette for that depth holds, so the two are
comparable rather than merely near each other.

- **`.leastError` is Lloyd with a projection.** Each pass takes the cluster's
  weighted mean as before, then moves the centre to the nearest colour the output
  has. Projected Lloyd is **not monotone** — the projection can give back a
  little of what the mean won — so convergence is tested on the *colours* rather
  than on the means, which drift on inside one lattice cell forever, and the
  existing pass budget bounds the rest.
- **Distinctness is a step, not a hope.** `snapping(_:)` assigns nearest-first:
  a centre already sitting on its colour keeps it, and the one that collided with
  it takes its own next best. First-come-first-served would hand the entry to
  whichever centre happened to be earlier in the array.
- **`.popularity` skips instead.** It walks its ranking past cells whose colour
  the output has already spent — two popular cells a third of a cube step apart
  *are* one colour there — rather than offering the second one a different
  colour, which would be inventing a colour the picture does not contain. Its
  one regression is n=4 on this picture, 4.4% worse: four distinct colours, and
  they cost more total error than three collapsed ones did. That is not a defect
  in the fix; popularity is a ranking, and four is what was asked for.

### Two rules that are easy to get wrong

**The depth is a parameter, never `ColorDepth.current`.** `recoloured` sends
pixels as RGB inside a Kitty/iTerm2 picture, so its palette is 24-bit on the very
terminal where the glyph rendering of the same picture is 256-colour.
`ASCIIConverter.recoloured` passes `.truecolor` unconditionally, and
`AdaptationTargetTests.theGraphicsPathIsUnconstrained` pins it.

**The second fit stays.** `.effective(for:)` still runs after the derivation, and
must: it exists because an adaptive palette changes its colours *after* the first
fit, and unfitted RGB triples on a 256-colour terminal made Terminal.app read
`38;2;r;g;b` as five SGR codes and draw "Most used" as blinking primaries
(`AdaptivePaletteDepthTests`). What the targeting changes is that the fit is now
a **no-op by construction**: the chosen colours are the lattice's own
`.palette(n)` / `.standard(.red)` entries, and those downsample to themselves.

### What it costs

Less, which was not the expectation. `ImageHarness --path palette`, release,
120×50 source, ms per derivation:

| mode | `--depth truecolor` | `ansi256` | `ansi16` |
|---|---|---|---|
| `optimal8` | 0.333 | 0.227 | 0.234 |
| `optimal64` | 1.365 | 0.659 | 0.404 |
| `optimal256` | 4.919 | **1.448** | 0.634 |
| `popular8` | 0.115 | 0.118 | 0.123 |
| `popular256` | 0.122 | **0.571** | 0.149 |

The projection is `count × entries` distance evaluations a pass — 61k at 256
colours against the Lloyd pass's five million — and it pays for itself many times
over by converging in two or three passes where the unconstrained one spends its
whole twelve-pass budget chasing means that never settle. `popular256` is the one
that costs: finding 256 *distinct* lattice colours walks further down the ranking,
at a 240-entry search per cell it passes.

## Still open

- **Should `.grayscale` become `.palette(.shades(24))` internally?** It is 24
  greys mapped by lightness, which is exactly what this does. Folding it in
  removes a code path; keeping it separate keeps a familiar case cheap and its
  output byte-identical. Worth doing after this has been looked at, not as part
  of the same change.
