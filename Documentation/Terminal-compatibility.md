# Terminal compatibility survey

The canonical record of how each terminal emulator behaves on every axis
TUIkit cares about — input encodings (keys, mouse, trackpad) and output
behaviour (cursor advance vs painted width, emoji handling, glyph cell
coverage, colour depth) — plus the environment variables each one defines
and the exact versions the observations were made against.

**Maintenance contract:** whenever anything new is observed or learned
about any terminal's behaviour — a new quirk, a version that changes one,
a new terminal evaluated — record it here, with the version and the method
of observation. Consult this document before making or reviewing any
change that relies on terminal-specific behaviour (`TerminalHost`,
`Character.terminalAppCursorAdvance` / `.iTerm2CursorAdvance` /
`.ghosttyCursorAdvance` / `.warpCursorAdvance`, `String.tmuxCursorAdvance`, the
`FrameDiffWriter` compensation paths, `CheckboxStyle.automatic`, …). tmux is a
**fifth cursor-advance model** here, not a fall-through to "unknown": a change
touching cursor advance must consider tmux's grid explicitly.

**Terminals covered:** Apple Terminal.app, iTerm2, Ghostty, Warp, tmux
(all measured). Jump to the
[measured advance table](#measured-advance-table-divergences-and-key-rows)
for the one-screen comparison.

## Methodology

Three reproducible probes live in `Tools/TerminalProbes/`; run them INSIDE
the terminal under test:

- `advance_probe.py` — measures the **cursor advance** of a battery of
  grapheme clusters with DSR (`ESC[6n`) position queries, and dumps the
  terminal-relevant environment. Writes JSON to `$PROBE_OUT`. Advance is
  the ground truth for layout: a glyph whose advance differs from the
  width TUIkit's tables claim shifts everything after it on the row.
  **Set `PROBE_ALT=1` and use those numbers**: TUIkit apps run on the
  ALTERNATE screen buffer, and advance can differ between buffers —
  iTerm2 advances VS-16 clusters by 2 on its primary screen but by 1 on
  the alternate screen. A first pass probed the primary screen only,
  concluded iTerm2 had no VS-16 quirk, and shipped a wrong model. iTerm2
  is also sensitive to write boundaries on the primary screen: a VS-16
  selector flushed ~100 ms after its base retro-colours the glyph without
  advancing the cursor.
- `visual_card.py` — prints a static `|<cluster>|X` alignment card with a
  column ruler; screenshot + zoom shows **painted width** (which DSR
  cannot see) and glyph appearance: merged vs split clusters, seams,
  swatches, cell coverage.
- `mouse_probe.py` — enables SGR mouse reporting (1000/1002/1006) in raw
  mode and appends every input byte sequence to `$PROBE_OUT`, for
  capturing exactly what a terminal sends per gesture.

"Advance" below = cells the cursor moves; "paints" = cells with ink.
TUIkit's shared layout width (`Character.terminalWidth`) claims 2 for all
the emoji-class clusters below unless noted.

---

## Apple Terminal.app

**Tested:** `TERM_PROGRAM_VERSION` 455.1, macOS 15.7 (Sequoia), 2026-07-13.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` |
| `TERM_PROGRAM` | `Apple_Terminal` |
| `TERM_PROGRAM_VERSION` | `455.1` |
| `TERM_SESSION_ID` | per-window UUID |
| `COLORTERM` | **not set** (no truecolor advertisement) |

### Output behaviour

- **Colour:** no truecolor — 256-colour palette is the ceiling
  (`ColorDepth` quantises; palettes must satisfy the WCAG contrast floor
  after quantisation).
- **VS-16 pictographic emoji** (❤️ ✏️ ☎️ 🖥️ 🛡️ …): paints 2,
  **advances 1** ("Bug A" — see `Emoji rendering bugs in macOS Sequoia's
  Terminal.app.md` for the full investigation). Compensated with CUF(1) by
  `withTerminalAppCursorCompensation()`. Exception: the East-Asian-Wide
  BMP bases 〰️ 〽️ ㊗️ ㊙️ advance their full 2.
- **Fitzpatrick skin tones:** the cluster renders as ONE merged,
  skin-toned glyph (paints 2) but **advances 4** (emoji-presentation
  bases: 👍🏽 ✊🏻) or **3** (text-presentation bases: ☝🏽; also ☝️🏽
  with VS-16) — "Bug B". Mid-line the modifier scalar is stripped
  (generic-yellow fallback) because the over-advance provokes a row-wide
  left shift no escape sequence recovers from; at end-of-line it is kept.
- **Flag pairs** (🇺🇸): paints 2, **advances 2** — no compensation.
  (An earlier TUIkit model said advance 1; measured 2 on 455.1.)
- **Lone regional indicator** (🇦): paints 2, **advances 1** → CUF(1).
- **Keycaps** (1️⃣ #️⃣, with or without VS-16): advance 2 ✓.
- **ZWJ sequences:** badly over-advance — 👩‍🚀 advances **5**,
  ❤️‍🔥 **4**, 👩🏽‍🚀 **7**. UNHANDLED (no compensation model); TUIkit
  chrome never emits ZWJ, but user content containing ZWJ sequences will
  shear rows here. Known limitation.
- **SF Symbols (Plane-16 PUA, U+100000+):** paints 2, **advances 1** →
  CUF(1). BMP PUA (e.g. U+E0B0 powerline): advances 1, width 1 ✓.
- **Emoji-repertoire chrome with VS-15** (⬛︎ ⬜︎ + U+FE0E): renders as a
  single seamless 2-cell monochrome, SGR-tintable glyph — *preferred*
  here because adjacent FULL BLOCK `█` cells show visible seams
  (incomplete cell coverage) in this terminal. This is why
  `CheckboxStyle.automatic` = `.emoji` on this host.
- **Block Elements:** `██` can show a hairline seam between cells;
  half-block pairs like `▐▌` render contiguously (they form the
  TextField caps and the switch knob). Shades ░▒▓ render as fine stipple.
  The image pipeline's half-block mode uses ▀ (upper) rather than ▄
  specifically to avoid a banding artifact observed here.
- **Right-edge phantom cells:** rows whose compensation leaves
  advance≠paint at the right edge can leave unpainted phantom cells;
  `FrameDiffWriter.repaintRightEdge` runs a scoped second pass.

### Input behaviour

- **Keys:** sends bare `ESC[A/B` for Up/Down — **all modifiers stripped**
  on the vertical arrows (Shift/Opt/Ctrl/Cmd); Left/Right keep their
  modifiers. Shift+Up/Down accelerators can never work here.
- **Mouse:** SGR (1006) reporting works: click press/release, wheel
  64/65. **Shift+wheel is intercepted** for the terminal's own scrollback
  — apps never see it (the Mouse demo notes this; use a trackpad's
  horizontal scroll instead). Trackpad horizontal scroll reports the
  standard horizontal wheel buttons 66/67. Right-click is reported to
  apps.
- **Mouse modifiers (byte-captured 2026-07-14, one run per modifier):**
  - **⌘-click: stripped to a plain click.** Eight deliberate ⌘-click
    press/release pairs ALL arrived as bare button code 0, symmetric —
    the app cannot tell a ⌘-click from a plain click, so **⌘-click
    multi-select toggling cannot work here** (the plain click replaces
    the selection). The pointer mirror of the Up/Down key modifier
    stripping above; not an app bug.
  - **⌥-click: forwarded as +8 (meta), symmetric** — the bit is present
    on both the press (`M`) and the release (`m`), and identically
    whether the profile's keyboard **"Use Option as Meta key"** setting
    is off or on (captured under both). TUIkit maps +8 to
    `MouseEvent.meta`, so **⌥-click** toggles rows in a multi-selection
    here. Note this is the *opposite* forwarding choice from iTerm2,
    which delivers ⌘ as +8 and swallows ⌥ (see its Input section).

---

## iTerm2

**Tested:** `TERM_PROGRAM_VERSION` 3.6.11, macOS 15.7, default profile,
2026-07-13.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` |
| `TERM_PROGRAM` | `iTerm.app` |
| `TERM_PROGRAM_VERSION` | `3.6.11` |
| `COLORTERM` | `truecolor` |
| `TERM_SESSION_ID` / `ITERM_SESSION_ID` | `wNtNpN:UUID` (both, same value) |
| `ITERM_PROFILE` | profile name |
| `LC_TERMINAL` / `LC_TERMINAL_VERSION` | `iTerm2` / version (propagates over ssh) |
| `COLORFGBG` | e.g. `0;15` |
| `TERMINFO_DIRS` | app bundle terminfo + system |

### Output behaviour

⚠️ Much of iTerm2's width handling is **configuration-dependent**
(Settings → Profiles → Text: Unicode version, ambiguous-width). All
values below are the DEFAULT profile; a profile on Unicode 8 widths would
measure differently — re-run `advance_probe.py` before trusting a
non-default setup.

- **Colour:** truecolor (24-bit) — gradients render smoothly.
- **VS-16 pictographic emoji — SCREEN-MODE DEPENDENT:** on the primary
  screen paints 2 / advances 2; on the **alternate screen** (where TUIkit
  apps run) paints 2 / **advances 1** — the same under-advance as
  Terminal.app, with the same EAW exceptions (〰️ 〽️ advance 2).
  Compensated with CUF(1) by `withITerm2CursorCompensation()`. (The
  primary-screen alignment card renders correctly; the app misrendered
  until the model was rebuilt from alternate-screen measurements —
  user-reported, byte-capture confirmed identical output bytes, and the
  `context_probe` isolated the screen mode as the variable.)
- **Fitzpatrick skin tones — split by plane:**
  - SMP bases (👍🏽): render MERGED (one skin-toned glyph), advance 2 ✓.
  - BMP bases (✊🏻 ☝🏽): render **base + separate 2-cell colour swatch**,
    advancing 4 / 3 — same numbers as Terminal.app's Bug B but with the
    swatch visible. Because TUIkit's layout claims 2, unstripped clusters
    shift the rest of the row. The iTerm2 output path therefore strips
    the modifiers (generic-yellow fallback, `withSkinToneFallback()`),
    which also makes output independent of the Unicode-version setting.
- **Flag pairs:** advance 2 ✓. **Lone regional indicator: advance 2**
  (differs from Terminal.app's 1) — width claim 2 ✓, nothing needed.
- **Keycaps** (1️⃣ #️⃣ *️⃣, bare or with VS-16): paints 2, **advances 1**
  (both screen modes) → CUF(1) via `withITerm2CursorCompensation()`.
- **SF Symbols (Plane-16 PUA):** paints 2 (monochrome, SGR-tintable),
  **advances 1** → CUF(1). Same under-advance as Terminal.app.
- **ZWJ sequences:** advance 2 ✓ (unlike Terminal.app) — EXCEPT
  VS-16-leading ones (❤️‍🔥) which advance 1 on the alternate screen;
  unhandled (ZWJ is unhandled on both hosts).
- **Emoji chrome with VS-15** (⬛︎ ⬜︎ + U+FE0E): monochrome, tintable,
  2 cells, no shear — on the `supportsEmojiChrome` allowlist, so
  `CheckboxStyle.automatic` = `.emoji` here too.
- **Block Elements:** gap-free full-cell coverage — `██` contiguous, no
  seams; shades ░▒▓ draw as a dotted crosshatch texture (font flavour,
  cosmetically different from Terminal.app's stipple). Half-block images
  (▀) and background-fill images render seamlessly. Because the crosshatch
  covers less of the cell than a solid `█`, a bar that mixes the two — a
  `█` fill against a `░` empty run — reads with the filled part visibly
  TALLER than the empty part here. So `TrackStyle.block` (and `.blockFine`)
  paint the empty run as a solid *background* instead of a `░` glyph,
  giving a uniform-height two-tone bar on every terminal.

### Input behaviour

- **Mouse (byte-captured):** SGR click `0` press/`m` release; wheel
  64/65. macOS translates **Shift+wheel into horizontal wheel deltas**, so
  iTerm2 reports Shift+wheel as the standard horizontal buttons **66/67**
  (+4 Shift) — reaching apps, unlike Terminal.app. (TUIkit's decoder
  maps 66/67 to `.scrollLeft`/`.scrollRight`; a pre-2026-07 decoder
  collapsed both into `.scrollDown`, which made Shift+wheel always scroll
  right.)
- **Right-click:** by DEFAULT iTerm2 opens its own context menu and the
  app never sees the click; configurable in Settings → Pointer
  (user-reported). **⌘-click is reported to apps as an ⌥-click**
  (user-reported). There is no escape sequence or variable that exposes
  the pointer configuration, so TUIkit cannot detect the setting; the
  example's Mouse page shows a static note under iTerm2 instead.
- **Modifier-clicks (byte-captured 2026-07-14, one run per modifier):**
  - **⌘-click → +8 (meta), symmetric.** Six deliberate ⌘-clicks arrived
    as SGR button code **8** with the meta bit present on **both** the
    press (`M`) **and** the matching release (`m`) — every pair fully
    symmetric (`ESC[<8;x;yM` … `ESC[<8;x;ym`). The earlier
    **release-drops-meta hypothesis is refuted** for iTerm2 3.6.11:
    release-acting handlers (List/Table selection, tap gestures) see the
    decorated click intact. `MouseEventDispatcher.stampClickCount` still
    unions the press's modifier bits onto the matching release as
    defence-in-depth for unmeasured terminals; on iTerm2 it is a no-op.
    This is also the byte-level substance of the user-reported "⌘-click
    reads as ⌥-click": ⌘ is delivered as the protocol's meta (alt) bit,
    which apps decode as an option-click.
  - **⌥-click → nothing.** A dedicated ⌥-click run produced **no report
    at all** — the default pointer bindings consume ⌥-clicks (cursor
    placement / rectangular selection), so apps never see them.
  - Net: iTerm2 forwards **⌘** and swallows **⌥** — the *opposite* of
    Apple Terminal (which forwards ⌥ as +8 and strips ⌘; see its Input
    section). Both deliver the surviving key as the same +8 bit, so
    TUIkit's `ctrl || meta` multi-select toggle works on both — but any
    user-facing hint must name a different physical key per terminal:
    **⌘-click here, ⌥-click in Apple Terminal**.

  *Earlier general captures (2026-07-14, before the probe logged
  `TERM_PROGRAM`):* plain clicks are **symmetric** (press `M` and
  release `m` carry the same button code, all SGR — no X10 "any
  release" fallback seen); shift+horizontal wheel arrives as **70/71**
  (66/67 + shift), confirming the Shift-wheel decoding above; drags
  report `+32` motion codes with clean SGR releases.
- iTerm2 honours a large proprietary escape set (OSC 1337) — unused by
  TUIkit so far.
- **Cell aspect ratio (image distortion):** iTerm2's cell height:width
  ratio differs from Apple Terminal's (font + line-spacing dependent), so
  an `Image` sized for a fixed 2:1 assumption looked horizontally squished
  here (user-reported). **Measured** with `cell_aspect_probe.py`
  (2026-07-14, default fonts/profiles):

  | Terminal | ioctl `TIOCGWINSZ` px fields | CSI `14t`/`18t` | aspect (ioctl / CSI) |
  |---|---|---|---|
  | Apple_Terminal 455.1 | 215×54 ch, 1505×756 px → 7.00×14.00 px/cell | 1515×763 px → 7.05×14.13 | **2.000** / 2.005 |
  | iTerm.app 3.6.11 | 80×25 ch, 1120×850 px → 14.00×34.00 px/cell | 570×458 px → 7.12×18.32 | **2.429** / 2.571 |

  Both terminals DO populate the `ws_xpixel`/`ws_ypixel` fields (the
  historical-zero concern did not reproduce), so the render root's
  auto-detection is live on both. Apple Terminal's two reports agree
  (2.000 ≈ 2.005) and match the framework's 2.0 default exactly. iTerm2's
  two reports **disagree by ~6%** (ioctl 2.429 vs CSI 2.571): the CSI
  report is self-consistent in points, while the ioctl fields look like a
  differently-rounded (retina-scaled) cell metric — either confirms iTerm2
  is meaningfully taller than 2:1, and the ~6% residual between them is
  visually minor. **Defence:** `ASCIIConverter.targetSize` takes a
  `cellAspect` parameter (default `2.0` ≈ Apple Terminal), threaded from
  `environment.imageCellAspect`; the render root auto-detects via
  `Terminal.cellPixelAspect()` (ioctl-based → 2.43 on this iTerm2, within
  the 1.0…4.0 sanity band), and `.imageCellAspect(_:)` overrides
  explicitly. *Residual: if circles still look slightly tall on iTerm2,
  the CSI-derived 2.57 is the candidate correction — verify by eye with a
  known-square image before switching sources.*

---

## Ghostty

**Tested:** 1.3.1 (`TERM_PROGRAM_VERSION`), macOS 15.7, default config,
2026-07-14.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-ghostty` (ships its own terminfo; often overridden to `xterm-256color` for remote hosts, so **do not detect on `TERM`**) |
| `TERM_PROGRAM` | `ghostty` |
| `TERM_PROGRAM_VERSION` | `1.3.1` |
| `COLORTERM` | `truecolor` |
| `TERMINFO` | app bundle terminfo |
| `GHOSTTY_BIN_DIR` / `GHOSTTY_RESOURCES_DIR` / `GHOSTTY_SHELL_FEATURES` | set |
| `__CFBundleIdentifier` | `com.mitchellh.ghostty` |

### Output behaviour

**Ghostty is the most Unicode-correct terminal measured.** Every class that
Terminal.app and iTerm2 get wrong — VS-16 pictographs, ZWJ sequences,
Fitzpatrick skin tones, keycaps, flags, lone regional indicators — advances
by exactly the 2 cells `terminalWidth` claims, on BOTH screen buffers
(primary and alternate agree on every row of the battery). Skin-toned emoji
render as one merged glyph (👍🏽 = 2 cells), so the iTerm2/Warp swatch strip
is deliberately NOT applied here — it would discard a correct rendering.

- **Colour:** truecolor.
- **Two under-advancers** (the only compensation Ghostty needs —
  `withGhosttyCursorCompensation()`):
  - **VS-15 chrome glyphs** (⬛︎ ⬜︎ = emoji-presentation base + U+FE0E):
    paints 2, **advances 1**. Uncompensated this collides the following
    label with the glyph — observed on the Toggle demo as `■On` where
    `.unicode` correctly showed `■ On`. CUF(1) fixes it, which is what
    earns Ghostty its place on the `supportsEmojiChrome` allowlist.
  - **SF Symbols (Plane-16 PUA):** unlike Terminal.app/iTerm2 (which paint
    2 and advance 1), Ghostty renders these grid-strictly at **1 cell** and
    advances 1. The claim of 2 is therefore an over-claim here; CUF(1)
    keeps the row aligned at the cost of one blank cell after each symbol.
    *A tighter fix would be a host-dependent width claim, but the claim is
    deliberately host-independent (layout must be identical headless).*
- **`☝🏽` / `☝️🏽`** (BMP text-presentation base + skin tone) advance 1 and
  **4** respectively against a claim of 2 — the only over-advance measured
  on Ghostty. Unhandled, as ZWJ is on Terminal.app; these clusters do not
  appear in TUIkit's own chrome.
- **Cell aspect ratio:** fills `ws_xpixel`/`ws_ypixel` AND answers CSI
  14t/18t, which agree within ~1.4% (ioctl **2.154**, CSI 2.125 — default
  font). Slightly taller than the 2.0 default; auto-detection handles it.

### Input behaviour

- **Mouse (byte-captured 2026-07-14):** textbook SGR (1006). Plain clicks
  are symmetric (`ESC[<0;13;6M` press / `ESC[<0;13;6m` release); wheel is
  64 (up) / 65 (down); **horizontal wheel reports 66/67**, which is
  exactly what TUIkit's decoder maps to `.scrollLeft`/`.scrollRight`. No
  quirk found — nothing to work around.
- *Not yet captured:* modifier-clicks (⌘/⌥). Ghostty is expected to
  forward more than the Apple terminals do (it has no ⌘-click binding of
  its own by default), but that is a hypothesis until byte-captured —
  run `mouse_probe.py` and ⌘-click, then ⌥-click, in separate runs. The
  key-encoding side (arrows + modifiers, Fn keys, Escape timing) is also
  uncaptured.

---

## Warp

**Tested:** `v0.2026.07.08.17.54.stable_02`, macOS 15.7, default config,
2026-07-14.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` (**not** a Warp-specific value — detect on `TERM_PROGRAM`) |
| `TERM_PROGRAM` | `WarpTerminal` |
| `TERM_PROGRAM_VERSION` | `v0.2026.07.08.17.54.stable_02` |
| `COLORTERM` | `truecolor` |
| `WARP_TERMINAL_SESSION_UUID` / `WARP_IS_LOCAL_SHELL_SESSION` / `WARP_HONOR_PS1` … | set |
| `__CFBundleIdentifier` | `dev.warp.Warp-Stable` |

### Output behaviour

Warp is the mirror image of Ghostty: it gets the *selector* classes right
and the *composed* classes wrong.

- **Colour:** truecolor.
- **VS-16 pictographs** (❤️ ✏️ 🖥️) advance 2 ✓ — no Bug-A compensation
  (unlike Terminal.app and iTerm2).
- **VS-15 chrome** (⬛︎ ⬜︎) advances 2 ✓ and paints clean squares → Warp is
  on the `supportsEmojiChrome` allowlist with no help at all.
- **Fitzpatrick skin tones paint base + a separate swatch at 4 cells**
  (3 for BMP bases) against a claim of 2 — the same shape as Terminal.app's
  Bug B and iTerm2's. **Observed** in the demo's "Unicode compatible"
  feature box: the skin-toned 👍🏽 sheared the box's right border two cells
  out of place. Handled by the shared `withSkinToneFallback()` strip.
- **Lone regional indicator** (🇦) advances 1 against a claim of 2 — same as
  Terminal.app; CUF via `withWarpCursorCompensation()`.
- **OVER-advancers, unhandled** (no escape can pull a cursor back to a
  column the glyph has already painted over):
  keycaps 1️⃣ #️⃣ *️⃣ advance **3**; 〰️ 〽️ advance **3**; ZWJ 👩‍🚀
  advances **5**, ❤️‍🔥 **5**, 👩🏽‍🚀 **7**. ZWJ is equally unhandled on
  Terminal.app (5/4/7), so this is the established limitation, not a new
  one — but keycaps and 〰️ are Warp-specific and DO shear rows.
- ⚠️ **Warp disagrees with itself across screen buffers** — more than any
  other terminal measured. Primary advances VS-16 by 1, alternate by 2;
  keycaps 1 vs 3; ZWJ 4/3/6 vs 5/5/7. The models use the **alternate**
  screen, where TUIkit apps run. Probe with `PROBE_ALT=1`.
- **Cell aspect ratio:** fills `ws_xpixel`/`ws_ypixel` AND answers CSI
  14t/18t, agreeing within ~2% (ioctl **1.956**, CSI 2.000) — essentially
  the 2.0 default, so images need no correction here.

### Input behaviour

Mouse SGR (1006) reporting works; **not yet byte-captured** (clicks, wheel,
modifiers, key encodings all remain to be measured — do not assume they
match Ghostty's). Warp defaults to `default_session_mode = "agent"` in
`~/.warp/settings.toml`, and its own UI overlays (tab switcher, command
palette) sit above the app — neither affects the app's byte stream.

**Driving Warp non-interactively** (it has no `-e`): write a launch
configuration to `~/.warp/launch_configurations/NAME.yaml` with a
`commands: - exec: …` entry and open `warp://launch/NAME`. Ghostty by
contrast takes `open -na Ghostty.app --args -e <cmd>`.

---

## tmux

**Status: MEASURED — tmux 3.7b (Homebrew, arm64), 2026-07-15.** DSR-probed
with `advance_probe.py` run *inside* a detached tmux session (no client
attached at all — the purest test of the compositor property below: tmux
answered every DSR from its own grid with nothing downstream to ask).

### Environment (measured, confirms the ≥3.2 expectation)

| Variable | Value inside a pane |
|---|---|
| `TERM_PROGRAM` | `tmux` — **overwritten**, does NOT pass the outer terminal's through |
| `TERM_PROGRAM_VERSION` | `3.7b` |
| `TERM` | `tmux-256color` |
| `COLORTERM` | `truecolor` |
| `TMUX` / `TMUX_PANE` | socket path / `%0` |

So under tmux the four native detectors all miss (`Apple_Terminal`,
`iTerm.app`, `ghostty`, `WarpTerminal`) — but tmux is NOT treated as an
unknown host. It is detected in its own right (`TerminalHost.isTmux`, from
`$TMUX`) and is a **first-class host with its own width model**, because tmux
is a **compositor**, not a passthrough: it parses TUIkit's output into its own
grid with its own width tables and re-renders. The outer terminal's advance
quirks apply to *tmux's* output, not TUIkit's, so tmux's model is the one
TUIkit must satisfy — and `FrameDiffWriter` checks `isTmux` FIRST, ahead of
every native host, so a native variable that survived into the pane cannot
select the wrong model (see `String.withTmuxCursorCompensation()`).

> **History.** Until 8c1e06d8 (2026-07-15) tmux WAS treated as unknown and got
> no compensation and no emoji chrome; the paragraphs below were once written
> to argue that was correct. It was not — tmux's grid diverges from TUIkit's
> width claims (measured, next), so leaving compensation off sheared exactly
> the glyphs a native host would have had fixed. This section now describes the
> shipped behaviour; the "live bug" is closed.

**Colour is fine:** tmux 3.7b preserves 24-bit SGR in its grid
(`ESC[38;2;255;100;0m` survives verbatim) and sets `COLORTERM=truecolor`, so
TUIkit's depth detection picks truecolor correctly. No `Tc`/`RGB`
`terminal-features` tweak needed at this version.

### Cursor advance — where tmux DISAGREES with TUIkit, and how it is handled

What matters under tmux is agreement between TUIkit's width tables and
*tmux's* wcwidth. Measured, with what the tmux path now does about each
divergence (`String.tmuxCursorAdvance` + `withTmuxCursorCompensation()` +
`withSkinToneFallback(basePlane: .bmpOnly)`):

| Cluster | tmux 3.7b | TUIkit claims | Handled how |
|---|---|---|---|
| `U+100038` etc. (Plane-16 PUA, **SF Symbols**) | **1** | **2** (`String+TerminalWidth.swift:166`) | CUF: one `ESC[1C` after each, landing the cursor at the claimed column |
| `U+1F5A5`, `U+1F6E1`, `U+1F577`, `U+1F39E`, `U+1F3D9` (bare SMP pictographs) | **1** | **2** | CUF, same as above |
| `U+1F060` domino, `U+1F0A1` playing card | **1** | 2 | CUF, same as above |
| `U+270A U+1F3FB` (**BMP** + skin tone) | **4** | 2 | swatch stripped (`.bmpOnly`) → back to a 2-cell advance |
| `U+2B1B U+FE0E` (VS-15 chrome ⬛︎) | **2** | 2 | ✓ already agrees (both 2) — no action |
| `U+1F1E6` lone regional indicator | 1 | 1 | ✓ |
| `U+4E2D` CJK · `U+1F44D` emoji · ZWJ families · `U+1F1FA U+1F1F8` flag | 2 | 2 | ✓ |
| `U+1F44D U+1F3FD` (**SMP** + skin tone) | 2 | 2 | ✓ — NOT stripped (`.bmpOnly` keeps it; tmux joins it correctly) |
| `U+0065 U+0301` NFD · `U+E0B0` powerline · `U+2588` block | 1 | 1 | ✓ |

**The defect this closed:** the main menu's "Supports SF Symbols" FeatureBox
renders **three** Plane-16 PUA glyphs. TUIkit reserves 2 cells each (6); tmux
advances 1 each (3). Before 8c1e06d8 nothing compensated, so — measured in
tmux's own grid at 100×60 — that line's right border landed at **cell 65**
while every other line of the box landed at **68**, exactly 3 cells short, one
per glyph, and the border was visibly broken. The tmux path now emits one CUF
per under-advancing cluster, landing the cursor at the claimed column, so the
border closes. Same fix for the bare SMP pictographs and the dominoes/cards.

The `:166` comment ("SF Mono: 2 cells") is right about the *font* in a native
terminal and about the width TUIkit paints; tmux's wcwidth has never heard of
SF Symbols and advances 1, which is why the tmux path adds the CUF rather than
changing the claim. `withSkinToneFallback(basePlane: .bmpOnly)` is deliberately
narrower than the iTerm2/Warp blanket strip: tmux joins an **SMP**-base skin
tone (👍🏽) into the 2 cells claimed, and only over-advances on a **BMP** base
(✊🏻 ☝🏽), so stripping the SMP ones would discard a cluster tmux gets right.

### Pane geometry (why a "normal" terminal still hits small-size bugs)

tmux reaches tiny panes from an ordinary window in three keystrokes. Measured
from a 100×40 window, splitting horizontally:

| splits | resulting pane heights |
|---|---|
| 1 | 20, 19 |
| 2 | 10, 9 |
| **3** | **5, 4** |
| 4 | 2, 2 |

`resize-window -y 12` is honoured exactly. **A 4-row pane in a 100×40 window
is three keystrokes away** — which is how a user with a perfectly normal
terminal lands in the negative-content-height crash band (see
`contentAreaHeight()`; crash fixed in c02c3678, which renders header + status
bar with an empty content area at 4 rows instead of trapping). Verified: four
TUIkitExample panes at heights 19/9/5/4, all `pane_dead=0`.

### Does the client terminal change tmux's behaviour? No. (measured)

The compositor property is now demonstrated, not assumed. `advance_probe.py`
was run **five ways** — with Apple Terminal, iTerm2, Ghostty and Warp attached,
and with no client attached at all:

> **All 58 clusters, all five runs: ZERO differences.**

tmux's grid does not depend on which terminal is attached, or on one being
attached at all. That is why there is **one** `tmuxCursorAdvance` model rather
than four, and why the outer terminal's quirks are irrelevant to our output.

### Identifying the client terminal (research)

It IS possible — tmux probes each client with XTVERSION and exposes the answer:

| Client | `#{client_termtype}` | `#{client_termname}` | `#{client_termfeatures}` |
|---|---|---|---|
| iTerm2 | `iTerm2 3.6.11` | `xterm-256color` | 256,bpaste,ccolour,clipboard,hyperlinks,cstyle,extkeys,focus,margins,mouse,osc7,progressbar,RGB,sixel,strikethrough,sync,title,usstyle |
| Ghostty | `ghostty 1.3.1` | `xterm-ghostty` | bpaste,ccolour,clipboard,cstyle,focus,RGB,title |
| Warp | `Warp(v0.2026.07.08…)` | `xterm-256color` | bpaste,ccolour,clipboard,cstyle,focus,RGB,title |
| Apple Terminal | *(empty — answers no XTVERSION)* | `xterm-256color` | bpaste,ccolour,clipboard,cstyle,focus,title |

Read from inside a pane with
`tmux display-message -p '#{client_termtype}'`. Three of four are named **and
versioned**. Ghostty is additionally the only one with a distinctive `TERM`.

**Apple Terminal is NOT identifiable from that table — measured.** The feature
set above reads like a fingerprint, and isn't: a bare PTY with
`TERM=xterm-256color` and no terminal behind it at all reports exactly
`bpaste,ccolour,clipboard,cstyle,focus,title` too. tmux derives
`client_termfeatures` from terminfo, so it identifies the `TERM`, not the app.
Identification by elimination fails for the same reason — "empty termtype" is
every silent terminal, not one of them.

**It is identifiable from its process tree.** A tmux client's ancestry is the
window it was launched in, and `#{client_pid}` is the handle:

```
  32465  /opt/homebrew/Cellar/tmux/3.7b/bin/tmux     <- #{client_pid}
  32453  /bin/zsh
  32452  /usr/bin/login
    509  /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
```

This is the CLIENT's chain, not ours — the tmux server is a daemon reparented to
launchd, so our own ancestry says nothing about who is watching. Local only: over
ssh the client's parent is `sshd` and the terminal is on the other end. Costs no
subprocess (`sysctl` per link, `proc_pidpath` per path).

**Environment leakage does NOT work — measured.** Terminals leak their own
variables into panes (`LC_TERMINAL=iTerm2`, `ITERM_SESSION_ID`, `GHOSTTY_*`,
`WARP_*`, `TERM_SESSION_ID`), which looks like a free answer. It is a trap: the
tmux **server** keeps the environment of the client that STARTED it, forever.
Measured by starting a server from Apple Terminal and attaching iTerm2 to the
same session:

```
FIRST client (Apple Terminal started the server)
  client_termtype     =                     <- Apple Terminal
  env TERM_SESSION_ID = 05D12807-…          <- Apple Terminal's
SECOND client attached (iTerm2), same pane, same process
  client_termtype     = iTerm2 3.6.11       <- LIVE, correct
  env TERM_SESSION_ID = 05D12807-…          <- STILL Apple Terminal's. Stale.
  env LC_TERMINAL     = <unset>             <- iTerm2 is attached; still unset.
```

**And the question is malformed anyway: there may be more than one client.**
The same run had both attached simultaneously —

```
attached client: /dev/ttys010 termtype=
attached client: /dev/ttys012 termtype=iTerm2 3.6.11
```

— two terminals, two fonts, painting the same bytes at the same time. There is
no single "the client app" to specialise for. This is a property of a
multiplexer, not a gap in the detection.

**With two clients attached, `display-message` reports the most recently
ACTIVE one** — measured with Apple Terminal and Ghostty on one session: it
returned `ghostty 1.3.1`, the higher `client_activity` (…632 vs …625), and did
not drift afterwards. `list-clients` enumerates them all individually, each with
its own termtype, which is what TUIkit uses.

**How it is used.** Widths never need the client (the grid is
client-independent, measured), so this drives exactly one decision: the emoji
chrome, whose glyphs are painted by the client's font. Each client is
identified by XTVERSION if it answered, and by its owning application if it did
not; the two are complementary, since XTVERSION crosses an ssh hop and the
process walk doesn't, while the process walk finds a silent terminal and
XTVERSION can't.

- **A client unidentified by BOTH loses the chrome** — a terminal that stays
  silent and isn't a local app we recognise is a real thing (a Linux VT console,
  an old xterm over ssh) and would draw tofu.
- **Every attached client must be recognised**, not just the active one — two
  fonts can be painting the same bytes.

**PUSH, not poll — tmux hooks (measured, 3.7b).** A same-size re-attach sends
no SIGWINCH, so waiting for one would keep a stale answer indefinitely, and
re-probing on a timer would fork in steady state for nothing. Instead, at
startup the app registers three global tmux hooks at array index = its PID —
`client-attached[pid]`, `client-detached[pid]`, `client-session-changed[pid]`
(the complete set of events that can change which terminals paint our output;
all three fire on 3.7b, including for a same-size attach and a SIGKILLed
client) — each running:

```
run-shell -b "kill -s WINCH <pid> || tmux set-hook -gu '<hook>[<pid>]'"
```

Every part measured or load-bearing:

- **Global at a PID index, never session-scoped**: a session-scoped hook
  shadows the user's ENTIRE global array for that hook name (measured — the
  user's `client-attached[0]` stopped firing), while two global hooks at
  different indices coexist. The PID index also keeps several TUIkit apps on
  one server out of each other's slots.
- **SIGWINCH as the channel**: the app already has a complete, tested SIGWINCH
  pipeline (async-signal-safe flag + self-pipe that wakes the idle-blocked
  loop, full repaint) — a client change rides it with zero new plumbing. And
  SIGWINCH's default action is IGNORE, so a stale hook signalling a recycled
  PID after a crash is harmless (SIGUSR1 would terminate an innocent process).
- **Self-cleaning**: `kill` fails once the PID is gone, and the `||` arm
  removes the hook on its first firing after an uncleaned death. Measured: all
  three orphaned hooks removed themselves within one attach/detach cycle.
  A clean exit removes them explicitly (`set-hook -gu`, ours and only ours).
- **The probe is asynchronous**: the SIGWINCH path kicks a background
  `list-clients` (bounded 250ms; coalesced to at-most-one-in-flight plus one
  queued re-run, so a resize drag costs one or two probes, not one per event).
  Frames keep rendering with the previous answer while it runs; if the landed
  answer differs, the whole screen is invalidated and re-rendered proactively —
  the loop is woken even if it was idle, no keypress needed.

Steady state — no client changes, no resizes — runs **no subprocess at all**.
A tmux too old for these hooks degrades gracefully: registration fails, and
the app adapts only on real SIGWINCHes.

**The attach race (measured).** `client-attached` fires — and the hook-driven
probe runs — BEFORE the new client's XTVERSION reply has arrived, so
`#{client_termtype}` is empty at that instant even for a terminal that names
itself milliseconds later (a hook logging `list-clients` at attach time
recorded an empty termtype for an iTerm2 that reported "iTerm2 3.6.11"
moments later). Two mitigations:

- The process walk covers the common silent cases immediately — including
  iTerm2 with session restoration enabled (the default), whose shells' parent
  chains end at `~/Library/Application Support/iTerm2/iTermServer-<version>`
  rather than the app bundle (measured; the bundle never appears in the chain).
- A reading derived from a still-silent, unidentified client is retried on a
  bounded backoff (250ms/500ms/1s), long enough for the XTVERSION round trip
  and burning out quickly for a genuinely unknown silent terminal.

A probe that FAILS outright (wedged tmux, deadline) keeps the previous answer
rather than reading as "no clients": one slow `list-clients` under load must
not restyle every glyph on screen and flip it back a moment later.

**A chrome flip invalidates the render cache**, not just the frame diff: the
diff invalidation rewrites every line, but line content comes from the render
pass, and value-memoized subtrees would otherwise serve buffers with the old
glyphs baked in — observed as a mixed-style screen (touched rows in the new
style, untouched rows in the old) with misaligned labels where a stale 2-cell
⬛︎ buffer met fresh 1-cell ■ measurements.

**It follows a client change mid-run**, which is the point — `CheckboxStyle.automatic`
is a marker resolved at render, not a style decided when the value was made, so
even an app's own explicit `.checkboxStyle(.automatic)` adapts. Verified end to
end on one running app with the client swapped underneath it: it drew ⬛ while
Ghostty watched, and still ⬛ when Apple Terminal took the session with
`attach -d` — same process, no restart, and no termtype to go on the second time.

| client attached | identified by | checkbox glyphs |
|---|---|---|
| Ghostty / iTerm2 / Warp | `#{client_termtype}`, named + versioned | ⬛ ⬜ emoji |
| Apple Terminal, local | owning application (termtype is empty) | ⬛ ⬜ emoji |
| Apple Terminal, over ssh | nothing — silent, and sshd owns the client | ■ □ |
| an unknown silent terminal | nothing | ■ □ |
| several, all recognised | either signal, per client | ⬛ ⬜ emoji |
| several, any unrecognised | — | ■ □ |

### Mouse

**SGR (1006) reporting passes through and the coordinates are correct.**
Verified end to end: with tmux at its default (`mouse off`), TUIkitExample's own
`ESC[?1006h` / `?1002h` reach the client, and a synthetic press/release injected
into the pane —

```
tmux send-keys -t <pane> -H <hex of ESC[<0;45;11M then ESC[<0;45;11m>
```

— landed on the menu row at screen line 11 and navigated the app to that page.
So tmux neither eats the enable sequence nor shifts the reported cell.

Not yet measured: the encoding under `set -g mouse on` (tmux then consumes
reports for its own pane management and re-emits to the focused pane), and
whether modifier bits survive that path.

### Still unverified

- Cell pixel aspect for images: tmux does not forward the client's
  `ws_xpixel`/`ws_ypixel`, so `cellPixelAspect()` returns nil and callers keep
  their default. Not yet measured whether that default is right under tmux —
  and it cannot be right for every client at once when two are attached.

**Reproduce:** `tmux -L probe new-session -d -x 120 -y 40 -e PROBE_OUT=/tmp/t.json
'python3 Tools/TerminalProbes/advance_probe.py; sleep 2'` then read `/tmp/t.json`.
Always use a dedicated `-L <socket>` and set `TUIKIT_CONFIG_DIR` so probes
never touch a real session or the user's preferences.

---

## Measured advance table (divergences and key rows)

DSR-measured on the ALTERNATE screen (the app's buffer). Terminal.app +
iTerm2 2026-07-13; Ghostty + Warp 2026-07-14; the bare-pictograph and
non-emoji rows re-measured across ALL FOUR on 2026-07-14 (Terminal.app
re-measured the same day too — identical, so the harness is
cross-validated). Every cell here is measured; none is inferred. Full battery in
`Tools/TerminalProbes/` (`PROBE_ALT=1`). Claim = `Character.terminalWidth`.
Terminal.app and Ghostty measure identically in both screen modes; iTerm2
and (much more so) Warp do NOT — always probe with `PROBE_ALT=1`.

**Bold = diverges from the claim** (i.e. needs compensation, or shears).

| Cluster | Claim | Terminal.app 455.1 | iTerm2 3.6.11 | Ghostty 1.3.1 | Warp 2026.07.08 |
|---|---|---|---|---|---|
| `a`, `─`, `▒`, `■`, `⣿`, NFD `é` | 1 | 1 | 1 | 1 | 1 |
| CJK 中, `██`(2), `▐▌`(2) | 2 | 2 | 2 | 2 | 2 |
| ⬛︎ ⬜︎ (VS-15 chrome) | 2 | 2 | 2 | **1** | 2 |
| ⌚ ⌛ ⏩ ⏰ 👍 ✊ (emoji presentation) | 2 | 2 | 2 | 2 | 2 |
| ❤️ ✏️ ☎️ ☂️ ✔️ 🖥️ 🛡️ (VS-16) | 2 | **1** | **1** | 2 | 2 |
| 〰️ 〽️ (EAW base + VS-16) | 2 | 2 | 2 | 2 | **3** |
| 🇺🇸 (flag pair) | 2 | 2 | 2 | 2 | 2 |
| 🇦 (lone regional indicator) | 2 | **1** | 2 | 2 | **1** |
| 1️⃣ #️⃣ *️⃣ (keycaps) | 2 | 2 | **1** | 2 | **3** |
| 1⃣ (bare keycap, no VS-16) | 1 | **2** | 1 | 1 | 1 |
| 👍🏽 (SMP base + skin) | 2 | **4** | 2 (merged) | 2 (merged) | **4** |
| ✊🏻 (BMP emoji-pres. + skin) | 2 | **4** | **4** (swatch) | 2 (merged) | **4** |
| ☝🏽 (BMP text-pres. + skin) | 2 | **3** | **3** (swatch) | **1** | **3** |
| ☝️🏽 (…+ VS-16) | 2 | **3** | **3** | **4** | **4** |
| 👩‍🚀 / ❤️‍🔥 / 👩🏽‍🚀 (ZWJ) | 2 | **5 / 4 / 7** | 2 / **1** / 2 | 2 / 2 / 2 | **5 / 5 / 7** |
| U+100038 etc. (SF Symbols PUA) | 2 | **1** (paints 2) | **1** (paints 2) | **1** (paints 1) | **1** |
| 🏽 (standalone modifier) | 2 | 2 | 2 | 2 | 2 |
| 🖥 🛡 🕹 🕷 🎞 🏙 (bare SMP pictograph) | 2 | **1** | **1** | **1** | **1** |
| ⤷ *(compensated since 2026-07-14 — all four CUF)* | | ✓ | ✓ | ✓ | ✓ |
| 🁠 🂡 (domino / card — in-block non-emoji) | 2 | **1** | **1** | **1** | **1** |

tmux is a fifth advance model and is measured separately (its grid is
client-independent, so it needs no per-client column) — see
[the tmux cursor-advance table](#cursor-advance--where-tmux-disagrees-with-tuikit-and-how-it-is-handled).

### Bare (selector-less) pictographs — FIXED 2026-07-14

**Not to be confused with `🖥️`** (U+1F5A5 **+ U+FE0F**) — the form the demo
app and virtually all real text uses, and which has always been correct on
all four terminals (Apple/iTerm2 under-advance it and the CUF fixes it;
Ghostty/Warp advance it natively). **This section is the BARE form**, no
variation selector: a different grapheme cluster.

`terminalWidth` ends with a blanket `0x1F000...0x1FBFF → 2` rule, so a bare
🖥 claims 2. Advance is 1 on **every** terminal, and no model said so — a
single scalar cannot trip `isVS16UnderAdvancer`, so each model fell through
to `terminalWidth` and reported 2, contradicting its own probe data. Model
== claim ⇒ no CUF ⇒ the row sheared one cell left.

**Both halves measured 2026-07-14** — advance by DSR (`advance_probe.py`),
paint by eye (`paintcard.py`, a `|<glyph>|X` row: if the closing pipe
survives the glyph painted 1):

| Class | Example | `isEmojiPresentation` | Claim | Advance | Paint (Apple) |
|---|---|---|---|---|---|
| BMP text-presentation | ✏ ❤ ☝ ☂ ✔ ☎ | false | 1 ✓ | 1 | 1 ✓ |
| SMP text-presentation | 🖥 🛡 🕹 🕷 🎞 🏙 | false | 2 | 1 | **2** |
| SMP emoji-presentation | 👍 🀄 | true | 2 ✓ | 2 | 2 ✓ |
| In-block non-emoji | 🁠 🂡 | false | **2** ✗ | 1 | **1** |

The paint row is what decides the fix, and it overturned the first guess.
The claim of **2 is correct** for the SMP pictographs: macOS has no text
glyph for them, so font fallback reaches Apple Color Emoji and paints 2
cells — the glyph eats the closing `|` exactly as a VS-16 cluster does,
while its BMP twins leave it intact. So this was never a claim bug: it is a
**model** bug, and the fix is `Character.isBarePictographUnderAdvancer`,
which all four models now consult. Verified end-to-end in Apple Terminal:
`|🖥X` (pipe eaten) became `|🖥|X` (pipe restored), with 👍 unaffected.
A claim of 1 would have been actively wrong — Apple would then paint over
the following cell. Ghostty, the one host that paints these at 1 cell, takes
a blank cell instead of a shear — the same trade already accepted for its SF
Symbols, and the right one, since a host-independent claim must cover the
widest painter.

**Still open — the in-block non-emoji row.** 🁠 🂡 (dominoes, playing cards)
claim 2 but paint 1 and advance 1 *everywhere*, so for them the claim really
is wrong and 1 is right; they shear today. Fixing that means narrowing the
blanket rule, which is riskier than it looks: the same range holds
U+1F200–1F2FF (Enclosed Ideographic Supplement, 🈁 🈚), which IS East Asian
Wide and mostly NOT emoji — so gating the rule on `isEmoji` would wrongly
drop those to 1. Any narrowing must be range-precise (Mahjong/Dominoes/Cards
are U+1F000–1F0FF) and re-measured, and it moves golden snapshots. Reach is
negligible: playing-card and domino codepoints in TUI content.

**SF Symbols PUA** is a third claim-vs-advance mismatch (no terminal advances
2) but is already handled: Apple/iTerm2 genuinely paint 2, so the claim is
right and the CUF is correct; only Ghostty paints 1 and takes the blank cell.

## Where the adaptations live

- `TerminalHost` — `TERM_PROGRAM` detection (`Apple_Terminal`,
  `iTerm.app`, `ghostty`, `WarpTerminal`) + the `supportsEmojiChrome`
  allowlist (all four; Ghostty only because its CUF fixes the VS-15
  under-advance).
- `Character.terminalAppCursorAdvance` / `.iTerm2CursorAdvance` /
  `.ghosttyCursorAdvance` / `.warpCursorAdvance` — the per-host advance
  models (TUIkitCore), each pinned to the table above by
  `GhosttyWarpCompatibilityTests` / `StringTerminalWidthTests`.
- `String+CursorCompensation.swift` — the per-host line rewriters.
  `withCursorForwardCompensation(advance:)` is the shared CUF walk for
  every host whose quirks are pure under-advances (iTerm2, Ghostty, Warp);
  Terminal.app keeps its own walk because it must also rewrite content.
  `String.withSkinToneFallback()` — the swatch strip, used by iTerm2 AND
  Warp (NOT Ghostty, which merges skin tones correctly).

### Per-host output pipeline (FrameDiffWriter)

The branch is checked in this order, **tmux first** — its grid is what our
output lands in, so it must win over any native host flag that leaked into the
pane. (`FrameDiffWriter.init` also zeroes the four native flags when `isTmux`,
so the tmux-first rule holds at the clip and right-edge repaint too, not only
here.)

| Host | Clip | Then |
|---|---|---|
| tmux | plain | `withSkinToneFallback(.bmpOnly)` → `withTmuxCursorCompensation()` |
| Apple Terminal | cursor-aware | `withTerminalAppCursorCompensation()` |
| iTerm2 | plain | `withSkinToneFallback()` → `withITerm2CursorCompensation()` |
| Ghostty | plain | `withGhosttyCursorCompensation()` |
| Warp | plain | `withSkinToneFallback()` → `withWarpCursorCompensation()` |
| anything else | plain | **untouched** (compensation would corrupt a correct terminal) |
- `FrameDiffWriter` — applies the rewriters on its build path; Apple-only
  right-edge repaint.
- `CheckboxStyle.automatic` + `SwitchIndicatorGlyphs` — chrome glyph
  selection per host.
