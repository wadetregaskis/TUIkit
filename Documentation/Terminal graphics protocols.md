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

| Host | version | Sixel in DA1 | Kitty `a=q` | Kitty virtual placement | Draws it? |
|---|---|---|---|---|---|
| Apple Terminal | 455.1 | no (`ESC[?1;2c`) | silent | silent | no — prints the APC |
| iTerm2 | 3.6.11 | **yes** (`ESC[?64;1;2;4;6;17;18;21;22;52c`) | **`OK`** | **`OK`** | **yes**, once the third mark is sent — §2.2 |
| Ghostty | 1.3.1 | no (`ESC[?62;22;52c`) | **`OK`** | **`OK`** | **yes** |
| Warp | v0.2026.08.26… | no (`ESC[?62c`) | **`OK`** | **explicitly refused** | no |
| tmux | 3.7c | **yes** (`ESC[?1;2;4c`) | silent | silent | no |

The last column is new, and it is the one that matters. Three of the five
answer *something* to the protocol query and **two of them draw a picture**
— Ghostty outright, iTerm2 once the third mark is sent (§2.2).

### 2.2 iTerm2 says yes to everything and drew nothing — RESOLVED 2026-09-03: it wants the optional third mark

`placement_probe.py`, iTerm2 3.6.11:

```
Kitty answered      True
virtual placement   True
TRANSMIT_SMALL      OK        PLACE_SMALL   <ESC>_Gi=31;OK<ESC>\
TRANSMIT_LARGE      OK        PLACE_LARGE   <ESC>_Gi=48879;OK<ESC>\
PLACE_AFTER_DELETE  <ESC>_Gi=31;ENOENT:Put command refers to non-existent image with id: 31<ESC>\
```

…and no picture. **It is not lying.** The `ENOENT` after a delete proves
iTerm2 really is tracking images by id and really is processing placement
commands; it accepts every one of them and then never composites the pixels
into the cells. The handshake asks *"will you accept a virtual placement?"*
and gets a truthful yes. The question TUIkit needs answered is *"will you
DRAW it?"*, and nothing in the protocol asks that.

**The placeholder cells come back BLANK**, which decides how bad this is.
Apple Terminal and Warp both *print* the U+10EEEE glyphs, so a reader sees
that something was attempted. iTerm2 consumes the placeholder codepoint and
stops: the cells are spent, nothing is drawn in them, and because the
framework believed the handshake the glyph renderer was never reached.

**This is not "iTerm2 cannot do graphics", and must not be fixed by deciding
that it cannot.** iTerm2 is believed to have worked, and the shape of the
evidence says something specific changed rather than something being absent.
Two things differ between the exchange iTerm2 acknowledges and the ones it
ignores, and they travel together in everything measured so far — which is
why neither is ruled out:

| | pixel format | chunking |
|---|---|---|
| the startup handshake — acknowledged | `f=32` (one RGBA pixel) | one escape, **no `m` key at all** |
| `placement_probe.py`'s card — blank | `f=24` | `m=1` … `m=0` |
| a real `Image` — blank | `f=24` (measured on the wire) | `m=1` … `m=0` |

`f=24` is the suspicious one on timing: TUIkit sent `f=32` for everything
until `2eb6c256`, which added three-bytes-a-pixel for opaque photographs
hours after graphics shipped in `eb829a29` on the same day. An opaque
photograph is exactly what the Example draws. But chunking is an equally good
candidate on the evidence, since the only single-escape transmission anybody
has made is one pixel wide.

`Tools/TerminalProbes/pixel_format_probe.py` separates them: the same ramp
transmitted four ways — `{f=24, f=32}` × `{single escape, chunked}` — each
virtually placed.

**CAUSE FOUND AND FIXED, measured 2026-09-03.** It was not iTerm2's absence
of a feature; it was one optional combining mark.

`pixel_format_probe.py` first: five cases in both hosts, four virtual
placements (`{f=24, f=32}` × `{single escape, chunked}`) and one direct.

| | A `f=24` 1 cell | B `f=32` 1 cell | C `f=24` chunked | D `f=32` chunked | E — DIRECT |
|---|---|---|---|---|---|
| Ghostty | draws | draws | draws | draws | draws |
| iTerm2 | blank | blank | blank | blank | **draws** |

So the pixels, the transmission, the chunking and the format were all fine —
iTerm2 draws the identical image without a placeholder — and `f=24` was
innocent despite the timing that made it look guilty. That much said only
"virtual placements do not work", and the conclusion drawn from it — that
iTerm2 does not implement Unicode placeholders — was the first explanation
that fitted rather than the measured one.

`placeholder_spelling_probe.py` measured it properly: one image, one
placement, four spellings of the cells that summon it.

| | two marks | three marks |
|---|---|---|
| 256-colour foreground | blank | **draws** |
| 24-bit foreground | blank | **draws** |

**The third mark decides it, and the foreground spelling is irrelevant.** A
placeholder cell carries the row, the column, and the image id's most
significant byte. For any id below 2^24 that byte is zero, and the spec says
the mark may be omitted — kitty's own documentation example omits it, and
kitty and Ghostty read the two spellings identically. **iTerm2 does not**: it
requires the mark, and without it looks up an image nobody transmitted, then
acknowledges every command and paints an empty rectangle. Which is why the
handshake could not catch it — every answer was true.

TUIkit now emits the mark. `KittyGraphics.maximumImageID` caps ids at 24 bits
precisely so it is always the mark for zero, so it is a constant two bytes per
cell and nothing else changes: kitty and Ghostty compute `(0 << 24) | fg`
either way. **iTerm2 is a fully supported graphics host**, on the pipeline that
already existed, and the veto that briefly excluded it is gone.

**Worth filing against iTerm2**, since the spec is on the other side: an
omitted third diacritic must mean a high byte of zero, not an absent id.

A second iTerm2 defect fell out of the first probe and stands on its own: a
CHUNKED transmission is acknowledged `i=0` instead of the image's id, where a
single-escape one reports it correctly. The image is stored under the right id
— every placement that follows succeeds — so it is a reply defect, and it
costs TUIkit nothing because the render path sends `q=2` and reads no replies.
It would break any client matching acknowledgements to requests by id.

Two notes on the probes, because both cost a round trip. The first version of
`pixel_format_probe.py` sent `q=2` and read nothing, so it could not tell a
refusal from an acceptance that drew nothing — the exact distinction it
existed to make. And **the control host is not optional**: four blanks with no
Ghostty run indicts the probe, not the terminal.

### 2.3 What they do when you send one — and the headline finding

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

### 2.4 tmux is the mirror image

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
| **Kitty** | Ghostty, iTerm2 — **2 of 4**; Warp answers the handshake and refuses the placeholder by name (§2.1) | handshake, per feature |
| Sixel | iTerm2; tmux, forwarding to iTerm2 | DA1 parameter |
| iTerm2 | iTerm2, Warp | nothing — a host table |

Kitty covers as many hosts as the iTerm2 protocol — Ghostty where the other
has Warp — *and* is the only one with a per-feature handshake. Sixel's only unique host is tmux, and tmux's
Sixel is useful only when the outer client also has it, which today means
iTerm2 — a host Kitty already covers.

Supporting a second protocol therefore buys **at most one more host** — Warp,
through the iTerm2 protocol, and only because it refuses the placeholder. It
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
  `TIOCGWINSZ`, or `CSI 14t` over `CSI 18t` (pixels over cells — what `cell_aspect_probe.py` asks). Sizing an image to C×R cells needs the same
  numbers.
- **Encoding** — `ImageLoader` already produces `RGBAImage`, which is Kitty's
  `f=32` format verbatim. No re-encode; optionally `o=z` (zlib) to cut the wire
  cost, which is the standard library's `compress` away.
  **Superseded 2026-09-02:** neither `o=z` nor `f=100` is being adopted, and
  the aside above understates `o=z` — it needs a deflate encoder this package
  will not carry. The investigation, the measured crossover for passing PNG
  bytes through untouched, and what would reopen it are in
  `Documentation/Compressed image transfer.md`.
  **Revised 2026-09-04:** `o=z` IS adopted, through the host's own `libz`
  borrowed at runtime (`SystemZlib`) and gated on a second handshake
  question; `f=100` is not. See §10 and the top of that document.
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

- **iTerm2's virtual placements — measured 2026-09-03, §2.2.** They draw, once
  every cell carries the third (image-id) mark; the two earlier walls — `open
  -a iTerm <file>` doing nothing, AppleScript refused at the object model with
  `-1743` — were got round by running the probes from inside an iTerm2 window.
  What is still not captured for iTerm2 is the cursor advance over a
  placeholder row: the probe's report was never quoted, so
  `Terminal-compatibility.md`'s advance table omits the host.
- **iTerm2's cursor behaviour after an image.** Its DSR went unanswered inside
  one second after both image payloads. The probe now waits four (`IMAGE_TIMEOUT`),
  but the number has not been re-taken. A terminal that takes measurable time to
  decode an image is a scheduling fact worth knowing before images go on a render
  path.
- **Whether anything actually appeared.** Every table above is escape-sequence
  evidence. The probe prints a card of one small square per protocol for a human
  to look at, and the `rendered` field of each record is filled in by hand:
  Ghostty's says a person confirmed the picture, three say why none can appear
  (Apple Terminal and tmux have no APC parser; Warp refuses by name), and four
  still read `unmeasured`. Filling those in is the difference between "the
  terminal consumed the bytes" and "the picture is there".
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
replaced by a binary search over `combiningMarkRanges` — generated from the
**Unicode Character Database** by `Tools/GenerateCombiningMarks/generate.swift`,
with a test that walks all 1,114,112 codepoints against the runtime's own
property. The table is an optimisation, so it is checked against the thing it
optimises rather than trusted — but not for equality: the runtime's Unicode
lags the published data (macOS 15 answers Unicode 16 where macOS 26 answers
17, under one Xcode), so the table follows the newest release and the test
holds it to the one relation that survives a version gap. Every mark the
runtime knows must be in the table, and anything the table adds must be a
codepoint the runtime has not assigned at all. A toolchain shipping a newer
Unicode than the table is caught rather than silently mis-measuring whatever
script gained a mark; a table newer than the toolchain is what it should be.

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

### 8.4a Which settings still mean something

`Image`'s rendering controls split cleanly in two, and the split is not a
compromise — it is what the two halves always were.

| Setting | Real pixels | Why |
|---|---|---|
| `.imageColorMode` | **applies** | a quantisation of colour, and pixels have colour |
| `.imageToneCurve` | **applies** | says what a TONE becomes; nothing about characters |
| `.imageEdgeContrast` | **applies** | an unsharp mask on the picture itself |
| `.imageDithering` | **applies** | diffuses the error of the quantisation above it |
| `.imageCharacterSet` | inert | there is no character to choose |
| `.imageShapeAware` | inert | chooses a character by its ink distribution |
| `.imageEdgeThreshold` | inert | draws directional line *glyphs* at edges |
| `.imageSupersampling` | inert | how many pixels feed one glyph's sample |

`ASCIIConverter.recoloured(_:width:height:)` is the applying half, and both
renderers go through it — so the two drawings of one picture agree about what
the picture is, rather than agreeing by coincidence. Two deliberate
differences from the glyph path:

- **The colour depth cap does not apply.** `ColorDepth` exists because SGR
  cannot express more than the terminal has; a transmitted image is not SGR, so
  a 256-colour terminal that draws images draws them in full colour. Asking for
  `.ansi256` still gets 256 — it is a look, and looks are honoured.
- **Local contrast is measured in pixels, not cells.** The glyph path uses a
  radius of one cell because a cell is its resolution and a finer lift would
  average straight back out before a character was chosen. Here the pixels
  survive.

The Example greys the inert half rather than hiding it: their absence would be
a puzzle, and their presence, greyed, is the answer. They are deliberately not
*snapped* to a default the way a genuinely dependent knob is — a charset while
pixels are being drawn is not a lie about the screen, it is simply unused, and
discarding it would lose the user's choice every time they compared the two
renderings.

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
| One placeholder row, 12 cells | 139 bytes for id 42, of which 24 are the id's high-byte mark — §2.2. Pinned by `KittyGraphicsDiacriticTests.rowByteCost`. |

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

---

## 10. Gradients as pixels — built 2026-09-04

§5 filed "gradients behind text" under *interesting, conditional*, and the
condition is still real: a placeholder cell IS the image, and holds no
character, so a ramp under type stays cells. What §5 did not consider is how
often a ramp has nothing in front of it — a `LinearGradient` used as a view,
a `.background` on a spacer, the fill of a progress bar or slider whose style
is a solid block, the indeterminate `.gradient` sweep. Those cells are colour
and nothing else, and colour is what a picture is.

**What ships.** Where the terminal answered the handshake and
`.gradientGraphics` (default `true`, ANDed with `.terminalGraphics`) has not
turned it off, those four are drawn as pictures through the same
`TerminalImageStore` and the same placeholder cells as `Image`:

| Where | Cells | Picture |
|---|---|---|
| `BackgroundModifier` over a BLANK buffer (a gradient view, `.background` on a spacer) | one colour per cell | `GradientRaster` — one per pixel, any geometry, the `.gradientExtent(.subtree)` window honoured |
| `TrackRenderer` for a `TrackConfiguration.isColourField` style (`.block`, `.blockFine`, a custom `█`-on-`.background`) | full cells + an eighths ramp | `TrackRaster` — the boundary on a PIXEL, the fill gradient sampled per pixel |
| The indeterminate `.gradient` motion over a `█` fill | 4 samples a cell, re-coloured every frame | `IndeterminateRaster` — a picture per frame, transmitted once; a frame is a row of unchanged cells naming a different id |
| everything with a glyph in it — shade, braille, dot, knob, text over a ramp | unchanged | — |

**Three facts about the protocol decided the shape**, and two of them are
the opposite of what one would guess:

1. **A virtual placement never stretches.** The terminal fits the picture to
   the cell box with its aspect preserved and centres it (`Compressed image
   transfer.md` §1.1, from kitty's and Ghostty's sources). So the obvious
   optimisation — send a horizontal ramp one pixel tall and let the terminal
   stretch it — draws a hairline across the middle of the row. The picture
   must carry the box's proportions, and the smallest one that does is the
   box's pixel size over a common factor of its width and height.
   `GradientRaster.resolution` picks the largest factor that keeps eight
   pixels a cell in each direction; at a 16×34 cell that is 2, so a 40×1 box
   is a 320×17 picture. The rows of a horizontal ramp are then identical,
   which is what compression is for:

   | picture | raw | deflated (zlib 6) | zlib 1 |
   |---|---|---|---|
   | 320×17 ramp | 16,320 B | **1,093 B** | 1,141 B |
   | 640×34 | 65,280 B | **1,439 B** | 1,914 B |
   | 1280×68 | 261,120 B | **2,726 B** | 8,631 B |

   (python zlib on a synthetic three-channel ramp; the framework's numbers
   come from whichever `libz` it borrows, and every zlib inflates them
   identically.) So `o=z` is what makes the "one-pixel strip" affordable
   after all — not by sending one row, but by sending seventeen rows that
   cost one. This is why `SystemZlib` exists (`Compressed image transfer.md`).
2. **A cell names an image, not a placement.** The protocol can crop a
   placement to a source rectangle (`x=,y=,w=,h=`), which would let one
   picture of the moving ramp serve every frame by sliding the window — the
   design first sketched for the indeterminate bar. But a placeholder cell
   addresses its image by id in the foreground colour, and choosing between
   several placements of one image needs a placement id in the *underline*
   colour, which no host has been measured to honour, and re-issuing one
   placement per frame needs the terminal to repaint unchanged cells when
   their placement changes, which no host has been measured to do either.
   A picture per frame needs nothing beyond what every drawing host has been
   measured to do: transmit by id, name by id. Forty-eight frames of a
   forty-cell bar are forty-eight 320×17 pictures — about a kilobyte each
   deflated, once — and thereafter a frame is one row of cells whose only
   difference from the last frame is the id in its foreground. The cells'
   own renderer rewrites forty SGR runs a frame; this rewrites forty
   placeholder cells. Neither sends a pixel.
3. **A boundary is a pixel now.** `.blockFine` had eight sub-cell steps from
   the eighths ramp and `.block` had one; the picture has sixteen at a
   16-pixel cell and the arithmetic is the same rounding the cells used, so
   50% of an even width is exactly half in both. The picture changes with the
   value — every distinct boundary pixel is a new transmission, a slider
   being dragged sends one a frame — which is a row of pixels deflated to
   about a kilobyte against the SGR-per-cell row it replaces, on an id the
   store reuses.

**One picture, many views.** `TerminalImageStore` now keys images by content
(a signature and a cell box that compare equal) with a holder set per image,
so a column of identical bars, or a list of one icon, transmits once and
frees when the last holder goes. The signature is type-erased
(`AnyImageSignature`) so a picture's, a ramp's, a track's and a frame's
signatures each stay a typed struct of the fields that decide them.

**Lifetime** is `Image`'s: `RenderContext.gradientGraphics(token:frames:)`
records the owner as appeared and registers a disappear that releases every
frame's picture, and declares a render side effect so the memo never serves
a cached row naming an image that has been freed.

**Measured through a PTY, 2026-09-04** — `Tools/Smoke/raw_probe.py` on the
Example with `TUIKIT_GRAPHICS=1 TUIKIT_GRAPHICS_COMPRESSION=1` (so the
handshake is skipped and the answer forced; the PTY reports no pixel size,
so the cell is the 8×16 default), 120×40, 2.6 s of capture per page:

| page | transmits | `o=z` | placements | deletes | placeholder cells | pictures |
|---|---|---|---|---|---|---|
| Colors (six gradient views) | 10 | 10 | 10 | 0 | 2,538 | 752×16, 1.2–2.6 KB each deflated (36 KB raw) |
| ProgressView (block tracks, the 72-frame sweep, gauges, demo bars advancing) | 169 | 169 | 169 | 20 | 10,978 | 192–464×16; a flat track deflates to **48 bytes**, a gradient one to ~1 KB |

The deletes are the demo bars' previous pictures going as their value
advanced, on ids the store reused; the sweep's 72 frames are among the
transmits, once. Everything that reached the wire was deflated, and no
picture was sent twice.

**Unmeasured, and said so.** No host has yet been run against
`Tools/TerminalProbes/graphics_compression_probe.py`, so whether iTerm2 and
Ghostty *acknowledge* `o=z` and whether they *draw* a deflated picture are
both open, and `Terminal-compatibility.md` carries the empty table. Until a
row is filled in, the framework acts on the host's own answer at startup —
which is what the handshake is for — and `TUIKIT_GRAPHICS_COMPRESSION=0` is
the switch for a host that says yes and draws nothing. The gradient pictures
themselves rest on mechanisms every drawing host HAS been measured to do
(§8), so a host that draws `Image` draws them.

