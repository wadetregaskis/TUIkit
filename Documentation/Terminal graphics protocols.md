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
drawn by writing **ordinary cells** containing U+10EFFF, with the image id in
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
   Symbols behave — so the walks emit `ECH` + glyph + `CUF` for them. U+10EFFF
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
   blocks as the fallback and the default. Handle §4.1's three hazards
   explicitly and test each: the PUA exemption by codepoint, the span-diff
   decline as a stated decision, the id-in-foreground as a pinned invariant.
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
  query; whether it supports Unicode placeholders was not captured, because the
  app stopped accepting new windows partway through the session. It is the
  single most load-bearing gap here: it decides whether the recommendation
  covers two hosts or three. `graphics_probe.py` answers it in one run.
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

## 8. Reproducing all of it

```sh
cd Tools/TerminalProbes
PROBE_OUT=/tmp/graphics.json python3 graphics_probe.py
```

Run it inside each terminal you have. It records what the host advertises, what
its cursor does with each of the three payloads, and prints the card that asks
the question no escape sequence can. Records belong in
`Tools/TerminalProbes/data/<terminal>-<version>-graphics.json`.
