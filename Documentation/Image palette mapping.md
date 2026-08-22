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

## Still open

- **Should `.grayscale` become `.palette(.shades(24))` internally?** It is 24
  greys mapped by lightness, which is exactly what this does. Folding it in
  removes a code path; keeping it separate keeps a familiar case cheap and its
  output byte-identical. Worth doing after this has been looked at, not as part
  of the same change.
