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

### 3.1 The four hosts this project has measured

| Protocol | Native hosts that render it | Detected by |
|---|---|---|
| **Kitty** | Ghostty, iTerm2 — **2 of 4**; Warp answers the handshake and refuses the placeholder by name (§2.1) | handshake, per feature |
| Sixel | iTerm2; tmux, forwarding to iTerm2 | DA1 parameter |
| iTerm2 | iTerm2, Warp | nothing — a host table |

Within those four, Kitty covers as many hosts as the iTerm2 protocol — Ghostty
where the other has Warp — *and* is the only one with a per-feature handshake.
Sixel's only unique host is tmux, and tmux's Sixel is useful only when the outer
client also has it, which today means iTerm2, a host Kitty already covers.

**A second protocol therefore buys at most one more of these four** — Warp,
through the iTerm2 protocol, and only because it refuses the placeholder. It
buys a second encoder, a second placement model, a second lifetime model, a
second fallback path, and a second set of failure modes — and, on Apple
Terminal, a second way to spray base64 across somebody's screen.

That sentence used to end this section without the words "of these four", which
made a claim about four terminals read as a claim about the ecosystem. §3.2 is
the ecosystem, and it does not say the same thing.

### 3.2 The ecosystem — surveyed 2026-09-05

Not measured here. Every row rests on the project's own documentation,
changelog, issue tracker or source, read on 2026-09-05; where a row rests on
something weaker it is marked ⚑ and the weakness is named in §3.3. **Y** yes,
**N** no, **F** only behind a build flag, patch or non-default setting, **P**
partial, **?** unknown.

| Terminal | Sixel | iTerm2 `File=` | Kitty APC | U+10EEEE | Evidence |
|---|---|---|---|---|---|
| xterm | **F** | N | N | N | compiled in by default since patch #359 (2020-08-17), and gated shut at runtime — see §3.3. The changelog also says it *ignores* APC |
| Apple Terminal ⚑ | N | N | N | N | absence of evidence only — see §3.3 |
| iTerm2 | **Y** | **Y** | **Y** | **Y** | `iTermImage+Sixel.m`; its own docs; commit 4fe5b21 (2024-08-21) adds `createUnicodePlaceholder` and `0x10EEEE` |
| kitty | **N** | N | **Y** | **Y** | zero "sixel" hits in the whole changelog; placeholders `versionadded 0.28.0` (2023-04-15) |
| Ghostty | **N** | **N** | **Y** | **Y** | `osc/parsers/iterm2.zig` lists `File=` in the *unimplemented* branch; `kitty_virtual_placeholder: u21 = 0x10EEEE` |
| WezTerm | **Y** | **Y** | **Y** | **N** | kitty images default-on since 20210814, animation absent; placeholders are PR #7924, still open |
| foot | **Y** | **N** | **N** | N | README (1.2.0+); the kitty/iTerm2 issue #481 has been open since 2021-05-06 |
| Contour ⚑ | **Y** | **Y** | **Y** | **N** | master's source has all three parsers; no `10EEEE` anywhere in `src` |
| mintty | **Y** | **Y** | N | N | iTerm2 images in 3.1.0 (2019-11-23); kitty appears only for underline colours |
| mlterm | **Y** | **Y** | N | N | sixel unconditional in `configure.in`; `SUPPORT_ITERM2_OSC1337` default-on since 2016-02-28; no kitty in 24k lines of ChangeLog |
| Alacritty | N | N | N | N | none of the three anywhere; sixel rejected by the maintainers |
| VTE (gnome-terminal, Tilix, Terminator, Ptyxis, Xfce, guake) | **F** | N | N | N | `meson_options.txt`: `option('sixel', value:false)` — a build option, off by default |
| Black Box | **F** | N | N | N | needs a sixel-enabled VTE; on in the Flatpak builds only |
| Konsole | **Y** | **Y** | **Y** | **N** | `Vt102Emulation.cpp` has all three; a full-tree grep for `10EEEE` returns nothing (26.08.0) |
| Windows Terminal | **Y** | **N** | N | N | `SixelParser.cpp`, shipped in 1.22; `DoITerm2Action` handles marks only |
| ConEmu | N | N | N | N | issue #807 open since 2016; has its own non-standard image sequences |
| Rio | **Y** | **Y** | **Y** | **Y** | `place_virtual_graphic` (`a=p,U=1`) with tests, plus sixel and `File=` (v0.5.27) |
| Warp ⚑ | **N** | **Y** | **Y** | **N** | closed source; kitty images in the 2025-03-26 changelog; placeholders are issue #6210, open |
| Hyper ⚑ | **F** | **F** | N | N | pins `xterm-addon-image`, loaded only when `imageSupport` is set |
| Terminology | **N** | N | N | N | its XTSMGRAPHICS handler is a `DBG(… TODO)` stub; uses its own OSC media protocol |
| DomTerm | **Y** | **N** | N | N | `sixel-decode.js`; `case 1337:` is an empty `break` |
| Yaft | **Y** | N | N | N | README: "sixel (experimental)" |
| Zellij | **Y** | N | **Y** | **N** | sixel 0.31.0; kitty graphics 0.45.0 (2026-08-20); no `10EEEE` in the tree |
| tmux | **F** | N | N | N | `--enable-sixel`, off by default; no kitty of its own — placeholders pass through |
| GNU screen | N | N | N | N | nothing in the ChangeLog |
| MobaXterm | N | N | N | N | nothing through 26.4 (2026-06-11) |
| PuTTY | N | N | N | N | nothing in `changes.html` |
| SecureCRT | N | N | N | N | nothing through 9.7.3 (2026-07-01) |
| Tabby ⚑ | **Y** | **Y** | **N** | N | pins `@xterm/addon-image` at a version predating its kitty support; default state unverified |
| Wave Terminal ⚑ | N | N | N | N | inferred from a missing dependency; its image features are the file previewer |
| xterm.js + `addon-image` | **Y** | **Y** | **P** | **N** | 0.10.0-beta.301 says "partially Kitty"; placeholders are issue #5711, open. §"xterm.js" of `Terminal-compatibility.md` records what it did here |
| VS Code terminal | **F** | **F** | N | N | `terminal.integrated.enableImages`, **off by default** |
| st + patch | **F** | N | **F** | **F** | the st-graphics patch ships placeholders, and builds classic placements on top of them; sixel is a different patch |
| Eat (Emacs) ⚑ | **Y** | N | N | N | one README phrase |
| Zed | N | N | N | N | issue #20860 closed *not planned* (2024-11-19) |
| JetBrains terminals | N | N | N | N | IJPL-196803 unresolved |
| wayst ⚑ | **Y** | N | **Y** | **?** | one README line; placeholders not mentioned |
| AbsoluteTelnet, Mobile SSH ⚑ | ? | ? | **Y** | **?** | listed only by kitty's own documentation |

**The counts, and the one that matters:**

| | |
|---|---|
| Sixel or iTerm2 images and **no** Kitty at all | **14** — 7 of them on by default, 6 behind a flag, patch or terminal-ID setting, 1 unverified |
| Kitty APC graphics | **14** — 12 read from source or project docs, 2 resting only on kitty's list |
| …of which **Unicode placeholders**, which is all TUIkit emits | **5** — kitty, iTerm2, Ghostty, Rio, patched st |
| …of which explicitly **not** placeholders | **6** — WezTerm, Contour, Konsole, Warp, Zellij, xterm.js |
| …unknown | 3 — wayst, AbsoluteTelnet, Mobile SSH |
| Placeholder hosts that *also* speak Sixel or iTerm2 | 2 — iTerm2 and Rio |

So the ecosystem does not say what §3.1 says. **TUIkit's pictures reach five
terminals**, and the largest single group of hosts it misses is not the Sixel
crowd at all: it is the **six that implement the Kitty protocol and not the
placeholder**. What that group needs is not a second protocol — it is a second
*placement model* for the protocol already built. §12.

### 3.3 Where this survey is weakest

Carried rather than smoothed over, because a coverage table is the kind of
document people quote:

- **xterm's Sixel is compiled in and switched off**, which is a trap worth more
  than a footnote because every community table this survey started from says
  "yes". Read from xterm 411's own `ptyx.h`: `optSixelGraphics(screen)` is true
  only when `GraphicsTermId(screen)` is 240, 241, 330, 340 or 382. That macro
  reads `decGraphicsID`, whose default `"420"` `charproc.c` maps to 0, and then
  falls back to `decTerminalID`, which also defaults to 420. So a stock xterm
  answers no to DA1 parameter `4` and draws nothing until it is started as
  `xterm -ti vt340` or given `decGraphicsID`. Detection is not affected — the
  DA1 answer is honest either way — but the coverage count is, and the row is
  `F`, not `Y`.
- **Apple Terminal** is an all-`N` row resting on absence of evidence.
  `terminfo.dev` actively claims it supports Kitty graphics *and* placeholders,
  which contradicts everything else here and which §2 measured the other way —
  Apple Terminal has no APC parser and prints the payload. Read as a probe
  artefact, and a reason not to use that table as a source: it also marks
  WezTerm as having no Kitty support, which its changelog contradicts.
- **Contour**'s three yeses come from reading master. Its own README advertises
  only Sixel, so which *released* version shipped the other two is unknown.
- **Warp** is closed source: changelog and issue tracker only.
- **Tabby, Hyper, Wave Terminal** are inferred from `package.json` plus at most
  one call site, not from product documentation.
- **wayst, AbsoluteTelnet, Mobile SSH, Eat** each rest on a single line.
- **mlterm's Sixel default** is inferred from the option having disappeared and
  the code being unconditional, not from a statement.

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
| `TrackRenderer` for a `TrackConfiguration.isColourField` style (`.block`, `.blockFine`, a custom `█`-on-`.solid`) | full cells + an eighths ramp | `TrackRaster` — the boundary on a PIXEL, the fill gradient sampled per pixel |
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


---

## 11. Working around the cursor-anchored protocols — assessment, 2026-09-05

**Question:** §4 rejected Sixel and the iTerm2 protocol because they draw pixels
at the cursor rather than into the cell grid. Can that be worked around?

**Answer: yes, and by a smaller mechanism than the rejection implies — but the
workaround does not make a second protocol cheap.** What follows is a design
assessment. Nothing here is built, and the parts that would need measuring
before it could be are named as such.

### 11.1 Three losses, and only one of them is the interesting one

"Not Kitty" is really three separate absences, and they do not cost the same:

| Loss | Bites where |
|---|---|
| **No retained store** | every repair retransmits pixels — the cost, §11.5 |
| **No in-grid placement** | the terminal does not know the picture occupies cells — what §4 called fatal |
| **No capability query** (iTerm2 only) | detection could only be a host table — §11.6 |

The second is the one §4 argued from, and it is the one that turns out to be
addressable, because of *where* the substitution can happen.

### 11.2 The mechanism: substitute at the writer, not at the renderer

Keep the placeholder representation exactly as it is. `TerminalImageStore`
still hands `_ImageCore` rows of cells; `strippedLength` still measures them,
`clamped` still clips them, `composited(with:at:)` still overlays them,
`ScrollView` still windows them, and `FrameDiffWriter` still decides which rows
changed. Only at the last moment — where a row becomes bytes — does a row
carrying placeholder cells stop being written as text. The writer finds each
maximal run of cells naming one image at consecutive columns of one image row,
and emits, in place of that run, a `CUP` to its first column plus a
cursor-anchored image of exactly the sub-rectangle those cells cover.

Two properties make that work, and both are already true of this code:

- **The crop is read off the cells, not computed.** Every placeholder cell
  carries its own image row and image column (`KittyGraphics.placeholderRows`
  spells them into every cell rather than using the protocol's run-length form
  — for the diffing reason recorded there). A run of surviving cells therefore
  *names* the sub-rectangle it wants. Clipping, scrolling and compositing are
  not re-implemented for pixels; they have already happened, and what is left
  says what to send. A modal covering half a picture leaves half the cells, so
  half the picture is emitted, with no z-order in the protocol and none needed.
- **Every span is positioned absolutely, and nothing scrolls.** `writeDiff`
  emits a `CUP` before every span and before every whole line, and the frame
  builder emits no `IL`, `DL` or scroll region at all. So an image that leaves
  the cursor somewhere implementation-defined damages nothing, because nothing
  downstream reads the cursor. This is the single fact that makes the
  substitution cheap.

  Relative motion does exist, but only *inside* a span: the Plane-16 and
  emoji compensations inject `ECH`+`CUF` into a built line, scoped after
  clipping (§4.1, `withTerminalAppCursorCompensation`). A substitution
  therefore has to split its span at the run's boundaries and give each
  surviving piece its own `CUP` — which it must do regardless, since the
  cursor after an image is the terminal's business. Both halves of that are
  worth a test if this is ever built: a future optimisation that elided a
  `CUP` by tracking the cursor would silently break images, and so would a
  compensation that survived across a run boundary.

Whole rectangles coalesce: where every row of an image survives intact, the
runs are identical and stacked, and one image covering the whole rectangle can
replace them. The per-row slice is the general case, not the common one.

### 11.3 What still has to be built — the damage model

This is the real work, and it is the thing placeholders give away for free.

A placeholder picture is a pure function of the cells: rewrite the cell and the
image comes back. A cursor-anchored picture is separate state that only the
writer knows about, so the writer has to decide when to re-emit. The rule falls
out of the diff — re-emit a run whenever its row is one the diff chose to write
— and that covers content change, movement, and being uncovered. It does not
cover damage the app did not cause: a resize, an alternate-screen switch,
another process writing to the terminal. TUIkit already has whole-frame
invalidation for those (`invalidate()`, `invalidateIfProgramChanged()`), and
each of those paths would have to force every image run to re-emit rather than
trusting `previousLines`.

**And the cells underneath have to be erased, not merely skipped.** The text
layer keeps whatever was last written into those cells. If the picture is lost
before the next repaint, the terminal reveals stale glyphs rather than the
page. So a run is written as spaces in the row's background first and the image
drawn over it — which also fixes an ordering rule in place: within a row, erase
then draw, and never write text into a cell an image is currently covering.
Whether writing text over an image erases the pixels underneath is
host-dependent and **is not measured here**; `graphics_probe.py` is where the
answer would go.

### 11.4 What still has to be built — two encoders, unequal

**Sixel reuses more of this package than it looks like.** It is palette-indexed,
and the palette machinery already exists: `ASCIIPalette+Adaptive` derives an
adaptive palette by median cut in OKLab, and `ASCIIConverter+Dithering` already
carries quantisation error through one. The one seam to open is that today's
derivation re-fits its centres to the terminal's colour depth, and a Sixel
colour register takes an arbitrary RGB triple — so it wants the centres from
*before* that re-fit. How many registers is not a guess: xterm's XTSMGRAPHICS
reads the current count with `CSI ? 1 ; 1 S` and the maximum with
`CSI ? 1 ; 4 S`, and `CSI ? 2 ; 1 S` reports the largest Sixel geometry in
pixels (xterm `ctlseqs`; not measured here). The encoder itself is small —
bands of six pixel rows, a pass per colour, `!<n>` run-length — and a slice one
cell tall is a partial band, which the format handles, because an unset bit
paints nothing when the DCS's P2 parameter declares unset pixels transparent.

**The iTerm2 protocol needs an encoder this package does not have**, because its
payload is a real image file rather than pixels. PNG is the format every
implementation reads, and a PNG can be written with deflate *stored* blocks —
no compressor at all, only CRC-32 and Adler-32 — which keeps it independent of
`SystemZlib`, whose whole point is that it is optional and dlopened; where a
zlib is present the same encoder compresses properly. Sizing is in cells and is
documented: a bare `width=N;height=N` means N character cells (`Npx` and `N%`
are the other spellings), with `preserveAspectRatio=0` so the picture fills the
rectangle exactly, which is what a crop needs. Nothing in the documented
argument list controls whether the cursor moves afterwards.

**The bottom row is a new hazard, of a familiar shape.** Both protocols advance
the cursor past the image, and on the last row that scrolls the screen — the
same family as the last-column problem `repaintRightEdge` exists for, but not
the same problem and not covered by it. Sixel has a mode for it, DECSDM
(`CSI ? 80 h`), and it is a trap rather than a solution: its sense was inverted
in xterm for years relative to the VT382 manuals, corrected in xterm patch #369,
and foot, mintty and contour each followed at a different release — so an app
that sets it cannot know which of two opposite behaviours it just asked for
without measuring the host. The cheap answer is to measure last-row behaviour
per host and let the framework decline the substitution for an image that would
land there, falling back to glyphs. That decline is a seam the renderer already
has, but only at whole-image granularity (`placeholderRows` returning `nil`); a
per-row decline would be new.

### 11.5 What it costs

Arithmetic over §8.6's measurements, not a new measurement. On Ghostty's
16×34-pixel cells an opaque picture transmits at about **2,170 base64 bytes a
cell** (1.8 MB for 49×17 cells; 104 KB for 12×4 — the two agree). A placeholder
cell repairs for **11.6** (139 bytes for a 12-cell row, pinned by
`KittyGraphicsTests.rowByteCost`).

| | Kitty placeholders | Cursor-anchored |
|---|---|---|
| First draw of a picture | pixels once | pixels once |
| Picture undisturbed, per frame | nothing | nothing |
| **Repairing one cell of it** | **~12 bytes** | **~2,170 bytes** (Retina cell) |

So the steady state is identical — an image nothing touches is transmitted once
either way, because the diff writes no rows — and the price of *disturbance*
rises by about **190×** on a Retina cell, nearer 45× on a non-Retina 8×17 one,
and better than either on flat content that run-lengths or deflates well. What
that buys or costs in practice is decided by how often something moves next to a
picture: a menu opening over its corner, a spinner ticking on the row beside it,
a selection travelling through a list of thumbnails. Those are nearly free today
and would not be.

### 11.6 Detection is still asymmetric

Unchanged from §1, and it decides how far this could go. Sixel is detectable and
reliable about it: DA1 parameter `4`, plus XTSMGRAPHICS to size the palette
before encoding for it. The iTerm2 protocol has no query at all, so support for
it could only ever be a host table — which §6 rejected on evidence rather than
taste: Warp is a host that answers a protocol query `OK` and then refuses the
feature, and a table written from feature lists would have got it wrong.

### 11.7 Verdict

The limitations are workable, and the reason is narrower than "Sixel turned out
to be better than §4 said". It is that the substitution happens *after* every
cell-defined operation has run, so clipping, compositing, scrolling and the row
diff never learn that pixels exist — exactly the property §4 wanted, arrived at
from the other end. §4's reasoning stands; its conclusion has one more option
under it than it knew.

What the workaround does not do is make a second protocol cheap. It costs an
encoder per protocol, a damage model with three invalidation paths, an
erase-then-draw ordering rule, a per-host last-row measurement, a host table for
the half of it that cannot be detected, and repairs one-to-two orders of
magnitude more expensive than today's. **The recommendation in §6 does not
change on this analysis alone.** What could change it is coverage — how many
hosts draw one of these and no Kitty placement — which is §3.2's question, and
§3.2 answers it by pointing somewhere else entirely. The mechanism above is
worth having; the protocol it should be pointed at first is not Sixel. **§12.**

---

## 12. The cheap half of §11: Kitty's *classic* placements — assessment, 2026-09-05

§3.2 counted six terminals that implement the Kitty graphics protocol and
explicitly not the Unicode placeholder: **WezTerm, Contour, Konsole, Warp,
Zellij and xterm.js**. TUIkit emits only placeholders, so it draws nothing on
any of them, and they are a larger group than any this framework currently
reaches. They want no new protocol. They want the *other* placement of the
protocol already built.

Everything below is read from the protocol specification, not measured. §12.4
says what would have to be.

### 12.1 A classic placement is cursor-anchored, and §11 is the answer to that

`a=p` without `U=1` renders the image "at the current cursor position, from the
upper left corner of the current cell". That is exactly the property §4
rejected Sixel and the iTerm2 protocol for — so §11's mechanism applies
unchanged: keep the placeholder cells in the buffer, let clipping, compositing,
scrolling and the diff run on them, and at the writer replace each surviving
run with a `CUP` plus a placement.

The difference is what a classic placement keeps that Sixel and the iTerm2
protocol threw away. §11's costs were four, and this loses three of them:

| §11's cost | With a classic Kitty placement |
|---|---|
| An encoder per protocol | **gone** — same `a=t` transmission, same `f=24`/`f=32`, same `o=z` |
| Retransmitting pixels to repair | **gone** — the image is still retained by id; a repair is a placement command |
| The bottom-row scroll hazard | **gone** — `C=1` sets the cursor movement policy to *no movement* |
| Cropping | **free** — `x,y,w,h` select a source rectangle in pixels of the stored image |
| The damage model (§11.3) | **stays** — the pixels are still not the cells |
| Erase-then-draw (§11.3) | **stays**, for the same reason |

Two more keys are there and are not needed: `z` places an image below text, and
TUIkit resolves z-order in the buffer before the terminal sees anything; and a
placement has its own id (`p`), so a picture can be *deleted* rather than
overdrawn, which is a cleaner answer to a view disappearing than any Sixel has.

### 12.2 What is reused verbatim

Nearly all of it, which is the argument:

- **The encoder and the wire format.** `KittyGraphics.transmit` is unchanged,
  including the `f=24` opaque path and the `o=z` deflation and its second
  handshake question (§10).
- **`TerminalImageStore`.** Ids, content-keyed sharing between views, holder
  sets, delete-on-last-release — a classic placement needs every one of those
  and needs them for the same reasons. What it adds is a placement id beside
  the image id.
- **The handshake's shape.** The exchange already asks two questions and tells
  the answers apart by id (`TerminalGraphicsQuery.parse`). A third — a classic
  placement — is one more command and one more id. It has to *draw*, unlike the
  virtual one, but the exchange already saves the cursor, wipes and restores
  (`ESC[s` … `ESC[u ESC[J`) precisely because a payload might print.

### 12.3 What it costs on the wire

A placement command for one run is on the order of sixty bytes: the APC
envelope, the image id, the placement id, four source-rectangle keys, `c`/`r`,
`C=1`, `q=2`, and the `CUP` in front of it. A placeholder run costs 11.6 bytes a
cell (§11.5). So a placement is *cheaper* than placeholders for a run longer
than about five cells and dearer below it, and both are the same order — which
is the whole point of the comparison with §11.5's 2,170 bytes a cell. Repair
stops being the problem.

### 12.4 What has to be measured before any of it

None of the above is measured, and three of the claims are exactly the kind
this project has been wrong about before:

1. **Does each of the six draw a classic placement at all?** The survey read
   "implements the Kitty graphics protocol" from changelogs and source. §2.2 is
   the standing reminder that a host can implement a protocol, acknowledge
   every command, and paint nothing.
2. **Does each honour `C=1`?** If a host moves the cursor anyway the writer
   does not care — every span is positioned absolutely (§11.2) — but a
   placement on the last row would scroll the screen, which is fatal and is the
   one hazard `C=1` was going to remove.
3. **Does each honour the source rectangle `x,y,w,h`?** Clipping depends
   entirely on it. A host that ignores those keys draws the whole picture where
   a crop belonged, which is worse than drawing nothing.

`graphics_probe.py` is where all three go, one command each, with the card a
person looks at. Until they are answered this is a design and not a plan.

### 12.5 Verdict

**This is the cheapest coverage available, by a wide margin, and it should be
measured before Sixel is reconsidered.** It roughly doubles the hosts TUIkit
draws on — five to eleven — for one new placement model, one new handshake
question, and §11's writer substitution and damage model, with the encoder, the
compression, the image store and the lifetime discipline all reused as they
stand.

§6's "do not ship Sixel, do not ship the iTerm2 protocol" is untouched by this;
if anything §3.2 strengthens it, because the fourteen Sixel-or-iTerm2 hosts cost
two encoders and a host table to reach and these six cost neither. What §6 did
not consider is that the protocol it *did* choose has two placement models and
this framework only ever built one.
