# Terminal graphics protocols — Sixel, iTerm2, Kitty

**Question:** should TUIkit draw with real pixels where the terminal can, and
if so, with which protocol and how far beyond `Image` should it go?

**Recommendation, up front:** ship **one** protocol — the **Kitty graphics
protocol, through its Unicode placeholders** — for `Image` only, detected by
handshake rather than by a host table, with the existing half-block renderer
kept as the universal fallback. Do not ship Sixel. Do not ship the iTerm2
protocol. The reasoning is below; the short version is that placeholders are
the only mechanism of the three that puts an image **inside the cell grid**,
and everything TUIkit does to a view — measuring it, clipping it, scrolling
it, compositing a modal over it, diffing it against last frame — is defined on
cells.

Everything measured here was measured on 2026-09-02 with
`Tools/TerminalProbes/graphics_probe.py`; the records are under
`Tools/TerminalProbes/data/*-graphics.json`. Claims taken from a protocol's
documentation rather than measured here say so.

---

## 1. The three, compared

| | **Sixel** | **iTerm2 inline images** | **Kitty graphics** |
|---|---|---|---|
| Escape family | DCS (`ESC P … ST`) | OSC 1337 (`ESC ] … BEL`) | APC (`ESC _ G … ST`) |
| Payload | 6-pixel-tall bands, palette-indexed | base64 of a real image file | base64 raw RGB/RGBA, or PNG |
| Alpha | no (palette index only) | via PNG alpha | full RGBA |
| Sized in | pixels | **cells** | **cells** |
| Placed | at the cursor | at the cursor | cursor, or a *virtual* placement in the grid |
| Retained | no — retransmit every time | no | **yes — by id; transmit once, place many** |
| Deleted | by overdrawing | by overdrawing | explicitly, by id or placement |
| Z-order vs text | none | none | **yes, including below text** |
| Chunked | no | no | yes (4 KB chunks) |
| Capability query | **DA1 parameter `4`** | none | **`a=q` handshake** |
| Age / origin | DEC VT240, 1980s | iTerm2, 2015 | Kitty, 2019; now the de-facto one |

Two rows of that table decide the recommendation on their own — *retained* and
*capability query* — and a third, *virtual placement*, decides how it is built.

---

## 2. What each host does — measured

### 2.1 What they advertise

| Host | version | Sixel in DA1 | Kitty `a=q` | Kitty virtual placement |
|---|---|---|---|---|
| Apple Terminal | 455.1 | no (`ESC[?1;2c`) | silent | silent |
| iTerm2 | 3.6.11 | **yes** (`ESC[?64;1;2;4;6;17;18;21;22;52c`) | **`OK`** | *not measured — see §7* |
| Ghostty | 1.3.1 | no (`ESC[?62;22;52c`) | **`OK`** | **`OK`** |
| Warp | v0.2026.08.26… | no (`ESC[?62c`) | **`OK`** | **explicitly refused** |
| tmux | 3.7c | **yes** (`ESC[?1;2;4c`) | silent | silent |

Warp's refusal is worth quoting, because it is a *named* answer rather than a
silence to be interpreted:

```
ESC_Gi=42;InvalidKittyAction(InvalidControlData(UnicodePlaceholderUnsupported))ESC\
```

That is the protocol's own error channel telling us a specific feature is
missing while the protocol as a whole is present. **No other terminal
capability in this project can be interrogated that precisely** — every other
one is a table keyed on an identified host. It is the single strongest
argument for Kitty over the other two, and it is the reason detection here can
be a handshake rather than a guess.

`XTGETTCAP` for the `Su` terminfo capability is **not** a usable Sixel signal:
iTerm2 answers `DCS 0 + r … ST` (not present) while its own DA1 advertises
Sixel, and Ghostty answers `DCS 1 + r 5375 ST` — a success flag with no value —
while supporting no Sixel at all. Use DA1.

### 2.2 What they do when you send one — and the headline finding

Each payload was printed between two brackets on a cleared row and the cursor
asked where it had landed, against the brackets alone. Columns are the delta
from the row's start.

| Host | Sixel (25 B) | iTerm2 OSC 1337 (161 B) | Kitty APC (123 B) |
|---|---|---|---|
| Apple Terminal | **Δcol +21 — PRINTED** | Δ0 — swallowed | **Δrow +1, Δcol +39 — PRINTED** |
| iTerm2 | Δ0 | *(DSR timed out at 1 s — see §7)* | *(same)* |
| Ghostty | Δ0 | Δ0 | Δcol +2 — drew a 2-cell image |
| Warp | Δ0 | Δcol +2 — drew it | Δcol +2 — drew it |
| tmux | **Δrow +1 — drew it** | Δ0 | Δ0 |

> ### Apple Terminal parses OSC and does **not** parse DCS or APC — measured
>
> This is the finding that most changes what is safe to build, and it
> contradicts the natural assumption. All three protocols ride
> string-terminated escape families, so it is tempting to reason that any
> terminal with an escape parser will consume them whole and ignore what it
> does not implement — which is exactly what all four hosts do with OSC 8
> hyperlinks (see `Terminal-compatibility.md`, "OSC 8 hyperlinks").
>
> Apple Terminal does that for **OSC** and nothing else. Given `ESC P` it
> consumes the `P` as though it were a two-byte escape and **prints the rest of
> the payload as text**: 21 visible cells out of a 25-byte Sixel, which is
> exactly `25 − ESC − P − ESC − \`. Given `ESC _` it prints 119 of 123 bytes,
> wrapping the row. A page-sized image would be tens of kilobytes of base64
> sprayed across the screen.
>
> So the safety question has three different answers for three protocols on the
> single most common macOS terminal, and the one that is safe there is the one
> whose coverage is worst. Sixel and Kitty must be gated on positive evidence
> and never sent speculatively. (The same parser weakness is already recorded
> elsewhere in this project: `probe_stamp.py` skips DECRQM on Apple Terminal
> because it prints that query's final byte.)

### 2.3 tmux is the mirror image

tmux advertises Sixel in DA1 and drew the band into its own grid; it answers
nothing for Kitty and swallowed both other payloads. So under tmux, Sixel is
the only one of the three that reaches the screen at all — and then only if the
attached client also has it, which tmux decides from its own `terminal-features`
table. Measured at 3.7c with one server per host, `sixel` is granted to
**iTerm2 alone** of the four (the same table, and the same asynchronous-detection
trap, as the hyperlink measurement in `Terminal-compatibility.md`).

---

## 3. Coverage, which is the whole argument

| Protocol | Native hosts that render it | Detected by |
|---|---|---|
| **Kitty** | Ghostty, iTerm2, Warp — **3 of 4** | handshake, per feature |
| Sixel | iTerm2; tmux, forwarding to iTerm2 | DA1 parameter |
| iTerm2 | iTerm2, Warp | nothing — a host table |

Kitty covers strictly more hosts than the iTerm2 protocol *and* is the only one
with a per-feature handshake. Sixel's only unique host is tmux, and tmux's
Sixel is useful only when the outer client also has it, which today means
iTerm2 — a host Kitty already covers.

Supporting more than one protocol therefore buys **no additional host**. It
buys a second encoder, a second placement model, a second lifetime model, a
second fallback path, and a second set of failure modes — and, on Apple
Terminal, a second way to spray base64 across somebody's screen.

---

## 4. Why placements, and not pixels at the cursor

TUIkit renders into `FrameBuffer`: rows of styled strings, measured in cells.
Everything the framework does downstream is defined on that unit — `clamped`
clips it, `composited(with:at:)` overlays it, `ScrollView` windows it,
`FrameDiffWriter` diffs it cell by cell and rewrites only the runs that differ.
An image drawn at the cursor is none of those things: it is pixels at a screen
position the grid knows nothing about. It does not scroll, it is not clipped by
the container that clips its cells, a modal composited over it does not cover
it, and the diff writer cannot tell whether it is still there.

Kitty's **Unicode placeholders** dissolve that problem rather than working
around it. The image is transmitted once with an id; a *virtual* placement
(`a=p,U=1,i=<id>,c=<cols>,r=<rows>`) declares its size in cells; and it is then
drawn by writing **ordinary cells** containing U+10EEEE, with the image id in
the cell's foreground colour and the row/column of the image encoded in
combining diacritics. The terminal composites the image over exactly those
cells.

An image placed that way is, to every part of TUIkit:

- **C cells wide and R rows tall** — so `strippedLength`, `clamped`, and every
  layout container already handle it;
- **text** — so it survives compositing, padding, alignment and the row diff
  with no new `FrameBuffer` payload, and none of the ~30 container placements in
  `ContainerPayloadAudit` needs to learn anything;
- **scrolled and clipped by whatever scrolls and clips its cells**, because they
  are its cells.

This is the single fact that makes the feature affordable. Without it, image
support means a fourth buffer payload (beside overlays, hit regions and animated
runs), propagation through every container, and a diff writer that reasons about
pixels — and `container-payload-audit` is the record of how expensive one more
payload is to keep correct.

### 4.1 Three concrete hazards in *this* codebase

Derived from what is already measured and shipped here, not from the protocol
spec:

1. **The placeholder is Plane-16 PUA, and this framework compensates that whole
   plane.** `TerminalQuirks.planeSixteenPUA` records that every measured host
   paints a Plane-16 codepoint two cells wide and advances one — it is how SF
   Symbols behave — so the walks emit `ECH` + glyph + `CUF` for them. U+10EEEE
   is not a glyph; the terminal intercepts it and advances one. Left in the
   general rule, every placeholder cell would be erased and CUF'd and the
   placement would shear. The character must be exempted **by codepoint**, and
   the exemption must be tested, because the failure looks like an image drawn
   one cell to the right rather than like a bug.
2. **A placeholder cell is a multi-scalar cluster, so the row declines the span
   diff.** `ANSIRowCells(decomposing:)` bails on any character that is not a
   standalone cluster scalar, and diacritics are exactly that. Rows carrying an
   image will be rewritten whole whenever they change. That is correct and
   affordable — an image's rows rarely change — but it should be a decision with
   the reasoning attached, exactly as the OSC 8 bail-out now is.
3. **The image id lives in the foreground colour**, so the SGR netting must not
   treat it as decoration. `paintsBlankCellsIdentically` deliberately ignores a
   foreground on a blank cell; a placeholder is not blank, so today's rule is
   safe — but it is safe by accident, and a future widening of that
   optimisation would silently drop images.

### 4.2 What else the integration needs

- **Cell pixel geometry** — already solved. `environment.imageCellAspect` is
  plumbed through `_ImageCore`, measured by `cell_aspect_probe.py` from
  `TIOCGWINSZ` and `CSI 14t`/`16t`. Sizing an image to C×R cells needs the same
  numbers.
- **Encoding** — `ImageLoader` already produces `RGBAImage`, which is Kitty's
  `f=32` format verbatim. No re-encode; optionally `o=z` (zlib) to cut the wire
  cost, which is the standard library's `compress` away.
- **Lifetime** — images must be deleted by id when their view goes away, or the
  terminal's image store fills. This is the one genuinely new resource TUIkit
  would own, and it wants the same discipline `LifecycleManager` already applies
  to view tokens.
- **Fallback** — unchanged. Half blocks remain the renderer for every host
  without a placement, which today is Apple Terminal, Warp, tmux and every
  terminal nobody has measured. The graphics path is an enhancement over a
  complete picture, never a prerequisite for one.

---

## 5. Beyond `Image` — what these protocols can and cannot do for the framework

The user's question was whether graphics could solve problems elsewhere: layer
composition, high-fidelity gradients, and so on. One boundary settles most of
it, and it is worth stating once:

> **TUIkit cannot draw text into an image, because it does not have the
> terminal's font.** Everything that would require rasterising the app's own
> text — a blur, a drop shadow under a label, real anti-aliasing, sub-pixel
> placement, an opacity fade of mixed content — is out of reach whatever the
> protocol. The framework composes *cells* and hands them to something else to
> draw.

With that fixed, each idea sorts cleanly:

| Idea | Verdict | Why |
|---|---|---|
| **High-fidelity `Image`** | **the reason to do this** | ~50× the pixels. A 120×40 terminal is 120×80 half-block "pixels" and roughly 840×600 real ones. No palette quantisation, no contrast floor, no cursor-advance compensation. |
| **Charts, sparklines, plots** | **yes, later** | A plot's interior is pure geometry with no text in it; axis labels stay cells. This is the second-best fit after `Image` and needs nothing new beyond a drawing surface. |
| **Gradients / images behind text** | **interesting, conditional** | Kitty places images below text with a negative `z`, so a true-colour gradient could sit behind ordinary styled cells. The condition is real: the text cells must state **no background**, or the background paints over the image. TUIkit paints backgrounds nearly everywhere, so this is a change to how backgrounds are emitted, not a drawing feature. And gradients already render well at truecolor — the gain is smooth diagonals and sub-cell vertical steps, not colour fidelity. |
| **Layer composition / `.opacity`** | **no** | TUIkit blends colours in software because the terminal has no alpha for text. The content being faded is text, and see the boundary above. A protocol that composites images with cells does not help composite cells with cells. |
| **Rounded corners, borders, shadows** | **no, for chrome around text** | Same boundary. Feasible only for ornament that contains no text, which is not what a border is for. |
| **Icons / SF Symbols** | **marginal** | They already render from the font where the font has them, at zero bytes. An image version would work on more hosts at the cost of transmitting bitmaps and matching the font's metrics. |
| **Animation / video** | **defer** | Kitty can drive animation frames itself, which would let a spinner run with no app-side clock at all — attractive against the idle-render work in `Performance-profile-2026-08.md`, and far too narrow a win to lead with. |

---

## 6. Recommendation

**Build, in this order:**

1. **Detection by handshake.** Send Kitty's `a=q` query, then a *virtual
   placement* probe, at startup alongside the existing identity queries — and
   believe only the answers. Do not add a host table for this. The Warp result
   is the argument: a host that answers `OK` to the protocol query and refuses
   the placement query would be recorded as "supports Kitty" by any table
   somebody wrote from a feature list.
2. **`Image` through Unicode placeholders**, behind that detection, with half
   blocks as the fallback. Handle §4.1's three hazards explicitly and test
   each: the PUA exemption by codepoint, the span-diff decline as a stated
   decision, the id-in-foreground as a pinned invariant.

   > **Corrected while building it.** This item originally read "with half
   > blocks as the fallback *and the default*". That was the wrong call, and
   > the reason is the detection in item 1: a capability that is asked for and
   > positively answered cannot be wrong about a host, so "on where detected"
   > costs nothing it does not buy. Off by default would mean a feature nobody
   > finds behind a modifier nobody knows to write. Shipped as
   > `\.terminalGraphics`, defaulting `true`, ANDed with the handshake's
   > answer — the same shape `\.terminalHyperlinks` already had, and the same
   > reasoning.
3. **Image lifetime** — delete by id when a view goes away; one owner, tested
   the way the render caches are.

**Do not build:**

- **Sixel.** One unique host (tmux, useful only into iTerm2, which Kitty already
  covers), no alpha, no retained images, no placements — and it *prints* on
  Apple Terminal. Its one virtue is that DA1 detection is trivial and reliable.
  Reconsider only if Ghostty ships it *and* Kitty placements have not spread,
  which is the opposite of the current direction.
- **The iTerm2 protocol.** It covers iTerm2 and Warp; Kitty covers both, plus
  Ghostty. It has no capability query at all, so support could only ever be a
  host table. Its single advantage is that it is safe on Apple Terminal — which
  matters only if you emit without detecting, and detection is the first item
  above.

**Defer, with the trigger written down:** images behind text (§5) — revisit when
something in the framework genuinely wants a picture *under* type, and expect
the work to be in how backgrounds are emitted rather than in the protocol.

**The through-line:** every one of these decisions is the same one. Prefer the
mechanism that lets an image be a *cell*, because the framework's entire
architecture is defined on cells, and prefer the protocol that will *tell you*
what it supports, because every other terminal capability in this project has
had to be measured host by host and re-measured on every release.

---

## 7. What is not measured, and should be

- **iTerm2's virtual placements.** iTerm2 answers `OK` to the Kitty protocol
  query; whether it supports Unicode placeholders is still not captured. It is
  the single most load-bearing gap here: it decides whether this covers two
  hosts or three. Two attempts, two different walls — `open -a iTerm <file>`
  does nothing (the app is running and answers neither it nor `open -a iTerm`
  alone), and AppleScript reaches iTerm2's standard suite (`get version`
  answers `3.6.11`) but is refused for anything touching its object model:
  `create window with default profile` returns `-1743`, errAEEventNotPermitted,
  which is iTerm2's own authorisation rather than the system's. `placement_probe.py`
  answers it in one run from inside an iTerm2 window.

  Being wrong about iTerm2 costs nothing while it stands: the handshake is
  positive-evidence-only, so an unanswered iTerm2 draws glyphs.
- **iTerm2's cursor behaviour after an image.** Its DSR went unanswered inside
  one second after both image payloads. The probe now waits four (`IMAGE_TIMEOUT`),
  but the number has not been re-taken. A terminal that takes measurable time to
  decode an image is a scheduling fact worth knowing before images go on a render
  path.
- **Whether anything actually appeared.** Every table above is escape-sequence
  evidence. The probe prints a card of one small square per protocol for a human
  to look at, and the `rendered` field of every record still says
  `unmeasured`. Filling it in is the difference between "the terminal consumed
  the bytes" and "the picture is there".
- **Sixel under tmux, end to end.** tmux drew the band into its grid; whether it
  reaches an attached iTerm2 client, and how it survives a pane resize, was not
  followed through — it only matters if Sixel is ever built, which is not the
  recommendation.
- **Placement under a modal.** The claim that placeholder cells are clipped and
  covered like any other cells follows from what they are, and has not been
  demonstrated with a real overlay over a real image.

---

## 8. What shipped, and what it measured

Built on the `kitty-graphics` branch, in the order §6 recommends. The
measurements that decided each piece are in `Terminal-compatibility.md` under
"The image placeholder advances ONE cell"; the raw records are
`Tools/TerminalProbes/data/*-placement.json`.

### 8.1 The hazards, and what each turned out to be

| §4.1 hazard | Verdict | What was done |
|---|---|---|
| Plane-16 PUA compensation catches U+10EEEE | **real, and worse than stated** — the width table claimed 2 cells AND five host advance models claimed an under-advance | Exempted by codepoint through one predicate every Plane-16 test in the module now goes through. Measured: the placeholder advances **one column on all three hosts that answered**, the two that do not implement the protocol included. |
| A placeholder row declines the cell-span diff | **real, and now deliberate** | The placeholder answers `false` to `isStandaloneClusterScalar`, so the decline does not depend on the encoder emitting diacritics. That in turn is why the **run-length elision is not used** despite working and saving a third of a row's bytes: a diffing writer writes runs after a cursor jump, and a cell that means "the one after the last one" is meaningless there. |
| The id in the foreground colour could be netted away | **not real, and still safe** | SGR collapsing merges *adjacent* escapes and nets them by value, so the foreground survives; and the depth downgrade happens at `Color`→ANSI time, not as a pass over emitted strings, so a 256-colour terminal cannot quantise an id. Pinned by a test that reads the id back out of every row. |

### 8.2 One thing the feature found that had nothing to do with it

The Kitty row/column diacritics are combining marks from a dozen scripts, and a
test that asserted "every mark is zero cells wide" failed on **214 of 297**.

`isWidthNeutralExtraScalar` named five blocks — the Latin diacriticals, the
selectors, the symbol marks — and Unicode has 354 ranges of them. Everything
else measured **one cell**: Hebrew points, Arabic vowels, Cyrillic, Devanagari,
Syriac, Thai, Tibetan, Ethiopic, Khmer, and the CJK tone and kana voicing marks
that sit *inside* the East-Asian-Wide ranges and were scored **two**. A line
carrying one measured wider than it painted, so every column after it landed
short — the same defect the bidi controls had, found the same way and fixed in
the same place. This is not an exotic script: it is any Hebrew or Arabic text
with points.

The fix is by Unicode general category (`Mn`/`Me` occupy no column, `Mc` does),
through a generated range table rather than the property itself — see §8.3.

### 8.3 The cost

Asking `Unicode.Scalar.Properties.generalCategory` on the width path is a
second standard-library lookup for every non-ASCII scalar the earlier fast paths
do not take, which in a terminal UI is every arrow, bullet, ellipsis, braille
cell and spinner frame. Measured with `Tools/Profiling/ab_bench.py`, 15 paired
reps, order randomised:

    scenario        old µs   new µs   change      95% CI      verdict
    table            518.5    526.6    +2.0%  +0.2% +2.9%     slower
    dashboard        171.2    174.9    +2.8%  +1.6% +3.4%     slower
    customlayout     402.9    411.7    +2.6%  +1.4% +3.3%     slower
    kitchensink      634.8    644.3    +1.0%  +0.3% +2.1%     slower

Four scenarios outside the interval is a real regression, so the property was
replaced by a binary search over `combiningMarkRanges` — **generated from that
same property** by `Tools/GenerateCombiningMarks/generate.swift`, with a test
that re-derives it over all 1,114,112 codepoints and fails if the two disagree.
The table is an optimisation, so it is checked against the thing it optimises
rather than trusted; a toolchain shipping a newer Unicode is caught rather than
silently mis-measuring whatever script gained a mark.

### 8.4 What it looks like, and the one thing that surprises

**The picture is made of cells, and at small sizes you can see it.** A virtual
placement declares its size in `c=` columns by `r=` rows, so an image always
occupies a whole number of them — which is exactly the property §4 is about.
Shrinking one far enough snaps it to 2 cells, then 1, and stops there: one cell
is the floor, because there is no half a placement. Between those steps the
cell box's proportions can differ visibly from the image's, a cell being
roughly twice as tall as it is wide.

The glyph renderer quantises identically and always has. The difference is that
a photograph makes it obvious and a field of `▄` does not.

### 8.5 The bug that shipped, and the test that would have caught it

The first version used **U+10EFFF**. The placeholder is **U+10EEEE**. Every
test passed, because every test compared the encoder against the encoder's own
constant; the DSR advance measurements were all still valid, because any
unassigned Plane-16 codepoint advances one column; and the four hosts agreed
with each other, because they agreed about a character none of them had ever
heard of. What a terminal showed was a grid of missing-glyph boxes, in the
near-black of the image id.

`KittyGraphicsDiacriticTests.matchesTheSpecificationsExample` is the test that
was missing: it transcribes kitty's own two-line `printf` for a 2x2 placeholder
of image id 42 and compares the encoder's cells against it. **A constant taken
from a specification has to be checked against that specification, spelled
out** — otherwise the tests only prove the code agrees with itself.

The same round found two more, both of which the codepoint bug was hiding:

- **`RGBAImage.scaledBilinear` was dropping the alpha channel.** It
  interpolated red, green and blue and then built its pixel with
  `RGBA(r:g:b:)`, whose alpha defaults to opaque. Nothing noticed while its
  only consumers read luminance to pick a glyph; a renderer that hands the
  pixels to the terminal notices at once, because the terminal is what
  composites them.
- **A terminal reply was being read as typing.** `ESC _ G i=7;OK ESC \`
  reached the input parser as Alt+underscore followed by the keystrokes
  `G i = 7 ; O K`, and `=` is the zoom-in shortcut on the image pages — so an
  acknowledgement moved a control nobody touched. The parser now swallows
  every string-terminated family (OSC, DCS, APC, PM, SOS); a reply is output
  the terminal volunteered, and this parser reads the keyboard.

### 8.6 What an image costs

| | Ghostty 1.3.1, 16×34-pixel cells |
|---|---|
| A full-screen image, 49×17 cells | 1.8 MB of base64, transmitted and acknowledged in **43 ms** |
| A 12×4-cell image | 104 KB, **2 ms** |
| One placeholder row, 12 cells | 111 bytes (67 elided, unused — §8.1) |

One-time per image and per size, not per frame: the image is *retained* by the
terminal under an id, and `TerminalImageStore` re-transmits only when the
picture or the cell box changes. **Never larger than the source**: the terminal
fits the image to the placement rectangle, so upscaling before transmission
buys nothing — and at zoom 2 on a 135x48 grid of Retina cells the unclamped
size is 56 MB of RGBA resampled up from a 1101x1080 photograph, which is what
"super slow to load" turned out to mean. An opaque picture is sent as `f=24`,
three bytes a pixel instead of four. It also deletes by id when the view goes away,
which is the one genuinely new resource TUIkit now owns — nothing in the
terminal will free it otherwise.

---

## 9. Reproducing all of it

```sh
cd Tools/TerminalProbes
PROBE_OUT=/tmp/graphics.json  python3 graphics_probe.py
PROBE_OUT=/tmp/placement.json python3 placement_probe.py
```

Run both inside each terminal you have. The first records what the host
advertises and what its cursor does with each of the three payloads; the second
asks the question this design rests on — whether a placed image behaves like
cells — and measures the advance, the elision, both id encodings, delete-by-id,
and what a full-screen transmit costs. Each prints the card that asks the
question no escape sequence can. Records belong in
`Tools/TerminalProbes/data/<terminal>-<version>-{graphics,placement}.json`.
