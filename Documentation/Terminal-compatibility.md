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
`FrameDiffWriter` compensation paths, `ToggleCharacterSet.automatic`, …). tmux is a
**fifth cursor-advance model** here, not a fall-through to "unknown": a change
touching cursor advance must consider tmux's grid explicitly.

**Terminals covered:** Apple Terminal.app, iTerm2, Ghostty, Warp, tmux
(all measured). Jump to the
[measured advance table](#measured-advance-table-divergences-and-key-rows)
for the one-screen comparison.

## Methodology

Reproducible probes live in `Tools/TerminalProbes/`; run them INSIDE
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
- `visual_card.py` — prints a static `|<c>|<c>|<c>|X` alignment card with a
  column ruler; screenshot + zoom shows **painted width** (which DSR
  cannot see) and glyph appearance: merged vs split clusters, seams,
  swatches, cell coverage.
- `mouse_probe.py` — enables SGR mouse reporting (1000/1002/1006) in raw
  mode and appends every input byte sequence to `$PROBE_OUT`, for
  capturing exactly what a terminal sends per gesture.
- `identity_probe.py` — asks the terminal **who it is** over escape
  sequences (DA1, DA2, DA3, XTVERSION, XTGETTCAP) rather than trusting the
  environment, and dumps the identifying variables alongside. Each query is
  fenced with a DSR request, which every terminal answers, so a query that
  goes unanswered reports `<silent>` instead of hanging. This is the only
  identification that survives an ssh hop — see the next section.

The `TerminalClientQuirks` app (`swift run TerminalClientQuirks`) is the
interactive counterpart to these probes: it shows which terminal was
detected and by which signal, the advance model in force, and an alignment
strip that fails visibly on any cluster the host handles differently from
TUIkit. Its **Custom** screen decomposes the workarounds into one switch per
cluster class, so an unmeasured terminal can be characterised by experiment
and exported as a `TerminalQuirks(...)` literal — see
`Sources/TerminalClientQuirks/README.md`.

"Advance" below = cells the cursor moves; "paints" = cells with ink.
TUIkit's shared layout width (`Character.terminalWidth`) claims 2 for all
the emoji-class clusters below unless noted.

---

## Identifying the host terminal

Every per-terminal model in this document is only as good as the answer to
"which terminal is this?". That question has a clean answer locally and a
poor one over ssh, and the gap is a real, shipped rendering bug rather than
a theoretical one.

**`TERM_PROGRAM` does not cross an ssh hop.** It is not an `LC_*` variable,
and OpenSSH forwards only `LANG` and `LC_*` by default (measured:
`/etc/ssh/ssh_config.d/100-macos.conf` sends `LANG LC_*`). The complete
environment of an `ssh` session into macOS from Apple Terminal, captured
2026-08-26, contains nothing that names the terminal:

```
LANG=en_AU.UTF-8            TERM=xterm-256color
SSH_CLIENT=…  SSH_CONNECTION=…  SSH_TTY=/dev/ttys008
SHELL=/bin/zsh  USER=…  HOME=…  PATH=…  TMPDIR=…  SHLVL=1  PWD=…
```

No `TERM_PROGRAM`, no `LC_TERMINAL`, no `TERM_SESSION_ID`; `TERM` is the
generic `xterm-256color` that dozens of terminals report.

**What that costs.** An unidentified host gets no cursor-advance
compensation, and that default is correct and must stay: absent explicit
evidence otherwise, a terminal is assumed to render correctly. Every
compensation here is a workaround for a measured *defect*, so applying one
blindly would penalise a well-behaved terminal that simply isn't
special-cased — breaking a row that was fine. The bug is upstream of that
choice. Apple Terminal is not an unknown terminal; it is the most heavily
measured host in this document, and it was landing in the unknown bucket
purely because of the transport. Unnamed, it renders (measured on the
`Example` main menu):

| Cluster class | Symptom with no compensation |
|---|---|
| VS-16 pictographs (🛡️ ✏️ ❤️) | paints 2, advances 1 — row pulled 1 cell left per emoji |
| Lone regional indicators (U+1F1E6…) | same 2/1 under-advance |
| SF Symbols (Plane-16 PUA) | same 2/1 — three adjacent symbols sit 1 cell apart, not 2 |
| Fitzpatrick clusters (🤙🏽) | modifier never stripped: over-advances, stranding 2 unpainted cells at the right edge |

**The signals, and how far each reaches.**

| Signal | Names | Crosses ssh | Notes |
|---|---|---|---|
| `TERM_PROGRAM` | all four hosts + tmux | ✗ | authoritative when present |
| `LC_TERMINAL` | iTerm2 only | ✓ | set by iTerm2's shell integration; `LC_*` is forwarded |
| `TERM` | **Ghostty only** | ✓ | the termtype travels in ssh's `pty-req` (RFC 4254 §6.2) |
| XTVERSION (`ESC[>0q`) | iTerm2, Ghostty, Warp | ✓ | **Apple Terminal answers nothing** |
| Process-ancestry walk | local apps | ✗ | over ssh the parent is `sshd` |
| `TUIKIT_TERM_PROGRAM` | anything | ✓ | explicit override, same vocabulary as `TERM_PROGRAM` |

**`TERM` as an identity — added 2026-08-26.** Measured across the four hosts,
only one names itself:

| terminal | `TERM` |
|---|---|
| Ghostty 1.3.1 | `xterm-ghostty` |
| Apple Terminal 455.1 | `xterm-256color` |
| iTerm2 3.6.11 | `xterm-256color` |
| Warp 2026.07 | `xterm-256color` |

So it closes exactly one gap, and a real one: **Ghostty over ssh was
unidentified.** `TERM_PROGRAM` is gone, Ghostty sets no `LC_TERMINAL`, and the
Device Attributes fingerprint names only Apple Terminal — so its VS-15 chrome
glyphs (⬛︎ ⬜︎, which every Toggle draws) and its SF Symbols went
uncompensated and those rows sheared. Verified end-to-end by running
`TerminalClientQuirks` in Ghostty with the environment scrubbed to what an ssh
hop leaves: identified as Ghostty, compensating.

Generic termtypes are excluded — `xterm-256color` is three of the four hosts
above — as are the multiplexer termtypes (`tmux-256color`, `screen-256color`),
which name the multiplexer rather than the terminal and are answered by
`$TMUX` first anyway. A test pins both exclusions.

A note on the risk that kept this out until now: `TERM` is routinely
*downgraded* to `xterm-256color` when sshing to a host without Ghostty's
terminfo entry (this Mac has ncurses 6.0.20150808 and no `xterm-ghostty`
entry, so that is the common case, not the exotic one). That is a false
NEGATIVE — it makes `TERM` name nothing — and cannot be caused by consulting
it. `TERM_PROGRAM` still outranks it, so a downgraded `TERM` beside a local
`TERM_PROGRAM` is unaffected.

The one host that most needs naming is the one no remote-capable signal
reaches: Apple Terminal sets no forwarded variable and answers no XTVERSION.
Hence `TUIKIT_TERM_PROGRAM`, which a remote shell profile or an ssh
`SendEnv`/`AcceptEnv` pair can set:

```sh
export TUIKIT_TERM_PROGRAM=Apple_Terminal
```

Precedence is `TUIKIT_TERM_PROGRAM` → `TERM_PROGRAM` → `LC_TERMINAL` →
`TERM`: the explicit answer first, the local answer next, the forwarded one
after that because it can arrive stale from a hop further back, and the
termtype last because it is the weakest — most terminals set a value that
names nothing, and a user can set it to anything. An `LC_TERMINAL` naming a
terminal with no model here falls through to `TERM` rather than blocking it:
it did not name *this* host, so it has nothing to outrank.

### Asking the terminal — Device Attributes (measured 2026-08-26)

Device Attributes are answered by terminals that answer no XTVERSION, and
cross an ssh hop like any other escape. Measured with `identity_probe.py`
through ssh (Apple Terminal 455.1 / macOS 15.7); Ghostty's and Warp's DA
strings were read out of their shipped binaries, and iTerm2's DA2 format
string (`ESC[>%d;%d;0c`) likewise.

| Query | Apple Terminal | Ghostty | Warp | iTerm2 |
|---|---|---|---|---|
| XTVERSION | *silent* | answers | answers | answers |
| DA1 `ESC[c` | `ESC[?1;2c` | `ESC[?62;22c` | `ESC[?62c` | `ESC[?62;…c` |
| DA2 `ESC[>c` | `ESC[>1;95;0c` | `ESC[>1;10;0c` | — | `ESC[>…;…;0c` |
| DA3 `ESC[=c` | `ESC[?1;2c` (!) | — | — | — |

Apple Terminal answers DA3 with a **DA1 reply** — it ignores the `=` and
treats `ESC[=c` as `ESC[c`. Noted as a curiosity; nothing depends on it.

⚠️ **Do not send DCS queries at startup.** XTGETTCAP (`ESC P + q … ESC \`)
is not safe: Apple Terminal does not parse DCS and *prints the payload* —
measured, it left a literal `+q544e` on the screen. Every query TUIkit sends
is a CSI sequence, and every one it sends today is consumed correctly even by
a terminal implementing none of them — but **not because CSI parsing is
generic**, which was the reason recorded here until 2026-08-26 and is false.

**Measured 2026-08-26, Terminal.app 455.1.** Sending `CSI ? 9999 <byte> p`
for each of the sixteen ECMA-48 intermediate bytes `0x20…0x2F`, and reading
the cursor column before and after to see whether the parser emitted text:

| shape | Terminal.app | iTerm2 | Ghostty | Warp |
|---|---|---|---|---|
| all 16 intermediates, with `?` | **leaks the final byte** | clean | clean | clean |
| any intermediate, no `?` | clean | clean | clean | clean |
| `?`, no intermediate | clean | clean | clean | clean |
| neither | clean | clean | clean | clean |

So the rule is narrower and sharper than "CSI is safe", and narrower than the
"any intermediate byte is unsafe" version reported elsewhere:

> Terminal.app leaks a CSI's final byte **if and only if the sequence carries
> both a `?` private-parameter marker and an intermediate byte.** Either one
> alone is consumed correctly.

Verified against all four combinations with two different intermediates
(`SP`, `$`) and two different final bytes (`p`, `z`) — eight sequences, and
the `?`-plus-intermediate quadrant is exactly the leaking one.

What follows for TUIkit:

- The four queries it sends — `CSI c`, `CSI > c`, `CSI > 0 q`, `CSI 6 n` —
  have no `?` and no intermediate, and all four were re-confirmed clean on
  Terminal.app on 2026-08-26. `TerminalIdentityQueryTests` now pins this so a
  future addition cannot quietly break it.
- **`CSI ? Ps $ p` — DECRQM in its DEC-private form — is exactly the unsafe
  shape**, and it is how modes 2026 (synchronised output) and 2027 (grapheme
  clustering) are negotiated. Sending one blind puts a `p` on the user's
  screen; measured here, twice, for both modes.
- The ANSI form `CSI Ps $ p` (no `?`) is clean, so ANSI-mode DECRQM is
  available on Terminal.app even though DEC-private DECRQM is not.
- Apple Terminal answers no DECRQM at all — both mode queries were silent —
  so there is nothing to gain by sending one there in any case.

**The fingerprint TUIkit ships** (`TerminalHost.nameFromDeviceAttributes`)
names Apple Terminal, and nothing else, by requiring all three of:

- **XTVERSION silence** — excludes the three hosts above, and kitty,
  WezTerm, foot and contour besides.
- **DA1 exactly `ESC[?1;2c`** — "VT100 with the Advanced Video Option", a
  1978 feature set. Modern emulators report VT220 or later (`?62`, `?63`,
  `?64`) because applications gate features on it, so this clause does most
  of the work.
- **DA2 matching `ESC[>1;…;0c`** — excludes the multiplexers, which are the
  real collision risk for the DA1 clause: GNU screen also reports VT100+AVO
  but identifies as terminal type 83 (`'S'`), and xterm as 41. tmux never
  reaches here (`$TMUX` answers first), but screen is not detected at all,
  and compensating inside a multiplexer would corrupt its grid.

The firmware field is deliberately not pinned to the measured `95`: it is a
version number by definition, and matching it exactly would mean a macOS
update silently switching the compensation back off.

The exchange is one write and one round trip, sent only when the environment
named no host, and fenced with a DSR request so a query nobody implements
costs nothing. `Tools/Smoke/identity_smoke.py` runs a real binary under a PTY
impersonating each terminal and asserts the compensation appears for Apple
Terminal and for nobody else — the wiring guard, since `TerminalHost`'s
detectors are `static let` and freeze on first read, so the query must run
before the render loop is built.

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
  (`ColorDepth` quantises). Framework-chosen label colours are floored
  **through the cube**: `Color.ensuringRenderedContrast(atLeast:against:)`
  measures each candidate — and the face — after `downsampledToPalette256()`,
  so the ratio that is guaranteed is the one on screen. It has to be, because
  the cube moves the FACE as well as the label: Green's button face is its
  accent at 20% over black (`#003300`) and the nearest cube green is `#005f00`,
  **3.5× the luminance**, so a `.destructive` label cleared 3:1 where it was
  measured and sat at 2.61:1 where it was read. (Floored in truecolor instead,
  a colour sitting exactly on the floor came out anywhere between 1.4:1 and
  4.7:1 once mapped into the cube.)

  Two floors, because one is not enough here: `labelContrastFloor` (3:1) for a
  live label, `disabledLabelContrastFloor` (2.4:1) for a disabled one — WCAG
  exempts inactive components, and pinned to the same 3:1 six palettes drew
  both states in the *identical* cube entry. `LabelContrastTests` pins all
  three properties across the sixteen built-in palettes: readable, recessive,
  and tellable apart.

  A **surface** (a text field, a tab island) is a different question and takes a
  different measure: not "can this be read on that" but "are these two shades
  visibly different", which a contrast ratio cannot answer — it flattens at both
  ends of the range, scoring two plainly different near-blacks at 1.08 and two
  plainly different creams at 1.05. Surfaces use perceived lightness (CIE L\*,
  `Color.perceivedLightness`) and step the page's own colour until they are far
  enough off it. The step scales the page's channels rather than mixing toward
  black or white, because mixing desaturates: a phosphor palette's near-black
  page mixed 10% toward white is grey, and a green terminal grew grey text
  fields.

  **How far** depends on how big the surface is. A *plane* — a tab body, a
  header strip — is ΔL\* 5 (`Palette.planeSeparation`, behind
  `liftedBackground`), because a large area needs less of a difference to read
  as one. A *well* — the field behind editable text — is ΔL\* 10
  (`wellSeparation`, behind `fieldBackground`), because a small one has to
  announce an edge. One number for both made the choice between them: at a
  plane's step Novel's fields disappeared, and at a well's every tab body read
  as a panel.

  **How far is measured in the colours the terminal will actually paint.** On a
  truecolor terminal the raw step is the step. On a 256-colour one the walk has
  to continue until the 6×6×6 cube separates the two (at half the floor, since
  the cube's own snapping does some of the work), and in dark saturated hues,
  where the cube's rungs are 95 apart, that costs a much bigger jump. Demanding
  the cube's jump on *every* terminal made a field inside a dark tab body come
  out three times its intended step — a bright green block on a theme whose
  point is that it is nearly black. (`Palette.hoveredControlFace` deliberately
  goes the other way and compares through the cube everywhere: a hover's tint is
  small, and looking the same on every terminal is worth more than the fidelity.
  Surfaces cannot look the same on both anyway — the cube moves the page too.)

  **Which way is decided once, for the whole palette** (`surfacesRunLighter`):
  by the palette's stated `appHeaderBackground` where it has a visible opinion,
  else away from the text where the page has room for it, else toward the text.
  Every rung follows that one direction. Asking "away from the text?" afresh at
  each rung folds the ladder back on itself — a dark palette's tab body steps
  lighter (its page has no room to go darker), and a field inside that body,
  asking again from there, steps darker and lands back on the page colour, which
  is what it looked like: a hole punched through the tab, on ten of the sixteen
  built-in palettes. Where the chosen direction runs out (a 256-colour terminal
  brightening Red's field until the cube can tell it apart makes the light text
  on it unreadable first), the other direction is taken instead — but only if it
  lands somewhere still visibly not the page. Red on a 256-colour terminal is
  the one palette where nothing satisfies all three, and its field inside a tab
  body quantises onto the tab's own cube entry.

  The step is taken from whatever is actually **behind** the control, not always
  from the page: a `TextField` inside a `TabView`'s body asked for "a surface on
  the page" and got the tab's own colour, both being the same step from the same
  place. A container that paints a surface publishes it
  (`EnvironmentValues.surfaceBackground`); the field derives from that.
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
- **ZWJ sequences:** DSR reports a wild over-advance — 👩‍🚀 **5**,
  ❤️‍🔥 **4**, 👩🏽‍🚀 **7** — but **the glyphs paint 2 cells and rows do
  NOT shear**. Terminal.app's cursor report and its paint position disagree
  here; the claim of 2 is correct and no compensation is wanted. See
  *ZWJ: where DSR lies* below — this bullet said the opposite until
  2026-08-26.
- **SF Symbols (Plane-16 PUA, U+100000+):** paints 2, **advances 1** →
  CUF(1). BMP PUA (e.g. U+E0B0 powerline): advances 1, width 1 ✓.
- **Emoji-repertoire chrome with VS-15** (⬛︎ ⬜︎ + U+FE0E): renders as a
  single seamless 2-cell monochrome, SGR-tintable glyph — *preferred*
  here because adjacent FULL BLOCK `█` cells show visible seams
  (incomplete cell coverage) in this terminal. This is why
  `ToggleCharacterSet.automatic` = `.emoji` on this host.
- **Block Elements:** `██` can show a hairline seam between cells;
  half-block pairs like `▐▌` render contiguously (they form the
  TextField caps and the switch knob). Shades ░▒▓ render as fine stipple.
  The image pipeline's half-block mode uses ▀ (upper) rather than ▄
  specifically to avoid a banding artifact observed here.
  **`Appearance.block`** (added 2026-08-20) draws its edges as a run of
  `█`, and takes the mitigation `TrackConfiguration.block` already used:
  ``BorderStyle/paintsBackground`` makes the cell's background the glyph's
  own colour, so the pixels the glyph misses are the right colour and the
  seams have nothing to show through to. The title and the focus dot are
  painted on the band too — and floored against it rather than against the
  page, since that is what they are now read on.
- **Right-edge phantom cells:** rows whose compensation leaves
  advance≠paint at the right edge can leave unpainted phantom cells;
  `FrameDiffWriter.repaintRightEdge` runs a scoped second pass.

### Input behaviour

- **Keys:** sends bare `ESC[A/B` for Up/Down — **all modifiers stripped**
  on the vertical arrows (Shift/Opt/Ctrl/Cmd); Left/Right keep their
  modifiers. Shift+Up/Down accelerators can never work here.
- **Function keys carry no modifier bits at all.** Rather than the
  `ESC[21;2~` (`;2` = Shift) form every other terminal uses, Terminal.app's
  shipped key map re-codes **Shift+F5…Shift+F12** as the *VT220 F13…F20*
  sequences — Shift+F10 arrives as `ESC[32~`, byte-identical to a real F18.
  See "Shifted function keys are re-coded" below.
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
- **ZWJ sequences:** advance 2 ✓ and paint 2 ✓ — confirmed by the paint
  card, not only by DSR. EXCEPT VS-16-leading ones (❤️‍🔥 🏳️‍🌈) which
  advance 1 on the alternate screen; unhandled.
- **Emoji chrome with VS-15** (⬛︎ ⬜︎ + U+FE0E): monochrome, tintable,
  2 cells, no shear — on the `supportsEmojiChrome` allowlist, so
  `ToggleCharacterSet.automatic` = `.emoji` here too.
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
  example's Mouse page shows a static note under iTerm2 instead. This is
  why TUIkit's `.contextMenu` accepts a **Ctrl-click** as a secondary
  trigger in addition to a right-click: where iTerm2 swallows the
  right-click for its own menu, Ctrl-click still reaches the app and
  opens the TUIkit context menu. (Right-click reaches apps directly in
  Apple Terminal, Ghostty and Warp — see those sections.)
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
  advances **5**, ❤️‍🔥 **5**, 👩🏽‍🚀 **7**.

  ⚠️ **Warp's ZWJ over-advance is the real one, and it is Warp's alone.**
  Warp does not compose ZWJ sequences — it draws the components, 👩 then 🚀 —
  so paint and advance agree with each other and disagree with the claim, and
  rows genuinely shift right. This was recorded as "equally unhandled on
  Terminal.app (5/4/7)"; it is not. Terminal.app composes the cluster into 2
  cells and only its DSR report runs ahead, so its rows do not shear. See
  *ZWJ: where DSR lies*. Keycaps and 〰️ remain Warp-specific and DO shear.
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
Example panes at heights 19/9/5/4, all `pane_dead=0`.

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

**The through-tmux bar is stricter than the native one — Ghostty fails it
(measured, 2026-07-16).** Natively a terminal qualifies with our compensation
applied; through tmux no compensation can reach the client (a CUF we emit
lands in tmux's grid and corrupts it). And tmux does not replay our bytes: it
redraws a VS-15 cell to the client as

```
⬛ BS BS ⬛︎        (bare U+2B1B, two backspaces, U+2B1B U+FE0E)
```

(byte-captured from a logging client, 3.7b). The client must advance that
sequence by the 2 cells tmux believes it occupies, unaided. DSR-measured on
the alternate screen against exactly those bytes:

| client | net advance | through-tmux emoji chrome |
|---|---|---|
| Apple Terminal 455.1 | 2 | ✓ |
| iTerm2 3.6.11 | 2 | ✓ |
| Warp v0.2026.07.08 | 2 | ✓ |
| **Ghostty 1.3.1** | **1** | ✗ — excluded |

Ghostty's net-1 is its known VS-15 under-advance (bare ⬛ advances 2, the two
BS go back 2, the re-write with U+FE0E advances only 1) — the single quirk
`withGhosttyCursorCompensation()` patches natively. Uncompensated, every row
containing a chrome glyph shears left by one — observed in Example as
`⬛Enable Notifications` losing its gap and the right-edge scrollbar
checkering, one sheared row at a time. So tmux+Ghostty draws the safe ■ □
while native Ghostty keeps the emoji chrome.

**Skin tones through tmux are per-client too — and the mirror image
(measured, 2026-07-16).** tmux re-emits SMP-base skin-tone clusters (👍🏽)
**verbatim** — no backspace trick (byte-captured) — so each client applies its
NATIVE advance while tmux's grid believes 2 cells:

| client | 👍🏽 verbatim advance | tones through tmux |
|---|---|---|
| Ghostty 1.3.1 | 2 | ✓ kept |
| iTerm2 3.6.11 | 2 | ✗ stripped — paints the tone as a broken separate swatch, the same appearance its native path strips for |
| Apple Terminal 455.1 | **4** | ✗ stripped — row shears right by 2 |
| Warp v0.2026.07.08 | **4** | ✗ stripped |

So the per-client policy converges exactly on the native one: Ghostty alone
keeps skin tones. The strip happens at SOURCE (`FrameDiffWriter`'s
`tmuxSkinToneBasePlane`, `.bmpOnly` for all-Ghostty clients, `.all`
otherwise) — the one fix that survives the hop, because tmux's grid then
holds and re-emits the toneless cluster. The plane rides the same
push-refreshed client probe as the chrome, so a client change restyles both
in the same full redraw. BMP-base tones (✊🏻 ☝🏽) are always stripped under
tmux: tmux's own grid over-advances those, client-independent.

**A chrome flip invalidates the render cache**, not just the frame diff: the
diff invalidation rewrites every line, but line content comes from the render
pass, and value-memoized subtrees would otherwise serve buffers with the old
glyphs baked in — observed as a mixed-style screen (touched rows in the new
style, untouched rows in the old) with misaligned labels where a stale 2-cell
⬛︎ buffer met fresh 1-cell ■ measurements.

**It follows a client change mid-run**, which is the point — `ToggleCharacterSet.automatic`
is a marker resolved at render, not a style decided when the value was made, so
even an app's own explicit `.toggleCharacterSet(.automatic)` adapts. Verified end to
end on one running app with the client swapped underneath it: it drew ⬛ while
Ghostty watched, and still ⬛ when Apple Terminal took the session with
`attach -d` — same process, no restart, and no termtype to go on the second time.

| client attached | identified by | checkbox glyphs |
|---|---|---|
| iTerm2 / Warp | `#{client_termtype}`, named + versioned | ⬛ ⬜ emoji |
| Ghostty | `#{client_termtype}` — identified, and **excluded** | ■ □ (see below) |
| Apple Terminal, local | owning application (termtype is empty) | ⬛ ⬜ emoji |
| Apple Terminal, over ssh | nothing — silent, and sshd owns the client | ■ □ |
| an unknown silent terminal | nothing | ■ □ |
| several, all recognised | either signal, per client | ⬛ ⬜ emoji |
| several, any unrecognised | — | ■ □ |

### Mouse

**SGR (1006) reporting passes through and the coordinates are correct.**
Verified end to end: with tmux at its default (`mouse off`), Example's own
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

## What an ANSI colour actually paints

**Status: MEASURED for Apple Terminal.app 455.1 (default "Basic" profile),
2026-08-24. Other hosts pending.** `Tools/TerminalProbes/palette_probe.py` asks
a terminal directly (OSC 4 / OSC 10 / OSC 11) and writes the answer as JSON;
run it in each host and record the results below.

### Apple Terminal.app 455.1, "Basic" — measured

It answered all 25 queries, and **15 of the 16 ANSI names differ from xterm's
table**. Only slot 0 (black) matches.

| slot | reported | xterm | | slot | reported | xterm |
|---|---|---|---|---|---|---|
| 1 red | 153, 0, 0 | 205, 0, 0 | | 9 | 230, 0, 0 | 255, 0, 0 |
| 2 green | 0, 166, 0 | 0, 205, 0 | | 10 | 0, 217, 0 | 0, 255, 0 |
| 3 yellow | 153, 153, 0 | 205, 205, 0 | | 11 | 230, 230, 0 | 255, 255, 0 |
| 4 blue | 0, 0, 179 | 0, 0, 238 | | 12 | 0, 0, 255 | 92, 92, 255 |
| 5 magenta | 179, 0, 179 | 205, 0, 205 | | 13 | 230, 0, 230 | 255, 0, 255 |
| 6 cyan | 0, 166, 179 | 0, 205, 205 | | 14 | 0, 230, 230 | 0, 255, 255 |
| 7 white | 191, 191, 191 | 229, 229, 229 | | 15 | 230, 230, 230 | 255, 255, 255 |
| 8 br.black | 102, 102, 102 | 127, 127, 127 | | | | |

**Default foreground `(0, 0, 0)` on background `(255, 255, 255)` — black on
white.** The out-of-the-box Apple terminal is a LIGHT one, which is worth
knowing before assuming a dark surface anywhere.

**The 6×6×6 cube and the greyscale ramp match xterm exactly** — 21, 46, 52,
124, 196, 231, 232, 240 and 255 were all sampled and all agreed. So this host
remaps the sixteen NAMES and nothing else, which is the pattern the section
above called conventional, now with one host's evidence behind it.

#### What that costs, computed

Terminal.app's palette is systematically MUTED — every name darker or less
saturated than xterm's. Against its own white background that makes contrast
*better* than the table predicts, uniformly:

| slot | believed | actual |
|---|---|---|
| 1 red | 5.84 | 8.92 |
| 2 green | 2.16 | 3.25 |
| 3 yellow | 1.70 | 3.04 |
| 4 blue | 9.40 | 12.72 |
| 6 cyan | 1.98 | 2.96 |
| 7 white | 1.26 | 1.84 |
| 8 br.black | 4.00 | 5.74 |
| 12 br.blue | 4.74 | 8.59 |

So `ensuringContrast` believes every ANSI colour is less legible than it is,
and **over-corrects** — which is the safe direction to be wrong in (it pushes
toward legibility, never away). Two things still follow:

- A colour it would have left alone gets adjusted anyway, so an app asking for
  `Color.red` on this host may not get quite the red it asked for.
- Slots 3 and 7 are below the floor on either table, so a bare `.yellow` or
  `.white` foreground on a light terminal is illegible however it is computed.
  That is a fact about light backgrounds, not about the table.

None of this reaches colours TUIkit chooses itself: those are palette roles,
which resolve to RGB and are stated exactly.

### The three colour spellings are not equally literal

| what we emit | what the terminal does with it |
|---|---|
| `SGR 30–37` / `90–97` (the 16 names) | Looks up slot *n* of the **user's colour scheme**. "Red" is a name, not a colour, and the user may make it green. |
| `SGR 38;5;n` (256-colour) | Slots 0–15 are the same sixteen, so they are remapped identically. 16–231 (the 6×6×6 cube) and 232–255 (the grey ramp) are conventionally fixed — but `OSC 4` can set any index, so "conventionally" is the strongest word available. |
| `SGR 38;2;r;g;b` (24-bit) | The colour is stated exactly and there is nothing to look up. It can still be *adjusted* — iTerm2's minimum-contrast setting will move a foreground it judges illegible against its background, and a terminal applying a colour profile shifts everything. |
| `SGR 39` / `49` (default fg/bg) | The user's configured default. This is what ``Color/default`` means, and it is the only spelling that is *defined* as "whatever the user chose". |

### Why this is load-bearing rather than trivia

`ANSIColor.rgbValues` carries xterm's conventional table — and its doc comment
says so. Two things derive real decisions from it:

- **The contrast floor.** `ensuringContrast` computes a WCAG ratio, which needs
  luminances, which need RGB. Against a remapped scheme the ratio it computes
  is not the ratio on screen.
- **Quantisation.** Downsampling a truecolor value for a 256-colour terminal
  searches for the nearest entry by RGB distance. If the first sixteen entries
  are not where the table thinks, the "nearest" one may not look nearest.

Both degrade rather than break: they are approximations against an unknown
palette, and they are the best available, because **an app cannot know the
user's scheme unless it asks** — which is what the probe does, and what nothing
in the render path does today.

### What follows for the framework's own colours

A colour TUIkit chooses for the user — a focus highlight, a disabled label —
should not be a fixed ANSI name, because the name's appearance is not ours to
predict. It should be either a **palette role**, which the app's theme defines
and which resolves to something we did choose, or ``Color/default``, which is
explicitly the user's. Naming `Color.blue` and hoping is the one option with no
defensible reading. (This is the reasoning that re-pointed
``Color/primary``/``Color/secondary``/``Color/accentColor`` at palette roles;
see `Documentation/Parity-decisions-pending.md` §1–2 for the decision.)

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
| ❤️ ✏️ ☎️ ☂️ ✔️ 🖥️ 🛡️ ⚙️ ⚠️ ✂️ ⚒️ (VS-16) | 2 | **1** | **1** | 2 | 2 |
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

### A skipped cell is not a painted cell — Terminal.app, FIXED 2026-08-23

Cursor advance is only half of an under-advancing cluster. The other half is
what happens to the cell the cursor was pushed PAST.

`CUF` moves without painting, so inside a coloured run that cell keeps whatever
was in it — and a wide glyph is drawn across it regardless. On a highlighted row
the emoji therefore came with a hole in it: the row's fill stopped at the
glyph's first cell and resumed after its second, in the terminal's default
background. Reported against a file list drawing `⚙️ .swiftlint.yml` on a
selected row.

**Measured** (`Tools/TerminalProbes/background_probe.py`, `PROBE_ALT=1`,
2026-08-23) by drawing eight clusters in a row on a coloured run, which turns a
one-cell hole into stripes no screenshot can be ambiguous about:

| host | cell the cursor skipped | with `CUF` alone |
|---|---|---|
| Terminal.app 455.1 | **not painted** | a comb: every second cell the terminal's default |
| iTerm2 3.6.11 | painted | unbroken run |
| Ghostty 1.3.1 | painted | unbroken run |

So the fix is Terminal.app's alone. `withTerminalAppCursorCompensation` now
emits **ECH** (`CSI n X`) before the cluster: it erases n cells from the cursor
in the current background and does not move it, so the glyph is then drawn over
cells that already carry the fill. Measured identical advance (2), unbroken
fill, and the glyph is NOT clipped by the erase.

ECH rather than "n spaces, then CUB(n)", which also works and was tried first:
the spaces are visible CHARACTERS, so every width measured after compensation —
`strippedLength` above all — inflates by the width of each emoji on the line.
ECH writes none.

Also measured, on the same run: an ECH-compensated cluster, a natively 2-cell
cluster (`📁`), and plain ASCII each put the character AFTER them in the same
column. The layout arithmetic is exact; what remains is only how Apple's font
paints a narrow glyph inside the two cells it owns.

#### The skin-tone path needed the same erase — FIXED 2026-08-26

The erase above was added to the branch that handles under-advancing clusters.
Terminal.app's walk has a *second* branch, for the clusters that OVER-advance:
a Fitzpatrick cluster on a text-default base (`☝🏽`) has its modifier stripped
and `U+FE0F` restored, so that the base still paints the two cells the layout
claimed. That restoration turns the cluster into a VS-16 pictograph — which is
to say, into exactly the paint-2/advance-1 case the first branch exists for —
and it was emitting `CUF` with no `ECH`.

**Measured** (Terminal.app 455.1 / macOS 15.7.9, 2026-08-26, six `☝🏽` on a
blue run, `DECDWL` so a one-cell hole is unmistakable in a capture):

| output | advance per cluster | the cells the glyph covers |
|---|---|---|
| `☝️` + `CUF(1)` (what shipped) | 2 | a white cell after every hand |
| `ECH(2)` + `☝️` + `CUF(1)` | 2 | unbroken blue |

Same defect, same remedy, same advance — the erase was simply missing from one
of the two places that produce an under-advancing glyph. The affected clusters
are the nine text-default emoji-modifier bases, five tones each: `☝ ⛹ ✌ ✍ 🏋
🏌 🕴 🕵 🖐`. Emoji-default bases (`✊🏻`) are unaffected: they are stripped bare
to a glyph that already advances as far as it paints, so there is nothing for an
erase to fix, and the walk must not emit one for them.

Found by sweeping `TerminalQuirks` — the open switch set the
`TerminalClientQuirks` app exports — against the hand-written per-host model
and diffing the emitted bytes over 46,073 clusters. The two are independent
encodings of the same measurements, so anywhere they disagree, one of them is
wrong; this was the only disagreement Apple Terminal had.

#### …and on a FULL-WIDTH row, which is the case an app actually draws

The report that prompted the section above had a second half — the row also
appearing to sit one cell left, borders and scrollbar included — and a short
line cannot ask that question: `FrameDiffWriter.repaintRightEdge` documents a
family that consumes more line budget than it claims and WRAPS, and a row padded
to the terminal's exact width is where that would show.

**Measured** (`Tools/TerminalProbes/row_probe.py`, `PROBE_ALT=1`, Terminal.app
455.1 / macOS 15.7, 80 columns). Each row carries one cluster and is padded to
four cells short of the edge, where the cursor is read — at the edge itself it
CLAMPS, and reports the same column whatever the row spent:

| row | end column | verdict |
|---|---|---|
| `📁`, no compensation | 77 | the reference |
| plain ASCII | 77 | the reference |
| `⚙️` + `CUF(1)` | 77 | correct |
| `⚙️` + `ECH(2)` + `CUF(1)` | 77 | correct |
| `⚙️` **bare** | **76** | one cell short |
| `🖥️` bare | **76** | one cell short |

Nothing wrapped, in any case. So a full-width row spends exactly what it claims,
both compensation strategies are exact, and **the one-cell shift is what an
UNCOMPENSATED emission looks like**.

##### Which is what it was — FIXED 2026-08-24

The shift WAS seen, on Terminal.app, and the table above is what identified it:
the bytes were uncompensated, so the question was which path emitted them
without a model rather than which model was wrong. The report named the path
precisely — the row drew correctly when it was selected and wrong on every
frame afterwards.

Only the FIRST of those frames is built by `FrameDiffWriter`. The rest are the
animation replay (`RenderLoop.replayAnimations`), which advances a pulsing row
by splicing the run's current picture into the row already on screen — and a
run's frames are content as the view rendered it, which has never been through
the host's advance model, because the model lives in the builder the replay
exists to skip. So a focused `⚙️ .swiftlint.yml` painted correctly once and then
shifted a cell left, at the pulse rate, for as long as it stayed focused.

The splice now goes through `FrameDiffWriter.patchingAnimatedRun`, which
compensates the frame first. The compensation writes no visible characters
(ECH and CUF, per the section above), so the run still claims the cells it
claimed and the splice arithmetic is untouched.

**The general rule this is an instance of:** every byte that reaches the
terminal passes through this file's advance model exactly once. Any future path
that writes without going through `FrameDiffWriter` — a partial repaint, a
direct cursor-addressed write — owes the same, and will show the same one-cell
shift if it does not. A host with no model here (the `else` arm) legitimately
receives uncompensated bytes; if the shift is seen on such a terminal, that
terminal is one to measure and add.

### Bare (selector-less) pictographs — FIXED 2026-07-14

**Not to be confused with `🖥️`** (U+1F5A5 **+ U+FE0F**) — the form the demo
app and virtually all real text uses, and which has always been correct on
all four terminals (Apple/iTerm2 under-advance it and the CUF fixes it;
Ghostty/Warp advance it natively). **This section is the BARE form**, no
variation selector: a different grapheme cluster.

`terminalWidth` ended with a blanket `0x1F000...0x1FBFF → 2` rule (narrowed
2026-08-26 — see below), so a bare 🖥 claims 2. Advance is 1 on **every** terminal, and no model said so — a
single scalar cannot trip `isVS16UnderAdvancer`, so each model fell through
to `terminalWidth` and reported 2, contradicting its own probe data. Model
== claim ⇒ no CUF ⇒ the row sheared one cell left.

**Both halves measured 2026-07-14** — advance by DSR (`advance_probe.py`),
paint by eye (`Tools/TerminalProbes/visual_card.py`, a `|<c>|<c>|<c>|X` row: if the closing pipe
survives the glyph painted 1):

| Class | Example | `isEmojiPresentation` | Claim | Advance | Paint (Apple) |
|---|---|---|---|---|---|
| BMP text-presentation | ✏ ❤ ☝ ☂ ✔ ☎ | false | 1 ✓ | 1 | 1 ✓ |
| SMP text-presentation | 🖥 🛡 🕹 🕷 🎞 🏙 | false | 2 | 1 | **2** |
| SMP emoji-presentation | 👍 🀄 | true | 2 ✓ | 2 | 2 ✓ |
| In-block non-emoji | 🁠 🂡 🬀 🜀 | false | 1 ✓ | 1 | 1 ✓ |

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

**The in-block non-emoji row — FIXED 2026-08-26.** These claim 1 now. The
row above stood open on the reasoning that narrowing the blanket rule was
risky, because the same range holds U+1F200–1F2FF (Enclosed Ideographic
Supplement, 🈁 🈚) which IS East Asian Wide and mostly NOT emoji, so gating on
`isEmoji` alone would wrongly drop those to 1. That hazard is real and the
measurement resolves it exactly.

**Measured 2026-08-26** over **all 1361 assigned non-emoji scalars** in
U+1F000–1FBFF, by DSR on Terminal.app 455.1 and Ghostty 1.3.1 — two terminals
that disagree about almost everything else and agree here on every single
scalar:

| | count |
|---|---|
| advance 1 | 1312 |
| advance 2 | 49 |
| host disagreements | **0** |

and all 49 wide ones are U+1F200–U+1F2FF, with no narrow scalar inside that
block and no wide one outside it. So the split is a clean range boundary,
which is what makes the narrowing safe:

```
0x1F200...0x1F2FF                    → 2   (Enclosed Ideographic Supplement)
0x1F000...0x1FBFF, isEmoji           → 2   (Apple Color Emoji fallback paints 2)
0x1F000...0x1FBFF, otherwise         → 1
```

The earlier note also **understated the reach**: it read as dominoes and
playing cards only (U+1F000–1F0FF). The affected set is 1312 scalars across
47 runs, and includes the Enclosed Alphanumeric Supplement (🅲), ornamental
dingbats (🙐), alchemical symbols (🜀), Supplemental Arrows-C (🠀), chess
(🨀) and — the most damaging — **Symbols for Legacy Computing** (U+1FB00–1FBF9,
🬀), which are block graphics, siblings of the U+2500–259F chrome the width
model already fast-paths to 1 cell. A framework that draws with block
graphics was claiming two cells for a quarter of them.

Verified end-to-end on all five hosts: rows of mahjong, dominoes, cards,
legacy-computing, alchemical, chess, Supplemental-Arrows-C, Enclosed
Ideographic and a mixed ASCII/CJK/emoji row were emitted through each host's
real compensation path and DSR-measured — **claimed width == measured advance
in all 50 checks**. It moved no golden snapshots.

With the claim corrected, `tmuxCursorAdvance`'s broader rule became dead
weight — it existed only to return 1 for scalars the claim had wrongly put at
2 — and now consults `isBarePictographUnderAdvancer` like the other four.

**SF Symbols PUA** is a third claim-vs-advance mismatch (no terminal advances
2) but is already handled: Apple/iTerm2 genuinely paint 2, so the claim is
right and the CUF is correct; only Ghostty paints 1 and takes the blank cell.

### ZWJ: where DSR lies, and where the defect actually is — measured 2026-08-26

Every advance number in this document comes from DSR (`ESC[6n`), and for ZWJ
sequences on Terminal.app **DSR is not telling the truth**. This was recorded
for a year as "Terminal.app badly over-advances ZWJ, rows will shear here,
known limitation". Rows do not shear. The measurement was right and the
conclusion drawn from it was wrong.

**The probe that settles it** draws three copies of a cluster separated by
pipes and terminated by an `X` — `|<c>|<c>|<c>|X` — on every host, and asks
where the `X` lands *on screen*. A cluster that occupies more cells than
claimed pushes the `X` right; one that occupies fewer pulls it left. Paint,
not report.

| host | composes a ZWJ cluster? | painted cells | DSR says | rows shear? |
|---|---|---|---|---|
| Terminal.app 455.1 | yes, one glyph | **2** | 5 / 8 / 11 | **no** |
| iTerm2 3.6.11 | yes | 2 | 2 | no |
| Ghostty 1.3.1 | yes | 2 | 2 | no |
| tmux 3.7b | yes (own grid) | 2 | 2 | no |
| Warp 2026.07 | **no — draws the components** | **4–11** | 4–11 | **yes** |

On Terminal.app the astronaut, the four-person family, the England tag flag,
👍 and 中 all put their `X` in the **same column**, though DSR claimed 21, 39,
30, 12 and 12 for those rows. The composed glyph is two cells and printing
resumes two cells along; only the *report* runs ahead.

**So the defect is Warp's, not Terminal.app's.** Warp does not compose ZWJ at
all: 👩‍🚀 draws as 👩 then 🚀, 👨‍👩‍👧‍👦 as four separate people. There paint
and advance agree with each other and disagree with TUIkit's claim of 2, so
every row carrying a ZWJ emoji really does shift right. Warp composes tag
sequence flags correctly (🏴󠁧󠁢󠁥󠁮󠁧󠁿 lands with the controls), so that class is fine
everywhere.

**Still unhandled, and now correctly scoped.** A Warp ZWJ cluster cannot be
fixed with `CUF`: paint equals advance, so there is no gap to close. The
remedies are a host-dependent width claim — which the whole model is built to
avoid, since a claim must be host-independent — or a skin-tone-style
substitution down to the first component. Neither is obviously worth it for a
class TUIkit's own chrome never emits, so it stays documented rather than
fixed. What has changed is that the cost is now known: it is one host, not
two, and it is Warp.

**Methodology, which this changes.** `Tools/TerminalProbes/advance_probe.py`
measures with DSR and is the source of every number in the advance table.
Those numbers are still correct *as cursor reports*, and for every class in
this document other than ZWJ they also match the paint. ZWJ is the one place
they come apart, so:

> A DSR advance that disagrees with the claim is a *hypothesis* about
> rendering, not a finding. Confirm it by drawing — `|<c>|<c>|<c>|X` and look
> at the column — before compensating for it.

The same discipline had already caught one error in the other direction: the
in-block non-emoji row above (🀀 🁠 🂡) was assumed to paint 2 and under-advance
until a paint test showed it painting 1, which turned a proposed `CUF` into a
width fix. Two classes, two wrong conclusions from advance alone, in opposite
directions.

**A residual, genuinely broken:** VS-16-leading ZWJ (❤️‍🔥 ⛓️‍💥 🏳️‍🌈) on
Terminal.app *does* misbehave visibly — in the same probe its separating pipes
were overpainted and the `X` landed left of the others. It is the one ZWJ
sub-class where Terminal.app's report and its paint agree that something is
wrong. Small, and unhandled as before, but real — unlike the rest of the class.

## Keyboard modifiers on key events

Recorded 2026-07-27 alongside `KeyboardShortcut`'s key-equivalent support.
Read this before designing any binding that depends on a modifier.

### Command is never reported

No terminal forwards the Command key on a **key** event. `⌘S` cannot arrive.
This is why `CommandKeyBinding` exists: SwiftUI source says `⌘S`, and an app
states once at its root which terminal modifier stands in for it
(`.commandKey(.control)`), rather than every shared shortcut being rewritten.

Note the asymmetry with **mouse** reports, where the meta bit is real but means
different things: iTerm2 forwards ⌘ as meta, Apple Terminal forwards ⌥ (see the
mouse sections above). The standing rule from that measurement holds here too —
never design around one specific macOS modifier key being available.

### Shift on a printable key is the character, not a bit

A terminal sends a shifted printable as the shifted **character** with no
modifier bits: "A" is one byte, 0x41, and `KeyEvent.parse`'s printable branch
builds `KeyEvent(character:)` with `ctrl`/`alt`/`shift` all false. There is no
shift flag to read.

So a shortcut's Shift has to be derived from case, both when it is declared and
when a key arrives. `KeyboardShortcut` does exactly that: `KeyEquivalent("A")`
normalises to `"a"` + `.shift`, and matching sets `.shift` from
`character.isUppercase` and ignores `event.shift`. Trusting the flag instead
would leave `("a", [.shift])` permanently dead while `("a", [])` fired for "A"
as well.

The flag IS meaningful on **non-printable** keys (arrows, function keys), where
it arrives in the CSI parameters — and there it is unreliable in a different
way: Apple Terminal sends bare `ESC[A`/`ESC[B` for Up/Down, dropping every
modifier, while keeping them on Left/Right. A Shift+Up binding therefore cannot
work in Apple Terminal. That is a terminal limitation, not a framework bug.

### Option arrives in two different spellings

Recorded 2026-08-13, while making ⌥←/⌥→ collapse and expand an outline
recursively.

A terminal set to treat **Option as Meta** does not report it in xterm's Alt
bit. The CSI modifier parameter is `1 +` a bitfield whose bits are
`1`=Shift, `2`=Alt, `4`=Ctrl, `8`=**Meta**, and Option-as-Meta lands in that
fourth bit — so the same keypress reaches an app as either of:

| Spelling | Bytes for ⌥→ | Sent by |
|---|---|---|
| xterm Alt bit | `ESC[1;3C` | terminals that report Option as Alt |
| xterm Meta bit | `ESC[1;9C` | terminals configured "Option as Meta", CSI form |
| ESC prefix | `ESC ESC[C` | the same setting's other encoding ("Esc+") |

TUIkit has no `meta` flag on a **key** event (unlike `MouseEvent`, where the
bit is real and the sections above measure what each terminal puts in it), and
there is no separate Meta key on a Mac keyboard for the bit to mean instead.
So `KeyEvent.parse` folds Meta onto `alt`, and all three spellings above decode
to the same `KeyEvent`. The ESC-prefixed form always did; the CSI Meta form did
not until now, and a ⌥-chord sent that way arrived as the **bare key** — the
modifier looked ignored rather than undelivered, which is the worse failure of
the two because the unmodified action happens instead.

*Not yet captured (2026-08-13):* **what Apple Terminal actually sends for
⌥←/⌥→.** The parser change above was verified against all three spellings by
feeding them to a real app through a PTY — that part is measured — but which
spelling (if any) Apple Terminal emits was not. Its shipped key map is believed
to bind that pair to `ESC b` / `ESC f`, the Emacs word-motion pair, which would
decode as **alt+`b`** / **alt+`f`** and never reach an app as arrows at all;
that is an expectation from the profile's Keyboard tab, not a byte capture, and
the parenthetical belongs in this section only once someone has run `cat -v` in
Terminal.app and pressed the two chords. Do that before relying on either
reading. The same run should cover iTerm2, Ghostty and Warp, whose Option
handling is a per-profile setting in each ("Esc+" vs "Meta" vs "Normal").

Either way the framework's rule stands on its own: **a ⌥-arrow binding must be
an accelerator, never the only route.** `OutlineGroup`'s recursive disclosure
follows it — plain Right and Left reach every branch one level at a time on
every terminal, and Option only makes that faster where the chord survives.

#### Option + Control + a letter (recorded 2026-08-20)

Select-all in the text controls is **⌥⌃A**, and it is the one binding in the
framework that deliberately breaks the accelerator rule above: there is no
other route to it. That was a decision made with the trade-off stated — "I know
that won't work in some terminal clients by default, but that's okay; I don't
want to move it even further away from the platform canonical shortcut
(⌘A)" — and ⌘A cannot reach a terminal app at all.

The bytes, for a terminal in "Esc+" mode:

| Chord | Bytes | Decodes to |
|---|---|---|
| ⌃A | `0x01` | `.character("a")`, ctrl |
| ⌥⌃A | `ESC 0x01` | `.character("a")`, ctrl + alt |

The second is the ESC-prefix spelling applied to a C0 byte rather than to a CSI
sequence, and `KeyEvent.parse` already handled it: a two-byte `ESC <byte>`
recurses into the single-byte path, which maps 0x01–0x1A back to a letter with
`ctrl: true`, and the ESC contributes `alt: true`. No new modifier flag was
needed — verified through a PTY.

*Not yet captured:* **which spelling each terminal emits for ⌥ + a C0 chord.**
This is the same survey the section above still wants, now with a second reason
to run it. A terminal in "Normal" Option mode will send the letter's ⌥-composed
character instead (⌥a is `å`), which decodes as a plain character and inserts
it; a terminal in "Meta" mode sets the high bit. Neither reaches the binding.
Run `cat -v`, press ⌃A and then ⌥⌃A, in Terminal.app, iTerm2, Ghostty and Warp,
and record the four pairs here.


### Control collides with the C0 range

`Ctrl`+letter arrives as 0x01–0x1A and `KeyEvent.parse` maps it back to the
lower-case letter with `ctrl: true` — but only for the letters the C0 range has
not already spent:

| Combination | Arrives instead as | Why |
|---|---|---|
| Ctrl-I | Tab | 0x09 is HT, matched before the Ctrl range |
| Ctrl-J | Enter | 0x0A is LF |
| Ctrl-M | Enter | 0x0D is CR |
| Ctrl-[ | Escape | 0x1B, outside the 0x01–0x1A range |
| Ctrl-C, Ctrl-Z | — | taken by the shell's job control |

These cannot be delivered under `.commandKey(.control)` by any means. Ask
`KeyboardShortcut.isDeliverableInTerminal` (after `resolved(commandKey:)`)
rather than wondering why one menu item is dead. `.commandKey(.option)` has no
such collision, at the cost of Option itself being less reliable: Apple
Terminal composes accented characters unless "Use Option as Meta key" is on.

### Shifted function keys are re-coded (Apple Terminal)

Measured 2026-07-27, `cat -v` in Terminal.app 2.14 (455): **Shift+F10 emits
`^[[32~`**, not the `ESC[21;2~` that xterm, iTerm2, Ghostty and Warp send.
Terminal.app has no modifier parameter for function keys in either direction;
its key map instead substitutes a *different* key:

| Chord | Apple Terminal sends | Which is really | Everyone else sends |
|---|---|---|---|
| Shift+F5 | `ESC[25~` | F13 | `ESC[15;2~` |
| Shift+F6 | `ESC[26~` | F14 | `ESC[17;2~` |
| Shift+F7 | `ESC[28~` | F15 | `ESC[18;2~` |
| Shift+F8 | `ESC[29~` | F16 | `ESC[19;2~` |
| Shift+F9 | `ESC[31~` | F17 | `ESC[20;2~` |
| **Shift+F10** | **`ESC[32~`** | **F18** | `ESC[21;2~` |
| Shift+F11 | `ESC[33~` | F19 | `ESC[23;2~` |
| Shift+F12 | `ESC[34~` | F20 | `ESC[24;2~` |

(The VT220 block is 25–34 with 27 and 30 unassigned, which is where the gaps
come from. Option+Fn is aliased the same way onto F(n+5).)

The collision is unresolvable from the bytes, so TUIkit picks the reading that
is reachable on a Mac keyboard: **on Apple Terminal only**, `Terminal.finalize`
rewrites a decoded F13…F20 as Shift+F5…Shift+F12
(`KeyEvent.normalizingLegacyShiftedFunctionKeys()`). Elsewhere those sequences
stay F13…F20, which is what a keyboard that has those keys means by them.

Deliberately NOT normalised: Apple Terminal's **Option**+Fn aliasing. Its
collision partner is the plain F6…F12 that people press all the time, so
rewriting it would cost more than it buys.

This is why `.contextMenu`'s Shift+F10 route appeared dead: the binding was
correct, but `parseExtendedKey` stopped at 24, so `ESC[32~` decoded to nothing
and never became an event at all.

## Mouse button codes: bit 7 means two different things

The SGR button code packs modifiers and group bits around a two-bit button
number, and **bit 7 (`+128`) is overloaded**:

| Code | With bit 6 (wheel) set | Without it |
|---|---|---|
| `+128` | horizontal wheel — the form some terminals use instead of buttons 66/67 | xterm's extended button **group 8–11** |

Both forms are real and both are in the wild, so the reading depends on the
wheel bit. Buttons 8–11 are a five-button mouse's back/forward pair plus two
more with no agreed meaning; they are numbered in the *same low two bits* that
mean left/middle/right, so a decoder that ignores bit 7 outside the wheel group
turns a press of "back" into a left click wherever the pointer happens to be.
TUIkit has no notion of those buttons and declines the report
(`MouseEvent.decodeSGRButton`); the horizontal-wheel reading is unaffected.

Not measured per terminal — this follows xterm's `ctlseqs` definition rather
than an observation, and no terminal surveyed here was seen to send 8–11 during
the probes (no five-button mouse was attached).

## Where the adaptations live

- `TerminalHost` — `TERM_PROGRAM` detection (`Apple_Terminal`,
  `iTerm.app`, `ghostty`, `WarpTerminal`) + the `supportsEmojiChrome`
  allowlist (all four; Ghostty only because its CUF fixes the VS-15
  under-advance).
- `Character.terminalAppCursorAdvance` / `.iTerm2CursorAdvance` /
  `.ghosttyCursorAdvance` / `.warpCursorAdvance` — the per-host advance
  models (TUIkitCore), each pinned to the table above by
  `GhosttyWarpCompatibilityTests` / `StringTerminalWidthTests`.
- `KeyEvent.normalizingLegacyShiftedFunctionKeys()` +
  `Terminal.finalize` — Apple Terminal's shifted-function-key re-coding
  (F13…F20 read back as Shift+F5…F12), gated on `TerminalHost.isAppleTerminal`.
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
- `ToggleCharacterSet.automatic` + `SwitchIndicatorGlyphs` — chrome glyph
  selection per host.

### SGR codes the output path emits (recorded 2026-08-20)

`String.collapsingAdjacentSGR()` states a line's styling once and then emits
each subsequent change as a **delta** from the state it last established, not
as a reset-prefixed absolute. That narrows the emitted vocabulary to codes
that must be safe on every host in this document, so the set is worth writing
down:

| Codes | Used for | Portability |
|---|---|---|
| `0` | the line's first statement, and any attribute-off | universal |
| `1 2 3 4 5 7 8 9` | attributes ON | universal |
| `30–37 90–97 38;5;n 38;2;r;g;b` | foreground | per the depth rules above |
| `40–47 100–107 48;5;n 48;2;r;g;b` | background | per the depth rules above |
| **`39` / `49`** | foreground / background back to the terminal's own | ECMA-48 core; present in every host here, in tmux, and in the Linux console |

The codes deliberately **not** emitted are the attribute-*off* ones —
`21 22 23 24 25 27 28 29`. `21` is the reason: ECMA-48 assigns it
double-underline and several terminals read it as bold-off, so the two
readings disagree about what a line looks like afterwards.
``SGRState/rendered(changingFrom:)`` therefore declines to turn an attribute
off by delta at all and restates from `ESC[0m`, which every terminal agrees
about. (``SGRState/apply(_:)`` still *honours* both readings when parsing,
because there the conservative direction is the opposite one — treating an
off-code as a no-op would leave styling on that the source cleared.)
