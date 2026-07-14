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
`Character.terminalAppCursorAdvance` / `.iTerm2CursorAdvance`, the
`FrameDiffWriter` compensation paths, `CheckboxStyle.automatic`, …).

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
- **Modifier on release (`m`):** a ⌘/⌥-click reaches the app with the SGR
  meta bit (+8) set on the button-**press** (`M`), but the matching
  **release** (`m`) is reported with the modifier bits **cleared**
  (inferred, not yet byte-captured — the only explanation consistent with
  "⌘-click reads as ⌥-click" AND "⌘-click still collapses a
  multi-selection", since a release that carried the meta bit toggles
  correctly in the pipeline test). Views that select on release (List /
  Table / tap gestures) would therefore see a bare click and replace the
  whole selection instead of toggling one row in. **Defence:**
  `MouseEventDispatcher.stampClickCount` remembers the press's modifier
  bits and unions them onto the matching release, so the gesture stays
  whole regardless of which report the terminal decorates. No-op where
  press and release agree (Terminal.app). *Verify with `mouse_probe.py`:
  capture a ⌘-click and confirm the `m` report's button code drops the +8
  the `M` report carried.*
- iTerm2 honours a large proprietary escape set (OSC 1337) — unused by
  TUIkit so far.
- **Cell aspect ratio (image distortion):** iTerm2's cell height:width
  ratio differs from Apple Terminal's (font + line-spacing dependent), so
  an `Image` sized for a fixed 2:1 assumption looked horizontally squished
  here (user-reported; exact ratio **not yet measured** — run
  `cell_aspect_probe.py` in each terminal to capture it). **Defence:**
  `ASCIIConverter.targetSize` now takes a `cellAspect` parameter (default
  `2.0` ≈ Apple Terminal), threaded from `environment.imageCellAspect`.
  The render root auto-detects the real ratio from `TIOCGWINSZ`
  `ws_xpixel`/`ws_ypixel` (`Terminal.cellPixelAspect()`) when the terminal
  reports them; whether iTerm2/Terminal.app populate those pixel fields on
  macOS is **unverified** (historically 0). If they don't, the
  `.imageCellAspect(_:)` modifier sets it explicitly. *Verify with
  `cell_aspect_probe.py`: it prints both the ioctl-pixel and CSI-14t/18t
  derived ratios; record iTerm2's and Apple Terminal's measured values
  here once captured.*

---

## tmux

**Status: NOT yet locally verified** — tmux is not installed on the
evaluation machine (no Homebrew either). The notes below are from tmux's
documented behaviour; treat them as expectations to verify, not
measurements.

- tmux (≥3.2) sets `TERM_PROGRAM=tmux` and `TERM_PROGRAM_VERSION`, and
  always sets `$TMUX` (socket path) and `$TMUX_PANE`. `TERM` inside is
  `screen-256color` or `tmux-256color`. This is why the Apple-Terminal
  tweaks do not apply when TUIkit runs under tmux inside Terminal.app:
  `TERM_PROGRAM` no longer says `Apple_Terminal` — and that is CORRECT
  behaviour, not a detection bug, because…
- …tmux is a **compositor**, not a passthrough: it parses TUIkit's output
  into its own cell grid using ITS OWN width tables, then re-renders that
  grid to the attached client. The outer terminal's advance quirks apply
  to *tmux's* output, not TUIkit's; what matters for TUIkit under tmux is
  agreement between TUIkit's width tables and *tmux's* (wcwidth-based,
  varies with tmux's Unicode tables). Host-specific CUF compensation
  would corrupt output under tmux and must stay off (it does — neither
  detector matches).
- Mouse: with `set -g mouse on`, tmux consumes mouse reports for its own
  panes and re-emits SGR sequences to the focused pane's application.
  Encoding fidelity (horizontal wheel, modifiers) needs verification.
- The outer terminal is not reliably identifiable from inside tmux
  (`LC_TERMINAL` propagates for iTerm2 ssh integration only; the tmux
  server keeps the environment of its FIRST client, which may not be the
  current one).

**Verification checklist when tmux becomes available:** run
`advance_probe.py` inside tmux under both Terminal.app and iTerm2 clients
(expect identical results in both — that's the compositor property);
byte-capture the mouse encoding with `mouse_probe.py`; check VS-16 /
skin-tone / PUA advances against TUIkit's width claims; record
`TERM_PROGRAM_VERSION`.

---

## Measured advance table (divergences and key rows)

DSR-measured on the ALTERNATE screen (the app's buffer), 2026-07-13.
Full battery in `Tools/TerminalProbes/` (`PROBE_ALT=1`). Claim =
`Character.terminalWidth`. Terminal.app measures identically in both
screen modes; iTerm2 does NOT (its primary screen advances VS-16
clusters and ❤️‍🔥-style ZWJ by 2).

| Cluster | Claim | Terminal.app 455.1 | iTerm2 3.6.11 |
|---|---|---|---|
| `a`, `─`, `▒`, `■`, `⣿`, NFD `é` | 1 | 1 | 1 |
| CJK 中, `██`(2), `▐▌`(2), ⬛︎ ⬜︎ (VS-15) | 2 | 2 | 2 |
| ⌚ ⌛ ⏩ ⏰ 👍 ✊ (emoji presentation) | 2 | 2 | 2 |
| ❤️ ✏️ ☎️ ☂️ ✔️ 🖥️ 🛡️ (VS-16) | 2 | **1** | **1** |
| 〰️ 〽️ (EAW base + VS-16) | 2 | 2 | 2 |
| 🇺🇸 (flag pair) | 2 | 2 | 2 |
| 🇦 (lone regional indicator) | 2 | **1** | 2 |
| 1️⃣ #️⃣ *️⃣ 1⃣ (keycaps) | 2 | 2 | **1** |
| 👍🏽 (SMP base + skin) | 2 | **4** | 2 (merged) |
| ✊🏻 (BMP emoji-pres. + skin) | 2 | **4** | **4** (swatch) |
| ☝🏽 (BMP text-pres. + skin) | 2 | **3** | **3** (swatch) |
| 👩‍🚀 / ❤️‍🔥 / 👩🏽‍🚀 (ZWJ) | 2 | **5 / 4 / 7** | 2 / **1** / 2 |
| U+100038 etc. (SF Symbols PUA) | 2 | **1** | **1** |
| 🏽 (standalone modifier) | 2 | 2 | 2 |

## Where the adaptations live

- `TerminalHost` — `TERM_PROGRAM` detection (`Apple_Terminal`,
  `iTerm.app`) + the `supportsEmojiChrome` allowlist.
- `Character.terminalAppCursorAdvance` / `Character.iTerm2CursorAdvance`
  — the per-host advance models (TUIkitCore).
- `String+CursorCompensation.swift` — the per-host line rewriters
  (CUF injection; Apple also strips mid-line skin tones);
  `String.withSkinToneFallback()` (iTerm2 skin-tone strip).
- `FrameDiffWriter` — applies the rewriters on its build path; Apple-only
  right-edge repaint.
- `CheckboxStyle.automatic` + `SwitchIndicatorGlyphs` — chrome glyph
  selection per host.
