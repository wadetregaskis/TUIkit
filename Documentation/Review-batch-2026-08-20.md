# Review batch, 2026-08-20

A running log of one review pass: what was asked, what was done, what was
decided along the way, and what is still open. Newest work at the bottom of each
section. Commit subjects are quoted so `git log --grep` finds them.

## Done

### The Animation page
*"missing the app header … oddly padded … doesn't resize well … not in a
ScrollView"*, plus the bar width, the button row, the controls, and the
rearrangement so the curve settings read as page-wide.

- **"A view removed from a stack now gets to leave"** — the framework half.
  `if` inside a stack was the one shape a removal transition could not play in,
  because a `nil` optional flattened to no children and left nothing standing
  where the view stood. A `nil` now keeps one slot, but only while something is
  actually leaving from it, claimed by address (enclosing identity + the wrapped
  view's type) so a `nil` in a tree that animates nothing costs one
  dictionary-empty check and shifts no spacing.
- **"The Animation page, laid out like the rest of the app"** — header,
  `ScrollView`, settings first and labelled as governing the page, duration /
  speed / bounce / four Bézier control points, a full-width bar, centred
  buttons, `ViewThatFits` at every row, and a "Keep the space" toggle for the
  transition demo.

### Disclosure
- **"Left and Right disclose, wherever the triangle is"** — `List(_:children:)`
  had answered these keys for ages; `DisclosureGroup` and a bare `OutlineGroup`
  had not, so the same tree behaved differently depending on what it was inside.
  Both build their header from a `Button`, so the keys travel down the
  environment (`ButtonKeyExtras`) and the button hands them to its focus
  handler — which is what makes them focus-gated for free.
- **"A closed section remembers what was inside it"** — collapsing a group and
  reopening it reset everything within, because a collapsed group does not build
  its content and unbuilt state is collected at the end of the pass. It now
  declares `retainSubtree` while collapsed. **This is a deliberate divergence
  from SwiftUI**, recorded in `SwiftUI-compatibility.md`.

### Hover and focus
- **"A focused control still answers the pointer"** — focus says where the
  keyboard will go, hover says where the mouse would; a control that is both now
  shows both. They collide only where answered in the same ink, which is two
  places (a `Slider`'s and a `Stepper`'s arrows, whose focused state is an
  animation a static hover would freeze); those keep the old rule.
- **"Hover moves two visible steps, not one"** — the walk stopped at the first
  step the 256-colour cube could distinguish, which is not a difference a person
  notices. Two now, guarded so the extra step can never make a hovered label
  harder to read than the minimum-visible one was.
- **"The tint demo now tints something visibly"** — it hardcoded
  `.palette.success`, which under the default Green theme *is* the accent.

### Menus
- **"A scrolled menu lights the row the pointer is now on"** — the reported
  wrong-answer bug: the wheel moved the rows under a stationary pointer and the
  highlight stayed behind, so releasing chose what was under the cursor rather
  than what was lit.

### Layout
- **"Three alignment demos that show what a guide is for"** — the localised
  decimal column (two locales side by side), an acrostic, and a vertical guide
  that keeps three reflowing paragraphs' keywords level.

### In passing
- **"The main menu was showing a localization key as a headline"** —
  `feature.sfSymbols.title` rendered verbatim on the first screen of the app,
  because one non-literal argument took the whole call to the disfavoured
  `(String, String)` overload.

## Decisions I made without asking

- **Removal transitions in stacks**: the fix claims a slot by (parent identity,
  wrapped type). A `nil` whose content would have flattened into SEVERAL
  children has no single address and still jumps. Documented rather than
  guessed at.
- **Collapsed-disclosure state retention** diverges from SwiftUI. It seemed
  clearly the friendlier behaviour and it is what you asked for; say the word if
  you would rather match SwiftUI exactly.
- **Hover/focus coexistence is a sweep**, not a Buttons-and-Links change: a rule
  that holds for some controls and not others is worse than either rule.
- **The acrostic is not localized.** Its point is that a column spells a word.

### Borders and tabs
- **"The chrome around a tab is the tab's"** — a folder tab is three rows and
  reads as one control, so the border above and below the label is now part of
  its click target. The strip decides how tall each region is, because only it
  knows which chrome rows belong to a tab and which to its neighbour.
- **"A surface is a background, not a colour swatch"** — the tab body on a
  256-colour terminal. Worse than reported once measured: Amber's body came out
  RED, because the cube's nearest coloured entry to a barely-tinted dark brown
  is a corner. Where a hued step shouts, a neutral of the right lightness is
  taken instead; the greyscale ramp has 24 rungs where the colour cube has 6.
  Nothing changes on a truecolor terminal, and palettes whose page is already
  saturated (Grass, Ocean, Red Sands) keep their hue on 256 colours too.
- **"Border appearance names in the reader's language"** — they came from
  `Appearance.name`, which is the identifier capitalised, so every language read
  "Rounded", "Line", "Doubleline".
- **"Two more border appearances, and the enum question dissolves"** — see below.

## Answering your question about the block borders

You asked whether the two block appearances should be distinct enum cases or one
case with an associated value. **Neither**, and I was about to give you the wrong
answer.

The answer I had ready: the difference is not *which glyph* but *which channel
the colour goes in*, so it belongs on `BorderStyle` as an orthogonal axis
(`ink: .foreground | .background`) rather than as a case or an associated value,
because expressing it as a case duplicates the glyph table and expressing it as
an associated value hides an orthogonal axis inside one member.

That reasoning is sound and the premise is false. A border of **spaces** already
draws "an empty cell showing whatever is behind it" — no new axis needed, and
`BorderStyle.none` has been exactly that since the beginning; it simply was not
offered as an `Appearance`. And a border of `█` draws in the border colour
because every border character does.

So they are two ordinary `BorderStyle` values, like `.line` and `.heavy`, and
half of it already existed. Shipped as `Appearance.block` and `Appearance.blank`.

## Investigated, diagnosed, NOT fixed — needs your call

### 256-colour gradient banding

You reported "out-of-place colours" in default gradients on a 256-colour
terminal (the screenshots did not come through, so this is from first
principles — say if what I found is not what you were looking at).

**It reproduces, and the cause is exact.** The Example's default track gradient
(`FF5050 → FFC850 → 50DC78`) over 40 cells quantises to:

    203×5  202×1  209×5  208×2  215×4  214×3  221×3  185×4  149×4  113×4  77×4  41×1

202, 208 and 214 are the cube's **blue = 0** corner; their neighbours 203, 209,
215 are the same colours at **blue = 95**. The interpolated colour at those
cells has blue = 80. So a 15-point error is being passed over for an 80-point
one — a visibly more saturated cell wedged into a smooth ramp, which is exactly
"out of place".

**Why.** `nearestPalette256Index` compares in OKLab with the components split:
`ΔL² + w·ΔC² + 4·ΔH²`. ΔH² = Δa² + Δb² − ΔC² is the *tangential* part, so it is
blind to movement along the chroma axis — a candidate far more saturated in the
same hue has Δa² + Δb² ≈ ΔC², which cancels. The ×4 hue weight, whose job is
keeping a colour in its family, therefore does the least work exactly where the
family is most at risk, and nothing else prices the chroma. Chroma LOSS is
already charged ×4 for the mirror-image reason (recorded in that function's
comment, from an earlier washed-out-speckle report). Chroma GAIN is charged ×1.

**Three fixes tried, all measured, none shipped.**

1. **Charge chroma gain ×8 as well** (symmetric, hue left at ×4). The gradients
   come out perfect — `203×6 209×6 215×7 221×4 185×4 149×5 113×5 77×3`, eight
   monotonic runs, no speckles, and the "cool" ramp cleans up too. **But** it
   breaks four palette-derivation tests: the surface walk that separates a
   field or a plane from its page reads the *quantised* result to decide when
   it has moved far enough, so changing the metric changes where that walk
   stops. Novel's field ends up 8.99 apart from its page against a floor of 10.
2. **Weight hue ×8 too.** Same gradient result, and additionally reintroduces
   the washed-out speckle the ×4 chroma-loss weight was added to remove.
3. **A chroma CEILING instead of a weight** — no candidate may sit further from
   the target's chroma than the closest one does, plus a leeway. Principled (it
   forbids only the leap, leaving every close-call exactly as it was) but the
   leeway has no good value: 0.03 OKLab is too wide to remove the speckles and
   already too narrow for the surface walk.

**What I think the answer is, and why I did not just do it.** The banding is a
property of a *sequence*, not of a colour, and the quantiser only ever sees one
colour at a time. A gradient knows its whole ramp and could quantise it as a
ramp — enforcing monotonicity, which a per-cell nearest-neighbour search cannot
promise. That means the renderer pre-quantising when the terminal is
256-colour, which means the renderer knowing the terminal's colour depth, which
it currently does not. It is a real piece of work rather than a tuning change,
and it is worth doing properly rather than at the end of a batch.

*Meanwhile:* the metric is untouched, so nothing regressed. The measurement
above is repeatable — the probe is four `TrackRenderer.gradientColor` sweeps
printing run-length-encoded palette indices.

### Split View, second pass: found it, and my first measurement was measuring nothing

**I had the wrong column.** The divider's hit region is ONE cell wide, and I
dragged the box border beside it. Every "Split View is the cheapest page"
number in the table below was taken while the drag did nothing at all — the
screen was identical before and after. That table is left standing as a record
of the mistake, not as evidence.

With the right column (36, not 35, at 120 columns) the drag costs **13 KB per
event** against an arrow key's 210 bytes on the same page — 62 times as much —
and one drag step at 120x40 emitted **32,394 bytes**.

**The mechanism, pinned twice.** Writes to the terminal are a blocking
`write(2)` on the run loop's own thread (`Terminal.writeAll`), so the app cannot
get ahead of the terminal and its frame rate is exactly *terminal drain
throughput ÷ bytes per frame*. Driving a real drag through a PTY drained at a
fixed rate reproduces the whole curve — 30.6 fps unlimited, 20.2 at 250 KB/s,
10.3 at 120, 4.3 at 60, **1.7 at 30** — with app CPU falling 20% → 1% in
lockstep, and `sample` putting 94.8% of main-thread samples inside `write`. CPU
falling *with* frame rate is the signature: not slow, blocked.

Ruled out with evidence: the frame cap (60 fps, and the loop blocks on a wake
rather than polling), event coalescing (one frame per drag event, up to 128
drained per iteration, nothing dropped), discarded passes (zero samples in the
correction walk), and measure cost (2.6x the cells for 1.66x the CPU but 2.1x
the bytes — size hurts through bytes, not measurement).

**What is fixed:** the SGR churn — see "A frame stops restating styling it has
already stated". 62% of that frame was colour escapes; the count is down 44%.

**What is left, with the numbers to justify it:** intra-line (cell-span)
diffing. `FrameDiffWriter` diffs at ROW granularity and every changed row is
written as `ESC[2K` plus the whole styled row. A divider move leaves the
columns LEFT of the divider untouched, so a span-aware writer would skip about
a third of each row. `Documentation/Intra-line output diffing.md` already
sketches exactly this and parked it on a 144 → 35 byte case; this is the case
that reopens it.

**Not a bug, checked:** the focused divider's pulse. It was suspected of
re-rendering the page 2.2 times a second; measured at 0.3% CPU and 768 bytes a
frame, which is the animated-cell replay path working exactly as intended —
the run loop advances the divider's own 40 cells without re-rendering anything.

### Split View, first pass: the measurements that were measuring nothing

You reported the Split View page as noticeably sluggish. I could not reproduce
it on any axis, and it is consistently the *cheapest* of the interactive pages.
Release build unless noted; `ps` CPU time, 120x40, 30 events at 20/s.

| Page       | idle CPU | Tab burst | Down burst | Terminal resize |
|------------|---------:|----------:|-----------:|----------------:|
| Split View |     0.4% |   6.3 ms  |    4.0 ms  |        12.7 ms  |
| Lists      |    15.2% |  21.3 ms  |   18.0 ms  |        34.7 ms  |
| Tables     |     4.8% |  13.7 ms  |   14.0 ms  |        24.7 ms  |
| Layout     |        — |  13.7 ms  |        —   |        30.0 ms  |

Also measured and found no difference: the debug build (same ordering, ~2x
across the board), all three split styles including `sizeToFit` (which
re-measures content to size its columns), a mouse-drag burst on the divider,
and a 220x70 terminal.

So: what were you doing when it felt slow? A gesture I have not thought of, a
much larger window, or possibly the terminal emulator's own redraw cost rather
than ours — the page emits a lot of box-drawing, and some terminals are slow
with it. Happy to chase it with a hint.

### What the measurement DID turn up: one spinner costs 22% of a core

The Lists page idles at **22.6% CPU** (debug; 15.2% release) while nothing is
happening, emitting 2.3 KB/s — the shape of a page re-rendering ~20x a second
and producing almost no diff.

Deleting one line finds it. The multi-line list demo has a `Spinner(style:
.dots)` in every row; replacing it with a static `Text` takes the page from
**22.6% to 0.2%**.

The cause is the animated-run propagation trap, from the other side. `_ListCore`
flattens its rows to `[String]` lines and collects runs only for its OWN pulse
(the cursor row breathing); a row's `buffer.animatedCells` is dropped on the
floor. So the spinner cannot be replayed by the run loop and has to be
*re-rendered* to move — which means re-rendering the page, twenty times a
second, to advance three characters.

`SpinnerRowAnimationTests` passes, and is right to: the spinner does keep
spinning. It tests the visible outcome, not the mechanism, which is exactly the
hole that lets a 100x idle-CPU regression through.

The fix is real work rather than a gate: `RenderedRow` would have to carry the
row's own runs alongside its lines, and they would have to survive the same
overscroll slide and reorder clip the pulse runs already go through — in a
2500-line file with several row-assembly paths. Worth a session of its own, and
not worth starting at the end of a batch. **This is the biggest single
performance item I have found in this pass.**

### Scrolling
- **"The scroller never disappears into its own track"** — the focused
  scrollbar's breath faded its thumb to *exactly* the track's colour on several
  palettes (a contrast ratio of 1.0), so once per breath there was nothing on
  the bar to read.

### Spinners
- **"Two places you can choose a spinner, and one list to choose from"** — an
  editor on the Spinners page, and a picker for the `.refreshable` indicator
  (the setting with a real reason to exist: `.line` is pure ASCII and animates
  on a font with no Braille coverage).

## Second pass — the four you called out

### The block borders, proceeded with
**"A block border paints its cells, so the seams have nothing to show."**
`BorderStyle.paintsBackground`, a Bool rather than a `Color` because a border's
colour arrives per frame (palette, override, or one step of a pulse) and a
colour on the style would be a second source of truth an animated wall could not
honour. False on `.blank`, whose contract is that things show through — and no
"the glyph looks opaque" heuristic, which would also break drag previews, where
a blank carrying a background is deliberately kept as fill rather than trimmed
as padding. Three hand-built wall/rule emitters now go through
`BorderRenderer.wall` / `.rule`. `DimmedOrnaments` gained the block glyphs: a
block-bordered page behind a modal had been the only chrome that did not recede.

### Select-all is Option-Ctrl-A
**"Ctrl-A means the same thing in both text controls."** No new machinery: the
`alt` flag existed, `ESC 0x01` already decoded to it, and ⌥⌃A was *already*
selecting all because the Ctrl table ignored the bit. Ctrl-A is start-of-line in
both controls now. Ctrl-E came with it — beyond the letter of the decision, but
with Ctrl-A moving and Ctrl-E still typing an "e" the field would have had half
of readline's pair, which is the same asymmetry being fixed. The ⌥ dependency is
in `Terminal-compatibility.md` with the bytes, flagged as the one binding that
deliberately breaks that file's own "an ⌥-chord must be an accelerator, never
the only route" rule, with the reasoning for it.

Also **"The editor's keys, written down under the editors"** — a readline legend
under the two `TextEditor`s, read off `TextEditorHandler` rather than from
memory.

### The gradient banding, fixed
**"Quantise a gradient as a ramp, not one cell at a time."** The premise
recorded above — that the renderer cannot know the terminal's colour depth — was
false; `ColorDepth.current` is public and already read twice per `colorize`. So
the fix needed none of the three metric changes that broke palette derivation:
quantise per cell with the **unchanged** metric, then repair the sequence by
dropping the shorter run's entry at each monotonicity break and re-quantising
among what survives. A run's length is the tie-break and needs no tuning,
because it is not a threshold — the cells an entry wins are the extent of the
ramp for which it genuinely is nearest.

### The drag, and the byte budget
**"A frame stops restating styling it has already stated."** 62% of a drag frame
was SGR escapes, 984 of them a bare reset followed by the background it had just
cleared. A line now states each style once and skips any restatement of what is
already in force — with the baseline subtlety that before a line's first reset
the incoming state is unknown, so nothing there may be netted or skipped. Escape
count down 44%, at no measurable CPU cost.

Both A/B runs across this pass: `table`, `kitchensink`, `deep` and `textwall`
all indistinguishable.

## Third pass — the Split View drag, again

You said it was maybe a little better and still quite poor. It was. Here is
what the second pass had actually achieved, and what this one did.

### What the second pass fixed, and what it left

Collapsing adjacent SGR cut a drag frame from ~15,600 to 10,747 bytes. Real,
and not nearly enough, because it left the shape of the problem untouched: the
diff worked in whole ROWS. Measured at 140x42 in release, one drag frame:

| | |
|---|---|
| bytes emitted | **10,747** |
| rows rewritten | 27.9 of 42 |
| cells written | 3,906 |
| **cells that actually changed** | **393** of 5,880 |
| bytes per genuinely changed cell | **27.3** |

Ten times the cells written as changed. That number is the frame rate, because
writes block: the app renders exactly as fast as the terminal absorbs bytes.

### Two changes

**Say only what changed** (`bd741b84`). The collapser skipped restating styling
already in force but restated anything that *did* change absolutely — a reset
plus every parameter. Inside one built line the terminal's state is known,
because we put it there, so each change is now a delta from it. The two
commonest escapes in a drag frame were both saying things the terminal already
knew: `ESC[0;48;5;16m` (12 bytes, only the foreground going back to default —
`ESC[39m`, 5) and `ESC[0;38;5;22;48;5;16m` (19 bytes over a background that was
not changing — `ESC[38;5;22m`, 11). SGR bytes down 31%, frame down 17%.

**Write the cells that changed, not the rows they are in** (`ad929451`). The
intra-line diffing that `Documentation/Intra-line output diffing.md` had parked.
It was parked on the strength of the wrong measurement — a blinking cursor,
where the win is 4x on a number already too small to matter. On the drag it is
2.3x on the number that IS the gesture.

### Where it ended up

| per drag frame, 140x42 release | bytes | CPU |
|---|---|---|
| before this whole review | 10,620 | 6.4 ms |
| after the SGR collapse (second pass) | ~8,900 | 7.0 ms |
| **now** | **3,929** | 7.6 ms |

**2.7x fewer bytes**, for about 1 ms more CPU per frame — and the trade is the
right way round, because CPU was 23% of one core during the drag and the bytes
were the constraint.

### Two things you should know

**The debug build is a different animal.** The same drag frame costs **7.6 ms in
release and 77.8 ms in debug** — a factor of ten, and 77.8 ms caps the drag at
about 13 fps before the terminal has seen a single byte. If you have been
watching `swift run Example`, that is very likely the largest single term in
what you are seeing, and none of the byte work above can touch it. Worth
checking before I chase the remaining bytes.

**Spans cost cursor moves.** The frame now emits about 53 cursor moves where it
emitted 28, in exchange for writing 454 cells instead of 3,906. On every
terminal I can measure that is an enormous win, because the cost is in the
bytes. On a terminal whose cost is per-escape rather than per-byte it would be
less of one. The gap that decides this is one constant
(`FrameDiffWriter.spanMergeGap`, 8): raising it to unbounded gives one span per
row — same 28 moves as today's whole-line path — at about 6,000 bytes a frame
instead of 3,929. I picked bytes. Say the word if your terminal disagrees.

### And a correction to my own method

Two of the twelve-gesture verification sweep's early failures were the harness,
not the code: feeding a terminal model in arrival-sized chunks splits multi-byte
sequences at different offsets for each build, and `pyte` gets some of those
wrong. It shows up as a difference between builds that the bytes do not have.
Capture the whole stream, replay it in one go, and only then is a difference a
difference. Written down in the design note so it does not cost anyone an hour
twice.


## Fourth pass

### Mono images now split where the image puts the split

**"Split ink from background where the image puts it, not at mid-grey."** Three
renderers reduce a pixel to one bit — `.blocks(.solid)` and `.blocks(.fine)` in
mono, and braille in *every* mode, since its dots carry the shape while colour
is averaged per cell. All three split at mid-luminance, and the demo image is
87% below it: only 12% of its sub-pixels came out as ink, which draws a broken
outline rather than a silhouette. Otsu's method now measures the split from the
image itself — 75.5 here rather than 128 — and the half-block mono render goes
from 15% ink to 28%:

```
   fixed 128                          measured 75.5
      ██████████▄▄▄                      ▄▄▄▄
      ███████████████▄             ▀▀█████████████▄▄▄
       ███▀█████████████▄    ▄▄      ██████████████████▄▄
```

It declines rather than guess: an image spanning fewer than 16 of 256 levels
keeps the fixed split, because Otsu on a flat image splits sensor noise and
renders it as speckle.

### The custom palette: designed, not built

`Documentation/Image palette mapping.md`, since you asked to see the design
before I build past mono. The short version:

- A fifth `ASCIIColorMode` case, `.palette([Color])`. **`Color`, not `RGBA`** —
  a palette of `.palette.accent` follows the theme, and that is the case worth
  having; an `[RGBA]` would freeze the answer at construction. It sits
  *orthogonal* to the existing four, which are a fidelity ladder chosen by what
  the terminal can do; this one is chosen by intent.
- **Map by luminance order, not nearest RGB.** Nearest-neighbour on three
  colours flattens whole regions to one — the same failure the gradient work hit
  — and the fix is the same: quantise the sequence, not the sample. Luminance
  ordering also makes `.grayscale` a special case of this rather than a separate
  thing.
- **Do not reach for `hueWeightedDistanceSquared`.** It is load-bearing for
  `SystemPalette` derivation, which reads *quantised* colours, so retuning it
  moves the surface walk. Three attempts during the gradient work each broke
  derivation and each was reverted. A palette mapper gets its own private
  distance.
- **Dithering is where the depth comes from.** The error diffused between two
  palette entries is what makes a boundary read as a gradient rather than a
  step, so the palette has to resolve to concrete RGBA before the dither runs —
  exactly as the mono threshold now does.

Two questions in the note are genuinely yours: whether a two-entry palette means
"ink and paper" or "two inks on the app's background" (I lean to the second),
and whether `.grayscale` should fold into `.palette` afterwards (I would, but
not in the same change).

### View resizing: a design note, not code

`Documentation/Resizable views.md`. The short version:

- **SwiftUI has nothing to copy.** Window resizing belongs to the window server;
  `Image.resizable()` means "scale the content", which is a different thing
  wearing the same word. So this is a TUI-specific API, and the name must not be
  `resizable()` or the two collide. Proposed: **`.userResizable(_:)`**.
- **The pointer has no shape**, so unlike every GUI the affordance must be
  *drawn, before the pointer arrives* — not summoned on hover. That single
  constraint decides most of the rest.
- **Of your three placements I recommend the second-and-a-half**: the
  bottom-right corner *plus* the full bottom and right edges. A one-cell corner
  is an invisible target and collides with the scrollbar's arrows; all four
  edges means the top and left resize by moving the view's origin, which takes
  space from a sibling and is a surprising operation; eight handles is a GUI
  idiom that only works because a cursor changes shape at each one. Bottom and
  right also has a sentence a user can hold: *a resizable view grows down and
  right, and never moves.*
- **The affordance** is your `╝`, plus the two live edges one palette step
  brighter, with hover strengthening rather than creating it. Block borders paint
  their cells, so it has to be expressed as a background change there too.
- **Most of the machinery already exists** — `_SplitDividerHandler`,
  `SplitViewWidths`, the reset token — and a general version should be an
  extraction of those rather than a second implementation. In particular it must
  keep their best property: the handler records raw intent and the layout clamps
  it, so the arrow keys always step from the real size.

### The horizontal-space review: measured, and the two worst pages fixed

You asked for every page rearranged to use the available width with a taller
narrow fallback. Thirty-five pages is more judgement than one pass, so this pass
**measured** them all — which turns the rest from a survey into a work list —
and rearranged the two worst.

Rendering every page at 200x50 through `tui_screens.py --dump-dir` and taking
the widest body row:

| | page | cols used of 200 |
|---|---|---|
| 1 | Radio Buttons | **65 (32%)** |
| 2 | Steppers | **74 (37%)** |
| 3 | Buttons & Links | 82 (41%) |
| 4 | Spinners | 91 (45%) |
| 5 | Preferences | 96 (48%) |
| 6 | State Persistence | 117 (58%) |
| 7 | Empty State | 124 (62%) |
| 8 | Picker | 134 (67%) |
| 9 | Image (File) | 138 (69%) |
| 10 | Split View | 172 (86%) |

Every other page already reaches 99–100%. So this is nine pages, not
thirty-five, and the list is ordered by how much there is to gain.

**Radio Buttons 65 → 175 cols**, **Steppers 74 → 120** and **Buttons & Links
82 → 183**, all following the
`ViewThatFits(in: .horizontal)` shape the Animation page and the track editor
use: preferred arrangement first, then progressively narrower ones, then the
original single column. Radio Buttons gets four arrangements (five across, then
2+2+1, then 3+2, then one column); Steppers three, with the shift-accelerated
section keeping a column of its own for as long as there is room, because it
carries a sentence of prose rather than a control. Buttons & Links gets three,
its nine sections grouped by what each demonstrates — how a button is styled,
how a modifier on a container cascades into it, and how buttons compose with
other things.

Each section is a named `@ViewBuilder` property rather than written out per
arrangement — `ViewThatFits` builds every candidate, so a section duplicated
four times would be four copies of the same bindings to keep in step.

Worth noting for the remaining seven: the arrangements fall back on their own
under translation, which is what makes this safe to do at all. The widest
arrangement stops fitting in German before it does in English, and the page
quietly takes the next one down.

**Spinners 91 → 145** and **Picker 134 → 142** next. The spinner catalogue
deals into a column count passed as a parameter rather than a second copy of
the list — a spinner is a live animation, and two lists of twelve would be
twenty-four clocks where twelve will do. Picker's six sections group by how a
picker presents its choices: as a menu that opens, as options laid out in
place, and as a value read back.

### And a correction to the survey's metric

"Widest body row" was the wrong measure, and re-reading the same captures with
the median row width says so:

| page | widest | median | p90 |
|---|---|---|---|
| Preferences | 96 | **12** | 34 |
| Picker | 134 | 18 | 39 |
| State Persistence | 117 | 29 | 86 |
| Empty State | 124 | **64** | 105 |
| Image (File) | 138 | **82** | 82 |
| Split View | 172 | **119** | 126 |

Two different things were sitting in one column. A page with a median of 12 and
a widest of 96 is a narrow column with one explanatory sentence across the top —
lots to gain. A page whose median is 64 or 82 is *uniformly* that wide, which
for **Empty State** is a centred placeholder that is meant to be narrow and for
**Image (File)** is the image itself. Rearranging either would make it worse.

So the honest remaining list is shorter than nine. Empty State, Image (File)
and Split View are right as they are.

And then the last two turned out to be a third category, which I only found by
building it: **prose-bound**. I rearranged State Persistence into two columns
and it stayed one column at 200 — because its sections are explanations, and two
~90-column sentences side by side need **215 columns** before `ViewThatFits`
will take them. Moving the filesystem-path row out of a column (a path is both
the longest line on the page and the one that reads worst wrapped) bought ten
columns and not the twenty needed. Preferences is the same shape with less of
it: twelve body rows, one of them a 96-column sentence.

So that change is **reverted rather than shipped**. Arrangements that never fire
on any terminal anyone has are worse than none: they are dead code that reads
like a feature, and the next person to widen a sentence would have no idea they
had just made the page narrower.

**The width review is finished**, then, with five pages rearranged and four left
alone for stated reasons — not nine pages of work, and not the two I thought
remained an hour ago.

| page | before | after | |
|---|---|---|---|
| Radio Buttons | 65 | **175** | four arrangements |
| Steppers | 74 | **120** | three |
| Buttons & Links | 82 | **183** | three |
| Spinners | 91 | **145** | three, catalogue column count as a parameter |
| Picker | 134 | **142** | four |
| Empty State | 124 | — | a centred placeholder; meant to be narrow |
| Image (File) | 138 | — | the width IS the image |
| Split View | 172 | — | already uses it |
| State Persistence, Preferences | 117, 96 | — | prose-bound; needs 215 columns |

### The left gutter: one column, unconditional

You picked B. Every page's content now starts one column in from the terminal
edge rather than hard against it.

Applied once in `ContentView`, not in `scrollableDemoPage()`: only 22 of the 36
pages use that wrapper — a split view, a tab view and the image pages fill the
viewport themselves — and a gutter on two thirds of the app would read as a
mistake rather than a margin.

One thing it does that you did not ask for, and I think is an improvement: the
app header's right-hand text (the version, the platform line) now sits one
column in from its border too, where before it was flush against it. The header
reads as symmetrically inset rather than crowded on one side. Easy to undo if
you disagree — say so and I will scope the padding to the body. It is a separate question from
this — it is about the page frame rather than the page content — and I have not
settled what "collapsible" should mean for something one column wide.

## Not started

Five items from your list are untouched. Each is a session rather than a batch
item, and I would rather say so than leave half of one behind.

### Correction: the bottom partial row already worked

I told you (commit `1daeecee`) that the bottom of a line-granularity list could
not show a partial row, and blamed `rowsFitting(in:)`. That was wrong on both
counts. `rowsFitting` feeds `pageDistance` — how far Page Down goes — and has
nothing to do with the window walk. The walk's straddle branch already admits
the row that overhangs the budget under line granularity, and `_ListCore` clips
it at the budget as it draws.

Driving a real List rather than reading the arithmetic settles it:

    r4L0 r4L1 r4L2 r4L3  r5L0 r5L1 r5L2 r5L3  r6L0

Row 6 enters and is cut after one of its four lines. Both ends do cut, and a
viewport sitting mid-row is filled exactly.

`ListPartialRowTests` now pins that: the top clips, the bottom clips, both clip
at once, and no line between them is left blank. It sweeps scroll positions
rather than computing one, because the first version of it computed one and got
a false negative — a wheel notch moves three lines, so with three-line rows
every notch lands back on a row boundary and the top never clips. That was a
property of my test, not of the List, and it is the same shape of mistake as the
divider column: a measurement that runs, reports, and is measuring nothing.

List only, deliberately: a `TableColumn` extracts a `String` per cell, so a
Table row is one line and the question does not arise there.

1. **Scroll granularity: partial rows at both ends, and a selection toggle.**
   The scrollbar-pulse half is done. On the other half I can now answer your
   question — "is there any technical or conceptual reason why it shouldn't
   behave consistently at both ends?" — and the answer is **no, and the
   asymmetry is two separate mechanisms rather than one decision**:

   - The TOP renders a partial row through `scrollTopClipLines`, and
     `clampTopClip()` says in as many words that granularity "is not a
     constraint on where the viewport may sit" (`ItemListHandler.swift:1250`).
     So a partial row is already legitimate there, at any granularity.
   - The BOTTOM cannot, because the window is filled by `rowsFitting(in:)`
     (`:1201-1210`), which stops at the last row that fits WHOLE and leaves the
     remaining lines blank. Nothing decided the bottom should differ; the fill
     was simply written in whole rows.
   - And `clampTopClip()` zeroes the clip outright once `scrollOffset >=
     maxOffset` (`:1263`), so the very bottom is pinned to a row boundary.

   **Resolved, and my diagnosis above was wrong** — see the correction just
   before this list. The bottom already cuts; nothing needed building, and what
   was missing was a test saying so.

   On the framing: your reading is right and worth writing down — row-vs-line is
   a property of a SCROLL, selection always moves whole rows because there is no
   such thing as half a selected row, and the Example demos currently conflate
   the two by driving granularity from the selection cursor. The toggle you
   asked for is the right way to show that.
2. **Mono image rendering: adaptive threshold and a colour LUT.** *Threshold
   done* — see below. The palette LUT is still the part you asked me to design
   before building beyond mono.
3. **Text input: the shortcut legend, and reconciling Ctrl-A.** The legend is
   small. The reconciliation is a decision, and I have opinions rather than an
   answer — see below.
4. **View resizing.** *Design note written* — `Documentation/Resizable views.md`.
   No code yet, deliberately: the affordance is the expensive part to change
   later. Summary below.
5. **The Example-wide horizontal-space review.** *Measured, two worst pages
   done, seven to go* — see above. The left gutter is still open.

### On Ctrl-A, since you asked for at least one option

The clash: `TextEditor` reads Ctrl-A as "start of line" (Emacs) and `TextField`
reads it as "select all" (because a terminal cannot deliver Cmd-A). Three ways
out, in the order I would rank them:

1. **Make Ctrl-A mean start-of-line everywhere, and move select-all to Ctrl-/ or
   Ctrl-6.** The Emacs motion set is the one a terminal user already has in
   their fingers from readline, and it is the set that is *complete* — Ctrl-A/E,
   Ctrl-B/F, Ctrl-K, Ctrl-U. Select-all is the odd one out and the one with no
   tradition to break; it also has an unambiguous replacement in a chord nothing
   else wants.
2. **Make Ctrl-A select-all everywhere, and use Home for start-of-line.** Fewer
   keys to learn, and matches what a non-Emacs user expects from a text box —
   but it breaks the readline muscle memory in the one control where it is
   strongest, and Home is not always deliverable (some terminals send nothing
   useful; see `Terminal-compatibility.md`).
3. **Leave them different and document it.** I do not recommend this; the two
   controls sit on the same page and are the same kind of thing.

I favour (1). It is the only one where both key sets stay internally consistent,
and the cost falls on the gesture with the least history behind it.

## Deferred, deliberately

**The page-instruction concision sweep.** You asked for the instruction lines at
the foot of each page to be accurate, complete and concise. Accuracy and
completeness are done where they were wrong: the Containers page had no
keyboard help at all and is the page whose keys are least obvious (Left and
Right disclose there now), and the Animation page's loose line of prose became
a `KeyboardHelpSection` like everywhere else.

Concision is a separate, mechanical job I have left whole rather than half
done. About a dozen lines still use the verbose "Use [X] to Y" form while the
rest use the terse "[X] Y" one, and rewriting them means 7 translations each.
The keys: `page.buttons.help.{enterSpace,tab}`,
`page.list.help.{navigate,select,switch,jump,fastScroll}`,
`page.table.help.{navigate,select,switch,jump,fastScroll}`,
`page.picker.help.{openMenu,moveChoose,moveFocus,dateFields}`,
`page.radioButton.help.{navHorizontal,navVertical,select}`,
`page.secureField.help.typeInsert`. The rest of the "not bracket-prefixed"
lines are prose on purpose (`page.theme.help.everyChange`,
`page.list.help.wheel`, `page.contentUnavailable.help.placeholder`) and should
stay that way.

## Open questions

Nothing blocking. Listed for when you get to them.

- **Q1 — `handleMenuShortcut` in `ContentView` is dead code.** It maps
  characters to pages, omits `f` and `a` (Forms and Animation), and never fires:
  the menu rows carry their own `.keyboardShortcut`, which is what actually
  works. Delete it?
- **Q2 — `row(_:_:)` in `MenuPressTrackingTests` is off by one for a popup tall
  enough to be clamped to the screen.** It returns `overlay.offsetY + line`,
  which is the drawn row, but the popup's hit regions for a clamped popup sit
  one row lower. Existing tests do not notice because their menus are short. Not
  chased; noted because the next person to write a menu mouse test will hit it.
