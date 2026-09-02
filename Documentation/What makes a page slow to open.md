# What makes a page slow to open

Reported: the Colors, Sliders and Progress & Gauges pages of the Example app
are noticeably slower to open the first time and quick on every later visit,
and the one thing they have in common is gradients. Separately: gradients are
sluggish to redraw on Apple Terminal while iTerm2 is fast, in proportion to how
many colours the gradient has.

Both were measured. Neither is about gradients.

## The answer, first

1. **The first render of a page's subtree costs ~35× a later one**, because
   later ones are served whole from the render memo. Every page pays it, once
   per session. In the DEBUG build that is 620 ms of CPU for the Colors page
   against 183 ms afterwards, with 590 ms before the first byte appears — which
   is the report. In RELEASE the same premium is 13 ms, and imperceptible.
2. **The pages named are the dearest to render on EVERY visit**, not only the
   first: Progress & Gauges 69 ms, Colors 57, Sliders 36.5, against Toggles 27
   and Text Styles 17 (release CPU per open). The reported ordering is exactly
   the measured one. The two effects multiply, which is why those three are the
   ones you notice.
3. **Colour work is 0.5% of the Colors page's own profile.** The rest is the
   measure/render pipeline (~25%), the allocator (~16%) and refcounting (~7%),
   with no hot spot to remove.
4. **On the host reported as slow the framework emits FEWER bytes than on the
   host reported as fast**, and since `589b557e` about 20% fewer again. What is
   left is Apple Terminal's own per-colour-change painting cost.

The one actionable thing is the build. Beyond that the lever is the cold-render
path itself, which is a flat profile — see "What is left".

## Cold is real, universal, and not about gradients

`Stress --bench --cold` builds a fresh context per frame, so every memo is
cold. Release, 120×40, 40–60 iterations:

| scenario | cold µs/frame | warm | ratio |
|---|---|---|---|
| `gradients` | 40,843 | 3,883 | 10.5× |
| `modifiers` | 44,665 | 961 | 46× |
| `textwall` | 10,635 | 2,298 | 4.6× |
| `kitchensink` | 6,969 | 657 | 10.6× |
| `dashboard` | 7,013 | 174 | 40× |

Every scenario pays it, and the two dearest ratios are not the gradient one.
`gradients` does have the highest WARM cost in the harness (3.9 ms against
0.17–2.4 ms), but that is a cost paid on every frame, not a first-visit one.

## The mechanism: the render memo, per subtree

One view tree rendered six times into one context (debug):

    pass 1: 4,946µs   pass 2: 148µs   pass 3: 135µs   pass 4: 134µs …

A 35× premium, and it is the RENDER memo rather than the measure one — the
measure memo records 312 misses on the first pass and is not consulted again,
so what serves passes 2+ is the whole-subtree buffer. A *different* tree of the
same shape, in the same warm process and context, still costs 2,706 µs on its
first pass: about 45% of the premium is shared first-touch and the rest is
genuinely per-subtree.

The view body is called exactly **once per pass**, first pass included, so
there is no hidden second render to remove.

In the app the same thing is page-specific rather than process-wide: opening
Toggles, Text Styles, Sliders and Progress & Gauges first and only then Colors
gives 650 ms against 620 — no help at all.

| page (debug) | first open | later opens | to first byte, first |
|---|---|---|---|
| Colors | 620 ms | 183 ms | 590 ms |
| Sliders | 150 | 135 | 39 |
| Progress & Gauges | 230 | 224 | 103 |
| Toggles | 90 | 80 | 27 |
| Text Styles | 120 | 90 | 34 |

Release, same measurement, four rounds each: Colors 78/80/71/81 ms wall to
quiescence with byte-identical output every round. The premium is there in CPU
(70 vs 57 ms) and nowhere near perceptible.

`Tools/Profiling/page_open.py` is the probe: it measures a page ARRIVING, in
one process, so a once-per-session cost shows as round 0 and nowhere else.

## The profile is flat

`sample(1)` over the real app while it opens and closes the Colors page on a
loop: `renderResolved` 2.4%, `renderToBuffer` 2.1%, `measureChild` 1.9%,
`measureChildUncached` 1.7%, `measureResolved` 1.5% — the pipeline, and nothing
gradient-shaped in the top 22. Over the `gradients` Stress scenario, warm:
`IdentityNode.structurallyEqual` 6.1%, retain/release 10.5%, dictionary find +
resize + hashing 12.9%, generic metadata ~8%, and **no `Color`, `Gradient`,
`quantisedRamp` or `oklab` in the top 28 at all.**

Filtered for colour work specifically, on the Colors page's own first open:
`nearestPalette256Index` 0.23%, `downsampledToPalette256` 0.16%,
`hueWeightedDistanceSquared` 0.07%. Half a per cent, all told.

It is not content HEIGHT either: `lists` scrolls twice as far as `colors` (24
wheel notches against 11) and costs less.

## 256 colours is the cheap case, not the dear one

Page opens with and without `COLORTERM=truecolor` (release, 1.5 s window,
process CPU): at `.palette256` Colors costs 60 ms and Progress 90 ms; at
truecolor Colors costs 370–440 ms and its first paint is 17.4 KB against
3.9 KB. Quantising collapses a ramp to about ten distinct indices and the diff
writer then has almost nothing to repaint.

Apple Terminal is `TERM=xterm-256color` with no `COLORTERM`, so it gets the
cheap path. iTerm2 — the host reported as fast — gets the expensive one.

## Emission carries no redundancy

`analyze_stream.py` over live PTY captures of six pages' first paint: **0.0%
redundant SGR on five of them and 0.3% on `progress`** (one escape, 20 bytes).

A slider drag of 1,020 steps, before `589b557e`: plain track 72,355 bytes,
gradient spanning the track 65,454, gradient scaled to the fill 166,810 — the
same CPU (7.2–7.3 s) in all three. `TrackGradientScaling.fill` is the dear one
because rescaling the ramp changes every filled cell; `.track`, the default,
holds each column's colour still and costs less than a plain track.

The one avoidable pattern that WAS in that stream — 228 bare `ESC[0m` and 213
`0;`-prefixed restatements out of 608 SGR escapes, a fixed cost per pass — is
gone as of `589b557e`; see `Intra-line output diffing.md`, "Carrying state
across PASSES".

## What is left

- **The cold-render path.** A flat profile whose largest identifiable share is
  allocation (~16%), which is the `lines: [String]` question
  `Intra-line output diffing.md` names as its own next lever. Nothing smaller
  than that is worth doing here: there is no hot spot.
- **Apple Terminal's painting cost.** Out of reach from this side. The
  framework already emits less to it than to the host that feels fast.

## Method notes worth keeping

- **Measure the build the report came from.** Release said "does not
  reproduce"; debug said 3.4×. Two rounds were spent on that.
- **`ps` reports centiseconds.** A single open is one sample; the later opens
  have to be summed over many rounds and divided.
- **A window that is too long swamps the thing being measured.** A 1.5 s window
  around a 13 ms premium reports noise.
- **Reset the config directory between paired runs.** The Example persists its
  demo toggles, so run 3's state leaks into run 1 of the next invocation — which
  is how a "plain track" measurement first came back at 150,157 bytes.
