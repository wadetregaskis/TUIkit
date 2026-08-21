# Mapping an image onto a chosen palette

A design note for the half of the image work that is not yet built: letting an
image be rendered in *a specific set of colours* rather than in the terminal's
whole repertoire. You asked to see the design before I build past monochrome.

## What exists, and the gap

`ASCIIColorMode` has four cases, and they form a ladder of **fidelity**, chosen
by what the terminal can display:

| | colours | chosen when |
|---|---|---|
| `.trueColor` | 16.7M | the terminal reports truecolor |
| `.ansi256` | 256 | it reports 256 |
| `.grayscale` | 24 greys | a deliberate stylistic choice |
| `.mono` | 2 | 16-colour terminals, `NO_COLOR`, `.noColor` |

`.effective(for:)` walks down that ladder automatically. What is missing is
orthogonal to it: a mode that says *use these colours*, chosen by intent rather
than by capability — an image drawn in the theme's palette, or in two or three
named colours, so it belongs to the app rather than sitting in it as a
photograph.

Between `.grayscale`'s 24 fixed greys and `.ansi256`'s everything, there is
nothing.

## The shape of the API

A fifth case carrying its own colours:

```swift
case palette([Color])
```

- **`[Color]`, not `[RGBA]`.** A `Color` can be `.palette.accent`, so a palette
  built from the theme *follows the theme* — recolour the app and the image
  recolours with it. That is the case worth having, and an `[RGBA]` would
  freeze the answer at construction. Resolution happens once per conversion,
  against the palette in the environment.
- **The list is ordered, and the order is dark → light.** Not because the
  mapper needs it (it does not) but because a caller writing
  `.palette([.black, .palette.accent, .white])` should get what that reads
  like. A ramp is a familiar object here — `ASCIICharacterSet.customRamp(_:)`
  already runs darkest → brightest — so borrowing its convention costs nothing
  and surprises no one.
- **`.effective(for:)` must handle it.** A palette of theme colours on a
  16-colour terminal has to degrade, and the honest degradation is to
  *quantise the palette itself* against `ColorDepth`, not to abandon it: the
  intent ("these colours") survives a downgrade in a way ("16.7M colours")
  does not. On `.noColor` it falls to `.mono`, like everything else.

## The mapping, and the trap in it

The obvious implementation is nearest-neighbour in RGB per pixel. It is also
the one that produces the two failures worth designing around.

**Failure 1 — flattening.** Map a photograph onto three colours by nearest
neighbour and large regions collapse to one, because within a region every
pixel's nearest palette entry is the same. Structure the eye can see in the
original vanishes. `Color.quantisedRamp(stops:count:depth:)` already exists for
exactly this problem in gradients, and its lesson transfers: **quantise the
sequence, not the sample.**

**Failure 2 — the metric.** The instinct is to reach for a perceptual distance,
and there is one to hand — `hueWeightedDistanceSquared`. Do not. It is
load-bearing for `SystemPalette` derivation: `isVisiblySeparate` reads
*quantised* colours, so retuning that metric moves the whole surface walk. Three
attempts at retuning it during the gradient work each broke palette derivation
and each was reverted. A palette mapper needs its own distance function, private
to it, and must not touch that one.

The recommendation, in order of what to build:

1. **Luminance-ordered assignment, not nearest-RGB.** Sort the palette by
   luminance once, then map each pixel by *where its luminance falls* among the
   entries. This is what already works for the character ramps, it never
   flattens (a monotonic input gives a monotonic output), and it makes
   `.grayscale` a special case of `.palette` rather than a separate thing.
2. **Dithering carries the residue.** The existing Floyd-Steinberg path already
   quantises against the effective mode, and this is where a three-colour
   render gets its apparent depth: the error diffused between two palette
   entries is what makes a boundary read as a gradient instead of a step. So
   `quantizePixel` gains a `.palette` case and the rest follows — which is
   also why the palette must resolve to concrete RGBA *before* dithering, as
   the mono threshold now does.
3. **Hue only if it earns its place.** Luminance ordering discards hue, which
   is right for a two- or three-colour ramp and wrong for a palette of five
   distinct hues (a flag, a logo). If that case turns out to matter, the answer
   is a *second* mode rather than a cleverer metric in this one — the two have
   genuinely different goals, and a single function trying to serve both is how
   a metric ends up load-bearing in two places at once.

## What it should not do

- **Not a replacement for `.ansi256`.** This is intent, not capability. A user
  who wants the best available rendering should keep getting it.
- **Not automatic.** No "detect the theme and use it" default. An image in the
  theme's colours is a strong stylistic choice and should be asked for.
- **No palette derived from the image** (median cut, k-means). That is a
  different feature — "reduce this image to N colours" rather than "draw this
  image in MY colours" — and building it here would put an image-analysis
  dependency inside a renderer whose job is mapping.

## Open questions for you

1. **Does the palette include a background?** A two-entry palette could mean
   "ink and paper" (draw the light one as blank, like mono does) or "two inks
   on the app's background". The first matches `.mono`; the second matches
   `.grayscale`. I lean to the second — consistent with every other coloured
   mode, and "draw nothing here" is what `.mono` is for — but it changes what
   `.palette([.black, .white])` looks like, so it is worth agreeing first.
2. **Should `.grayscale` become `.palette` internally?** It is 24 greys mapped
   by luminance, which is exactly what this does. Folding it in removes a code
   path; keeping it separate keeps a familiar case cheap and its output
   byte-identical. I would fold it *after* this ships and the mapper has been
   looked at, not as part of the same change.
