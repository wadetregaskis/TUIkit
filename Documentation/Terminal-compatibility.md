# Terminal compatibility survey

The canonical record of how each terminal emulator behaves on every axis
TUIkit cares about — input encodings (keys, mouse, trackpad) and output
behaviour (cursor advance vs painted width, emoji handling, glyph cell
coverage, colour depth, OSC 8 hyperlinks, graphics protocols) — plus the
environment variables each one defines and the exact versions the observations
were made against.

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

Two structural rules hold everywhere in that machinery:

- **The advance MODELS state raw-cluster truth, ungated.** Only the WALKS
  (and the claims) are gated on `TerminalWidthTraits`. A model gated on the
  traits silently reverts to the claim when a widening is turned off — it
  happened, and the conformance suite could not see it because a
  self-consistent model passes conservation while being wrong about the
  terminal. Where a walk rewrites a cluster, the raw cluster's model keeps
  an explicit arm anyway (`TerminalLedgerConformanceTests` checks it against
  the committed records).
- **Every emission must net the cursor to the claim** (the conservation
  law, `CursorAdvanceConservationTests`) — and consistency is not
  correctness, which is why every model value must also trace to a record
  under `Tools/TerminalProbes/data/`.

**Terminals covered:** Apple Terminal.app, iTerm2, Ghostty, Warp, tmux
(all measured). Jump to the
[measured advance table](#measured-advance-table-divergences-and-key-rows)
for the one-screen comparison.

## Methodology

> **CORRECTED 2026-08-27, twice — the first correction was itself wrong.**
> The original text below called advance "the ground truth for layout". A first
> correction swung to the opposite pole — "advance is not ground truth, paint
> is" — rebuilt the Apple Terminal model on paint alone, and shipped the
> mirror-image defect within a day: every full-width row carrying a skin tone
> wrapped, leaving default-white cells at its right edge, because the internal
> column the models no longer tracked is what decides when a row wraps.
>
> The truth is that **both counters are load-bearing and compensation must end
> each cluster with both at the claim**: the internal column (DSR) governs
> wrapping and how far a row's writes are accepted; the paint position governs
> where glyphs land. On iTerm2, Ghostty and Warp they agree for every corpus
> cluster, so the distinction is invisible; on Apple Terminal they diverge on
> 25, by up to nine cells. See [Three numbers, not one](#three-numbers-not-one).
>
> **EXTENDED 2026-08-27, the same day, by the treatment cards:** there is a
> THIRD per-row fact — the cluster's **stored width** in the row's text store —
> and it, not the cursor, decides where everything *later* on the row paints,
> absolutely-addressed writes included. A cluster stored wider than it paints
> (a flag pair: 2 painted, one surplus column; a composed ZWJ sequence under
> any cursor-move repair) displaces the whole tail left, and no cursor move
> repairs that, because cursor moves do not edit the store. Backward moves are
> worse than useless here: **any backward cursor motion over a composed
> cluster makes this terminal re-render it as its bare first segment** — the
> tone or the sequence survives in the store and dies on screen. The shipped
> treatments (see the Apple Terminal section) all make stored width == painted
> width == claim: rewrite (ZWNJ separation), decompose (ZWJ), or delete the
> surplus stored column (`DCH` — flags, keycaps).

### Four numbers, not one

A cluster has four different measurements and this project has, at various
times, mistaken each for another:

| number | measured by | what it governs |
|---|---|---|
| **advance** | DSR (`ESC[6n`) | the terminal's own bookkeeping |
| **landing** | pixels | **where the next character is drawn** — row alignment |
| **ink** | pixels | how many cells the glyph covers — gaps and overlap |
| **reserve** | the wrap test | whether the row wraps early |

`advance` and `landing` are BOTH load-bearing, for different failures: a walk
that leaves the internal column past the claim wraps every full-width row that
carries the cluster (white cells at the row's right edge — measured, and
briefly shipped); one that leaves paint short of the claim shears the row.
`landing` is the one no escape sequence will tell you. On iTerm2, Ghostty and
Warp the two are equal for all 69 corpus clusters; on Apple Terminal they
differ for 25.

The displacement is **row-wide, not local**: on a row already carrying 🤙🏽, an
absolute `CUP` to column 50 paints at column 48. Every later cell on the row
inherits the whole accumulated error, which is why a single skin-toned emoji
moves an enclosing border two cells left.

Compensation moves BOTH counters, and must also respect the STORE. `CUF(n)`
moves internal and paint by exactly `n`. `CUB(n)` moves internal by exactly
`−n` — and what looks like "paint snapping to the internal column" is the
terminal re-rendering the cluster as its bare first segment, which is how a
CUB pull-back silently strips a skin tone on screen (treatment cards,
2026-08-27). Even where a pull-back aligns, a cluster whose stored width
differs from its painted width displaces every LATER write on the row —
sequential or absolutely addressed — by the difference, which cursor moves
cannot repair. Hence the shipped per-class treatments: rewrite as base + ZWNJ
+ modifier (every Fitzpatrick cluster — the one separator the terminal does
not re-join, with a text-presentation base VS-16-promoted first, 2026-08-28),
software decomposition (ZWJ sequences), and `CUB(1)` `DCH(1)` `CUF(1)` store
surgery (FE0F keycaps and flag pairs; a BARE keycap is pulled back instead). Every emission was
verified in the terminal itself: follower and absolute-move alignment,
background integrity, and a full-width row ending in the cluster with no wrap.
A claim must never be narrower than the landing —
`TerminalLedgerConformanceTests` asserts that — and no emission may leave the
internal sum above the claim — `CursorAdvanceConservationTests` sums exactly
that, and catches both halves of the briefly-shipped defect under mutation.

### Measuring paint

`landing_probe.py` prints a cluster, lets the terminal put a magenta marker
wherever it thinks the cursor is, and screenshots the result;
`landing_analyze.py` reads the marker's column out of the pixels. The reading is
arithmetic, not judgement — this project has a poor record of interpreting
screenshots by eye, and every conclusion in this section that had to be
corrected was corrected by a program looking at the same picture.

The instrument checks itself in two ways, both of which caught real errors:

- **A self-check marker** at a column the probe chose, with nothing in front of
  it. If the analyser cannot read that column back exactly it aborts rather than
  report numbers off a mis-derived grid.
- **Control clusters** whose landing is known before any terminal is asked
  (ASCII is 1, East-Asian-Wide is 2). iTerm2 read uniformly +1 on these,
  including for `a`; taking that as a terminal behaviour would have "corrected"
  all 69 clusters on a host that gets every one of them right.

Five bugs in the instrument were found this way, each of which produced
confident, plausible, wrong numbers: reading the marker's left edge (a wide
glyph's ink spills into it, biasing every skin-tone reading), bounding `ink` by
`landing` (they then agree by construction), measuring `ink` further along the
same row (it inherits the displacement being measured), calibrating off a
stale window from an earlier run, and — found 2026-08-28 — **screenshotting a
page with the cursor still on it**.

That last one is worth stating plainly, because it is the reason this section
used to say `ink` could not be trusted. The probe draws each cluster a second
time on its own row to measure ink, and then simply stopped: the terminal left
a block cursor sitting immediately after the *last* cluster on the page, inside
the eight-cell ink window, and `ink_cells` reports the **rightmost** inked cell.
So exactly one row per page — whichever cluster happened to fall last — read
`ink == advance + 1`, describing the cursor rather than the glyph. It was
invisible precisely because it was rare, self-consistent, and moved: which
cluster it hit depends on where the page breaks fall, so growing the corpus
changed the answer for a host whose rendering had not changed at all.

The probe now hides the cursor (DECTCEM) and parks it on the self-check row.
Re-measuring all four hosts afterwards moved **only** `ink`, and only on
last-on-page rows — `advance`, `landing` and `reserve` are DSR- and
wrap-derived and were identical to the cell — which is what a fix for this
specific fault should look like. Seven committed values were wrong:
`combining_acute` on all four hosts (2 → 1, its true one cell), and on Apple
Terminal `partying` (3 → 2), `vs16_wavy_dash` (3 → 2), `zwj_astronaut`
(6 → 2) and `tone_thumbsup` (5 → 2).

`ink` is still recorded but **not asserted on** — it remains a coverage
threshold over an antialiased glyph, and a genuine over-ink (Apple paints
⏩ ⏪ ⏫ ⏬ into three cells) is a real reading rather than a bug. But the
specific evidence this document cited for distrusting it — "it puts 👍🏼 at five
cells on a host where it composes into about two" — was the cursor, not the
threshold. That host puts 👍🏼 at two.

Every probe result is written with a provenance stamp (`probe_stamp.py`) and
the curated ones are committed under `Tools/TerminalProbes/data/`, one file per
terminal, version and screen buffer. The stamp records the two conditions this
document has twice been bitten by leaving out — **which screen buffer**, and
**whether DEC mode 2027 was set** — because a number without them cannot be
re-read later and either trusted or discarded. See `data/README.md`.

Records are produced by running a probe, never by editing a file: that is the
only mechanism that keeps "contributing a measurement" and "making one" the
same act.

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

Since 2026-08-28 the switches can express **every** measured host: all four
native shapes are pinned to their real walks emission-for-emission by
`TerminalQuirksTests`, with no skipped rows. That pin is the point of the
app — what an explorer dials in is exactly what TUIkit would emit once the
model was written down — and it only became true when the mirror grew the
four mechanisms the real walks already had: claiming the detached skin-tone
swatch (for every base, or only a BMP one), merging a tone into a narrow
text base's single cell, a width table cut before Unicode 16.0, and keycaps
that advance a fixed 2 whichever spelling arrives — which the FE0F form's
claim meets and the bare form's one-cell claim does not, so only the bare
one is repaired.

"Advance" below = cells the cursor moves; "paints" = cells with ink.
TUIkit's shared layout width (`Character.terminalWidth`) claims 2 for all
the emoji-class clusters below unless noted.

---

### The framework's own chrome — advance and ink measured 2026-09-04

Until 2026-09-04 the width corpus had 116 rows for every class of cluster
someone's *data* might contain and none for a glyph TUIkit itself draws. Every
keyboard symbol the status bar emits (`⎋ ↵ ⏎ ⇥ ⇤ ⌫ ⌦ ␣ ↑ ↓ ← → ⇧ ⌃ ⌥ ⌘`) and
every glyph its borders, scrollbars, tracks, radio buttons, steppers and
disclosure triangles are made of (`◀ ▶ ▼ ▲ ● ◯ ◌ █ ▌ ▐ ▒ ─ │`) was claimed at
one cell on trust. Fifteen of the twenty-nine are East Asian **Ambiguous**,
whose width is a terminal SETTING rather than a property of the character, so
the claim was not obviously safe — and a border glyph measured wrong moves
every cell of every row inside it.

**Measured on all four hosts: every one of the twenty-nine advances exactly one
cell.** Ghostty 1.3.1, iTerm2 3.6.11, Apple Terminal 455.1 and Warp
v0.2026.09.02 agree with each other and with the claim, with no Ambiguous-width
divergence anywhere. (The *ink* is a separate question with a different answer —
eight of the rows paint two cells while advancing one, and not the same eight on
every host. See "The ink half" below.) Records:
`Tools/TerminalProbes/data/{ghostty-1.3.1,iTerm2,Apple-Terminal,Warp}-advance.json`,
asserted by `ChromeGlyphAdvanceTests`.

What remains open for these rows is `landing` — where the glyph is painted
relative to its neighbours — which needs pixels rather than DSR. They stay in
`TerminalLedgerConformanceTests.awaitingLandingMeasurement` until then. The
`ink` half is answered below.

#### The ink half: card-read 2026-09-04, and it is PER HOST

A chrome glyph can paint two cells while advancing one — the grid intact, the
ink over the line — and that is what the `↵` report from Ghostty was: the
status bar's `Shortcut.enter` swallowing the space before its label, so
`↵ activate` reads as `↵activate`. DSR cannot see it, because nothing moved.

**Instrument:** `Tools/TerminalProbes/overhang_card.py`, run inside each host
and **read by a person**. It draws each of the 29 `chrome_key`/`chrome_glyph`
rows in ONE cell between two flanks of solid magenta; ink on a flank is
overhang, and which flank says which way. Two calibration rows (`█` must meet
both flanks, `a` must clear them) say whether the card is legible on the host
before any row under it is believed. This is a **paint** measurement of the
kind a screenshot would give, not a DSR reply — the machine version
(`landing_probe.py`) needs a Screen Recording grant this project does not
have — so it carries a person's judgement where the advance records carry a
terminal's own number.

**Read 2026-09-04** on Apple Terminal 455.1, iTerm2 3.6.11, Ghostty 1.3.1 and
Warp v0.2026.09.02:

| Glyph | Codepoint | Corpus row | Apple Terminal | iTerm2 | Ghostty | Warp |
|---|---|---|---|---|---|---|
| `↵` | U+21B5 | `key_return` | — | — | **overhangs** | — |
| `⎋` | U+238B | `key_escape` | — | — | — | **overhangs** |
| `⏎` | U+23CE | `key_return_symbol` | — | — | — | **overhangs** |
| `⌫` | U+232B | `key_backspace` | — | — | — | **overhangs** |
| `⌦` | U+2326 | `key_delete` | — | — | — | **overhangs** |
| `␣` | U+2423 | `key_space` | — | — | — | **overhangs** |
| `⌥` | U+2325 | `key_option` | — | — | — | **overhangs** |
| `⌘` | U+2318 | `key_command` | — | — | — | **overhangs** |

Every other chrome row is contained on every host: `⇥ ⇤ ↑ ↓ ← → ⇧ ⌃`, and all
thirteen drawing glyphs (`◀ ▶ ▼ ▲ ● ◯ ◌ █ ▌ ▐ ▒ ─ │`) — which is the answer
that mattered most, because a wide claim is never the remedy for a border. The
CJK control `漢` claims two cells and overhangs neither flank on any host, and
the calibration rows read as described everywhere, so the readings under them
stand.

**Recorded caveat: the FONT was not captured with this reading.** Overhang is a
font property at least as much as a host one, and the card's own instructions
ask for the font and its size. What is recorded here is host + version + date,
so a re-run under a different font may disagree — treat a contradicting reading
as a font difference to be recorded, not as this one being wrong.

**The claim follows the host, and that is a departure.** TUIkit's standing rule
is that a claim is host-independent and covers the widest painter, with narrow
painters taking a blank cell — the rule stated for Ghostty's SF Symbols below.
Applied here it would give one table, the union of the eight codepoints above,
and that union is **wrong for 24 of the 32 measured (host, glyph) pairs** —
eight codepoints against four hosts, of which only eight cells of the table
above say "overhangs". A stray blank cell after all eight glyphs on Apple
Terminal and iTerm2 (16), after seven of them on Ghostty, and after `↵` on
Warp. The two overhanging sets are
**disjoint** — Ghostty's one glyph is not among Warp's seven — so no single
claim can be right for both, whichever way it leans. This is the case the
`TerminalWidthTraits` note anticipated when it said such a class "would need
its own measured rule": it has one now, on all four hosts, so the set lives in
`TerminalWidthTraits.chromeOverhang` alongside the other two host-dependent
claims and moves with them (including the cache-invalidating `generation` bump
and the `withTraits(_:)` scoped pin the tests need).

**The mechanism.** A codepoint listed for the host in force claims **two**
cells, every per-host advance model keeps reporting the measured **one**, and
the existing `ECH(2)` + glyph + `CUF(1)` walk squares them — the same treatment
SF Symbols, VS-15 chrome and lone regional indicators already take. The grid
stays exactly where it is; the glyph simply gets a blank neighbour to overhang
into. Four consequences are worth naming because none of them is obvious:

- **An unmeasured host claims one.** tmux and `unidentified` take
  `ChromeOverhang.contained` with every terminal nobody has run the card in.
  Widening there would scatter a blank cell after every shortcut glyph in the
  status bar for a defect nobody has seen on that host — and the two hosts that
  do have it disagree about which glyphs, so there is no majority to guess with.
- **The shortfall is ours, so it is owed by whoever emits under the claim.** It
  is not a terminal's defect but the price of a claim TUIkit widened, so
  `TerminalQuirks` has no switch to turn it off, the empty-quirk-set walk still
  emits it, and an **unidentified** host — which otherwise receives no
  compensation at all — gets `String.withChromeOverhangCompensation()`. Under
  an unidentified host's own traits that walk is the identity; it does the work
  when a diagnostic pinned a measured host's claims. That walk compensates but
  does **not** normalize: the shared walk it borrows also strips a redundant
  VS-16 off a tone cluster and decomposes ZWJ sequences, and those are repairs
  calibrated against the four measured hosts. Handing them to a terminal TUIkit
  could not name would rewrite its content — `☝️🏽` came back as `☝🏽` — which is
  the one thing an unidentified client is documented never to do.
- **The compensation gate stays the UNION of all four hosts.** It decides only
  whether the per-`Character` walk runs, and the walk then asks the claim in
  force per character. Admitting a row whose glyph this host draws contained
  costs a walk that changes nothing; skipping one it smears shears the row. It
  is derived from the tables rather than written beside them, so the two cannot
  drift (`CompensationGateTests`).
- **Box Drawing and Block Elements (`─ │ █ ▌ ▐ ▒`) can never be listed**, and
  the predicate refuses them rather than trusting whoever edits a table. For a
  border glyph a two-cell claim is not a remedy but a second defect: every row
  inside the border loses a column. If one is ever measured to overhang, the fix
  is a different glyph — chrome glyph selection — not a wider claim. The card
  measured all six contained on all four hosts.

`ChromeOverhangTests` holds the matrix — four hosts against 29 rows — so a
reading edited into one host's table cannot silently become every host's.

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

### Ghostty's model is conditional on mode 2027 — measured 2026-08-26

Every Ghostty number in this document was measured with DEC mode 2027
(grapheme clustering) **set**, which is Ghostty's default. Nothing checked
that, and the mode is not a constant.

Resetting it moves six of eleven probed classes:

| cluster | 2027 set | 2027 reset |
|---|---|---|
| 🖥️ VS-16 pictograph | 2 | **1** |
| ⬛︎ VS-15 chrome | 1 | **2** |
| 🇺🇸 flag pair | 2 | **4** |
| 👍🏽 skin tone | 2 | **4** |
| 👩‍🚀 ZWJ | 2 | **4** |
| 1️⃣ keycap | 2 | **1** |
| 🖥 bare pictograph · SF Symbol · 🇦 lone RI · 中 · 👍 | unchanged | unchanged |

In the reset state TUIkit's Ghostty compensation is wrong **in both
directions**: it emits no `CUF` for a VS-16 cluster that now under-advances,
and it emits one for a VS-15 glyph that no longer does. Skin tones, which
Ghostty is the only measured host not to need stripped, over-advance to 4 and
strand two cells.

**And the mode outlives the process.** Measured by resetting it in one program
and reading it back from a separate one launched afterwards: `DECRQM` answered
`ESC[?2027;2$y` and the whole reset-column behaviour was still in force. So
any program that resets mode 2027 and exits without restoring it leaves every
later Ghostty session in a state this document mis-describes — this is not a
hypothetical about user configuration, it is two escape sequences.

**What TUIkit does.** After identification, and only when the host is Ghostty,
it asks `DECRQM` and — if the answer is "supported, and off" — sets the mode
and restores it on exit. Silence, "not recognised" (`0`) and "permanently
reset" (`4`) all leave the terminal alone, per the governing rule.

The gating is not incidental. `DECRQM` is `CSI ? Ps $ p`: a private-parameter
marker *and* an intermediate byte, which is exactly the shape Apple Terminal
prints instead of consuming (see the CSI rule above). Asking blind would put a
stray `p` on the user's shell. `Tools/Smoke/mode_pin_smoke.py` pins both
halves — asked only of Ghostty, set only when off, reset only if set — and
both were mutation-checked: removing the host gate makes the unidentified case
fail, and pinning unconditionally makes the three already-fine cases fail.

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

> **CORRECTED 2026-08-27.** This host reports one thing and paints another, and
> the tables below were built from the report. Measured with `landing_probe.py`
> on 455.1 / macOS 15.7.9, alternate screen:
>
> | cluster | claim | DSR advance | reserve | **paints next at** |
> |---|---|---|---|---|
> | 🤙🏽 👍🏼 ✊🏻 | 2 | 4 | 4 | **2** |
> | ☝🏻 ✌🏼 ✍🏽 ⛹🏾 | 2 | 3 | 3 | **1** |
> | 👩‍🚀 🏴‍☠️ 🧑‍🌾 | 2 | 5 | 5 | **2** |
> | 👨‍👩‍👧‍👦 | 2 | 11 | 11 | **2** |
> | ❤️‍🔥 🏳️‍🌈 ⛓️‍💥 | 2 | 4 | 4 | **1** |
> | 🇺🇸 🇦🇺 1️⃣ #️⃣ | 2 | 2 | 2 | **1** |
>
> One rule predicts every case: **two cells if the cluster's base has emoji
> presentation of its own, one if it does not** — which is why 🏴‍☠️ and 🏳️‍🌈
> differ despite looking like the same kind of thing. Flag pairs and keycaps
> land at 1 regardless.
>
> **FINAL 2026-08-27 — the treatment cards.** The table above is the raw host
> behaviour; the shipped treatments were settled by four "treatment cards"
> (expect/actual row pairs on a blue background, read against a ruler in the
> live terminal, DSR recording the cursor at every atom), which added two
> facts the probes above could not see:
>
> - **Any backward cursor motion over a composed cluster re-renders it as its
>   bare first segment.** A `CUB` pull-back aligns the row and silently strips
>   the tone (or the family, or the tag flag) ON SCREEN — the scalars survive
>   only in the store. `DCH` re-renders the same way.
> - **Stored width is what everything later on the row paints against.** A
>   cluster stored wider than it paints (flags: one surplus column; composed
>   ZWJ under any cursor repair: up to nine) displaces sequential AND
>   absolutely-addressed followers left by the difference. No cursor move
>   edits the store.
>
> The shipped emissions, all card-verified for follower alignment, absolute
> moves, backgrounds, and a full-width row ending in the cluster (no wrap):
>
> | class | claim | emission | on screen |
> |---|---|---|---|
> | tone, emoji-presentation base (🤙🏽 ✊🏿 👍🏽) | 5 | base + **ZWNJ** + modifier, no moves | base, one blank cell, swatch — tone kept |
> | tone, text-presentation base (☝🏻 ✍🏿 ⛹🏾) | 5 | `ECH(5)` + **VS-16-promoted** base+ZWNJ+modifier + `CUF(1)` | emoji base and swatch ADJACENT, one trailing blank (painted by the ECH) — tone kept (2026-08-28; superseded the `CUB(int−2)` pull-back, which re-rendered the bare NARROW glyph beside a blank cell) |
> | ZWJ sequence (👨‍👩‍👧‍👦 ❤️‍🔥 👩🏽‍🚀) | Σ segments | **decomposed** — joiners removed, each segment its own class | component glyphs |
> | flag pair (🇺🇸), keycap (1️⃣) | 2 | cluster + `CUB(1)` `DCH(1)` `CUF(1)` | composed; surplus stored column deleted |
> | BARE keycap (1⃣, no VS-16) | 1 | cluster + `CUB(1)` | advance 2 (DSR record); it used to mis-enter the FE0F surgery on a fall-through model value of 1 and end one column past the claim. Paint/store unmeasured — pixel card queued (2026-08-28) |
> | tag flag (🏴󠁧󠁢󠁳󠁣󠁴󠁿) | 2 | cluster + `CUB(tags)` | aligned; bare 🏴 |
> | VS-16 / bare pictograph / lone RI / PUA | 2 | `ECH(2)` + glyph + `CUF(1)` | composed |
>
> ZWNJ is the ONE separator that stops re-joining: save/restore-cursor, an
> SGR, an 80 ms flush gap and absolute re-positioning all left base and
> modifier adjacent in the store and the terminal composed them again. The
> ZWNJ costs its own internal column (🤙+ZWNJ+🏽 advances 5), hence the claim
> of base + 3. The BARE rewrite fails on text-presentation bases (☝+ZWNJ+🏻
> misaligns), so those first shipped with the pull-back — until 2026-08-28,
> when the pull-back's own cost surfaced (bare narrow glyph, blank cell, tone
> lost) and the VS-16-promoted rewrite measured clean: promote the base to its
> emoji-presentation form, and the cluster becomes an ordinary under-advancer
> (internal 1+1+2 against a claim of 2+1+2) that the standard `ECH`+`CUF` arm
> already handles (point-up cards 1–2).
>
> **Where the ZWNJ's column lands differs by base — measured, both cards
> user-read.** After an emoji-presentation base (🤙‌🏽) the ZWNJ paints its
> own blank column MID-pair: base, gap, swatch. After a VS-16-promoted
> text-presentation base (☝️‌🏻) it paints NOTHING — the pair renders
> adjacent and the spare column trails the swatch, covered by the emission's
> `ECH(5)`. A redundant VS-16 added to an emoji-presentation base does NOT
> buy the adjacent form: 🤙️‌🏽 renders identically to 🤙‌🏽, gap mid-pair,
> same net 5 (adjacency card, 2026-08-28).
>
> **The separator hunt (2026-08-28) — negative result, recorded so it stays
> settled.** Looking for a gap-free separator: U+200B ZWSP, U+2060 WORD
> JOINER, U+00AD SOFT HYPHEN and U+FEFF each cost an internal column exactly
> as ZWNJ does (net 5). U+034F COMBINING GRAPHEME JOINER composes straight
> through — the cluster renders as the merged toned glyph at internal 4 /
> paint 2, the raw cluster's displacement profile: its CHA-60 follower
> painted two cells left, and a full-width row budgeted at its measured
> advance ended two cells short of the edge with the background unpainted in
> both. Reversing the pair (modifier first, net 4, adjacent) is unsafe: a
> leading modifier sits beside whatever PRECEDES the cluster on the row, and
> this terminal composes tone pairs even across cursor moves. The ZWNJ's
> column is the price of separation; on promoted text-presentation bases it
> at least trails rather than splitting the pair. The `DCH` variants of the
> over-advancing classes all wrapped at the row edge and re-rendered bare, so
> DCH is confined to the two classes whose internal column already matches the
> claim.
>
> One candidate was rejected before it reached a card: **interleaving a
> cursor move between base and modifier** (base + `CUF(1)` + modifier —
> "candidate A" of the 2026-08-28 session). In Swift's own grapheme
> segmentation a Fitzpatrick modifier is an Extend scalar, so it FUSES with
> the escape's final byte: `…C` + 🏻 becomes one `Character`, and every
> Character-level escape scanner in the pipeline (`escapeSequenceEnd`, the
> advance oracle, the width scan) mis-parses the emission it itself
> produced — the same `m🏻` hazard the SGR-collapsing code documents. The
> contiguous-cluster emission (`ECH` + whole rewritten cluster + `CUF`) has
> no such seam, which is why it shipped.


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
  (`ColorDepth` quantises). **A `38;2;r;g;b` that reaches it anyway is not
  skipped but read as five ordinary SGR parameters** (observed 2026-09-05,
  macOS 15.7, via an adaptive image palette that derived RGB triples after
  the depth fit): 38 and 2 do little, then a channel value of 5 is *blink*,
  30–37 and 40–47 are the named foregrounds and backgrounds, 90–97 their
  bright twins — a picture came out as blinking primaries in horizontal
  streaks. Anything that changes a colour after `effective(for:)` has fitted
  it must fit it again (`ASCIIConverter.convert`, the adaptive derivation).
  Framework-chosen label colours are floored
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
  **advances 1** ("Bug A" — see `Historical/Emoji rendering bugs in macOS
  Sequoia's Terminal.app (2026-07).md` for the original investigation).
  Compensated with `ECH(2)` + glyph + `CUF(1)` by
  `withTerminalAppCursorCompensation()` — the erase since 2026-08-23, when a
  coloured run showed the skipped cell keeps the default background with CUF
  alone. Exception: the East-Asian-Wide BMP bases 〰️ 〽️ ㊗️ ㊙️ advance
  their full 2.
- **Fitzpatrick skin tones:** the composed cluster paints one merged glyph in
  2 cells while **advancing the internal column 4** (emoji-presentation bases:
  👍🏽 ✊🏻) or **3** (text-presentation: ☝🏽) — "Bug B" — and any backward
  move to repair that re-renders it as the bare base. **Since 2026-08-27 an
  emoji-presentation base is rewritten as base + ZWNJ + modifier** (claim 5:
  base, the ZWNJ's own blank column, swatch) — the tone survives on screen,
  everything aligns, nothing wraps. **Since 2026-08-28 a text-presentation
  base (☝🏻 ✌🏼 ✍🏽 ⛹🏾) is promoted with VS-16 and rewritten the same
  way**, claim 5: the promoted base is a Bug-A under-advancer, so the walk
  wraps the rewritten cluster in the standard `ECH(5)`+`CUF(1)` — measured
  aligned, tone kept. (Its first shipped treatment, the `CUB` pull-back at
  the composed claim of 2, was user-caught re-rendering the bare NARROW
  glyph: one cell of ink, a blank cell beside it, tone lost.) The strip
  remains only for a caller that has not published the host's traits.
- **Flag pairs** (🇺🇸): paints 2, **advances 2** — and the row STORES one
  column more than it paints, displacing every later write on the row one cell
  left. Repaired with store surgery: `CUB(1)` `DCH(1)` `CUF(1)` (2026-08-27;
  the earlier `CUB(1)+CUF(1)` nudge measured misaligned on the cards).
- **Lone regional indicator** (🇦): paints 2, **advances 1** →
  `ECH(2)`+glyph+`CUF(1)`, like every under-advancer here.
- **Keycaps** (1️⃣ #️⃣, with VS-16): advance 2 ✓ — and store one column
  wide, same surgery as flag pairs. The BARE form (1⃣, claimed 1 — the
  base's own width) also advances 2, an over-advance pulled back with
  `CUB(1)` since 2026-08-28 (it used to mis-enter the surgery on a
  fall-through model value; paint/store unmeasured, pixel card queued).
- **ZWJ sequences:** the internal column decomposes (👩‍🚀 **5**, ❤️‍🔥 **4**,
  👨‍👩‍👧‍👦 **11**) while the glyph composes into 2 — and every cursor-move
  repair either displaced the row's tail (stored width) or re-rendered the
  cluster bare. **Since 2026-08-27 the walk decomposes in software**: joiners
  removed, each segment emitted under its own class, claim = the sum
  (👨‍👩‍👧‍👦 = 8, ❤️‍🔥 = 4, 👩🏽‍🚀 = 7 as a separated 👩+ZWNJ+🏽 plus 🚀).
  Component glyphs on screen — the accepted cost. See *ZWJ: where DSR lies*
  below for the history.
- **SF Symbols (Plane-16 PUA, U+100000+):** paints 2, **advances 1** →
  `ECH(2)`+glyph+`CUF(1)`. BMP PUA (e.g. U+E0B0 powerline): advances 1,
  width 1 ✓.
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
- **Bidi controls are painted, not consumed** (measured 2026-09-01): U+202D
  and U+202C come out as the missing-glyph box, one cell each, where the
  other three hosts swallow them at zero width. This is why TUIkit does not
  wrap right-to-left runs in an override — see
  [Right-to-left text](#right-to-left-text--measured-2026-09-01-in-part).
- **The framework's own chrome keeps its ink inside its cells** — card-read on
  455.1, 2026-09-04 (`overhang_card.py`): not one of the 29 `chrome_key` /
  `chrome_glyph` rows marks a flank, so nothing here takes the widened
  chrome-overhang claim Ghostty's `↵` and Warp's seven keyboard symbols do. A
  negative reading, recorded because a host-independent table would have put a
  stray blank cell after seven glyphs of every status bar drawn here.

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
- **Bold brightens a named colour** (`Use Bright Bold`, on by default), so
  `SGR 1` over `30`–`37` paints the bright twin. See "Bold is a COLOUR on some
  hosts"; it ruined every 16-colour image until 2026-09-01.
- **VS-16 pictographic emoji — SCREEN-MODE DEPENDENT:** on the primary
  screen paints 2 / advances 2; on the **alternate screen** (where TUIkit
  apps run) paints 2 / **advances 1** — the same under-advance as
  Terminal.app, with the same EAW exceptions (〰️ 〽️ advance 2).
  Compensated with ECH(2)+glyph+CUF(1) by `withITerm2CursorCompensation()`
  — the erase added 2026-08-28, when a coloured-run card showed the skipped
  cell keeps the default background here exactly as on Terminal.app. (The
  primary-screen alignment card renders correctly; the app misrendered
  until the model was rebuilt from alternate-screen measurements —
  user-reported, byte-capture confirmed identical output bytes, and an
  ad-hoc probe of the day — not kept in `Tools/TerminalProbes` — isolated
  the screen mode as the variable.)
- **Fitzpatrick skin tones — split by plane:**
  - SMP bases (👍🏽): render MERGED (one skin-toned glyph), advance 2 ✓.
  - BMP bases (✊🏻 ☝🏽): render **base + separate 2-cell colour swatch**,
    advancing 4 / 3 — same numbers as Terminal.app's Bug B but with the
    swatch visible. Since the detached-claim widening (`TerminalWidthTraits`,
    skinTone `.detachedOnBMPBases`) the layout claims the 4/3 cells the
    detached rendering actually occupies, so the modifiers pass through
    un-stripped and the swatch the user sees is iTerm2's own rendering.
    (The strip — generic-yellow fallback, `withSkinToneFallback()` — now
    fires only for a caller that has not published the host's traits.)
  - A tone cluster still carrying a redundant VS-16 (☝️🏽 🏋️🏽) renders in
    **3** cells on either plane — narrow base + swatch, NOT the promoted
    base's 4 — measured 2026-08-28 (☝️🏽 in every landing column; the
    siblings by DSR sweep). The old promoted claim of 4 left a one-cell
    hole; since 2026-08-28 the walk strips the redundant selector (the
    modifier alone forces emoji presentation, UTS #51) and the claim
    prices the normalized pair: aligned.
  - The **SMP text-presentation** pair (🏋🏽) breaks the by-plane rule from
    the other side: where BMP bases detach (✊🏻 4, ☝🏽 3), this one merges
    NARROW — advance **1** against the composed claim of 2 (DSR sweep
    2026-08-28; `.detachedOnBMPBases` deliberately does not widen SMP).
    Modelled at 1, so the ordinary ECH(2)+CUF(1) closes it — before the
    sweep the model fell through to 2 and each such pair sheared a cell.
- **Flag pairs:** advance 2 ✓. **Lone regional indicator: advance 2**
  (differs from Terminal.app's 1) — width claim 2 ✓, nothing needed.
- **Keycaps** (1️⃣ #️⃣ *️⃣, bare or with VS-16): paints 2, **advances 1**
  (both screen modes) → ECH(2)+CUF(1) via `withITerm2CursorCompensation()`.
- **SF Symbols (Plane-16 PUA):** paints 2 (monochrome, SGR-tintable),
  **advances 1** → ECH(2)+CUF(1). Same under-advance as Terminal.app, and
  the same unpainted second cell on a coloured run (measured 2026-08-28),
  which is what the ECH fills.
- **ZWJ sequences:** advance 2 ✓ and paint 2 ✓ — confirmed by the paint
  card, not only by DSR. EXCEPT VS-16-leading ones (❤️‍🔥 🏳️‍🌈) which
  advance 1 on the alternate screen — long documented as unhandled, now
  modelled (`iTerm2CursorAdvance` returns 1 for a VS-16-carrying leading
  segment) and closed by the ordinary ECH(2)+CUF(1) repair.
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
- **The framework's own chrome keeps its ink inside its cells** — card-read on
  3.6.11, 2026-09-04 (`overhang_card.py`): none of the 29 chrome rows marks a
  flank, the same negative reading Apple Terminal gives and the reason the
  overhang claim is per host rather than the union of Ghostty's and Warp's.

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
    `.unicode` correctly showed `■ On`. ECH(2)+CUF(1) fixes it (the erase
    measured harmless here — the ink already covers both cells), which is what
    earns Ghostty its place on the `supportsEmojiChrome` allowlist.
  - **SF Symbols (Plane-16 PUA):** unlike Terminal.app/iTerm2 (which paint
    2 and advance 1), Ghostty renders these grid-strictly at **1 cell** and
    advances 1. The claim of 2 is therefore an over-claim here;
    ECH(2)+CUF(1) keeps the row aligned at the cost of one blank cell after
    each symbol — the ECH added 2026-08-28, because that blank cell is one
    the glyph never paints, so with CUF alone it kept the terminal's
    default background on a coloured run (user-reported, card-measured;
    the only Ghostty class that showed the hole).
    *The claim stays 2 even though Ghostty draws 1: Apple Terminal and
    iTerm2 paint these glyphs 2 cells wide, and `TerminalWidthTraits` only
    widens claims for the classes where a 2-cell claim would force
    substitution — a Ghostty-only 1-cell claim would buy one blank cell at
    the price of a per-host layout difference.*
- **`☝🏽` / `🏋🏽`** (text-presentation base + skin tone, either plane)
  merge to ONE cell — the base is a 1-cell text glyph and Ghostty keeps it
  that way with the modifier folded in. Modelled since 2026-08-26 (BMP;
  the SMP flavour by the 2026-08-28 DSR sweep); ECH(2)+CUF(1) lands each
  on the 2-cell claim, tone kept.
- **`☝️🏽` / `🏋️🏽`** (the same pairs with a redundant VS-16) are the
  opposite: the selector DEFEATS the merge and Ghostty detaches promoted
  base + swatch across **4** cells (ledger + sweep, 2026-08-28) — the only
  over-advance measured on Ghostty, and one the ECH+CUF repair used to
  make a cell worse. Since 2026-08-28 the walk strips the redundant
  selector (the modifier alone forces emoji presentation, UTS #51), so
  Ghostty receives the merging pairs above and the class is closed.
- **Cell aspect ratio:** fills `ws_xpixel`/`ws_ypixel` AND answers CSI
  14t/18t, which agree within ~1.4% (ioctl **2.154**, CSI 2.125 — default
  font). Slightly taller than the 2.0 default; auto-detection handles it.
- **`↵` (U+21B5) paints wider than it advances — advance measured 2026-09-04,
  ink card-read the same day.** User-reported first: the status bar's
  `Shortcut.enter` swallows the space before the label beside it, so
  `↵ activate` reads as `↵activate`. **The advance is 1**, here and on all
  three other hosts, so nothing shifts — what Ghostty does it does to the INK
  alone. `overhang_card.py` confirmed it: `↵` marks the right-hand flank here,
  and it is the ONLY one of the 29 chrome rows that does. U+21B5 is East Asian
  Width *Neutral*, so no width table predicts this; it is a host or font
  rendering decision, and it does not disturb the grid.

  Shipped since that reading: Ghostty's traits carry
  `ChromeOverhang.returnArrow`, so `↵` claims two cells **on this host only**
  and the ordinary `ECH(2)` + glyph + `CUF(1)` gives its ink the neighbouring
  cell. Warp smears seven other glyphs and not this one, which is why the claim
  is per host — see "The ink half" above.

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
2026-07-14; **re-measured end to end on `v0.2026.08.26.17.59.stable_01`,
macOS 15.7.9, 2026-08-28** — both the advance battery and the landing/ink/
reserve record, with zero drift on every row of either (see the version-drift
note below). Numbers in this section are good for both builds unless a row
says otherwise. The exceptions are the **tmux** and **Device Attributes**
tables further down: those were measured with the July build attached and
have NOT been re-run, so they still name it.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` (**not** a Warp-specific value — detect on `TERM_PROGRAM`) |
| `TERM_PROGRAM` | `WarpTerminal` |
| `TERM_PROGRAM_VERSION` | `v0.2026.08.26.17.59.stable_01` (was `v0.2026.07.08.17.54.stable_02`; the format is stable, the value is not — never match on it) |
| `COLORTERM` | `truecolor` |
| `WARP_TERMINAL_SESSION_UUID` / `WARP_IS_LOCAL_SHELL_SESSION` / `WARP_HONOR_PS1` … | set |
| `__CFBundleIdentifier` | `dev.warp.Warp-Stable` |

### Output behaviour

Warp is the mirror image of Ghostty: it gets the *selector* classes right
and the *composed* classes wrong.

**Warp does NOT brighten bold** — measured on the card 2026-09-01, its bold
palette is identical to its plain one. What it does instead is
`enforce_minimum_contrast` = `only_named_colors` by default, which lightens a
named foreground it judges illegible; that banded every 16-colour image until
2026-09-01. See "A host may recolour a foreground it cannot read".

> **Version drift check (2026-08-28).** Warp self-updated to
> `v0.2026.08.26.17.59.stable_01`; the full advance battery re-run on that
> build reproduced every one of the 63 previously committed rows exactly —
> including all seven Unicode 16.0 emoji still at 1 — so everything below
> measured on v0.2026.07.08 holds unchanged (committed record:
> `data/warpterminal-v0.2026.08.26.17.59.stable_01-alternate.json`). The
> landing record was re-taken on the new build the same day and likewise
> drifted on nothing, so the July landing file — which no longer describes
> any installed build, and which carried the cursor artefact below — was
> replaced rather than kept.

- **Colour:** truecolor.
- **VS-16 pictographs** (❤️ ✏️ 🖥️) advance 2 ✓ — no Bug-A compensation
  (unlike Terminal.app and iTerm2).
- **VS-15 chrome** (⬛︎ ⬜︎) advances 2 ✓ and paints clean squares → Warp is
  on the `supportsEmojiChrome` allowlist with no help at all.
- **Fitzpatrick skin tones paint base + a separate swatch at 4 cells**
  (3 for BMP bases) against the old claim of 2 — the same shape as
  Terminal.app's Bug B and iTerm2's. **Observed** in the demo's "Unicode
  compatible" feature box: the skin-toned 👍🏽 sheared the box's right
  border two cells out of place. Since the detached-claim widening
  (`TerminalWidthTraits`, skinTone `.detached` — every base, unlike
  iTerm2's by-plane split) the layout claims the cells the detached
  rendering occupies, the modifiers pass through un-stripped, and the
  swatch the user sees is Warp's own. (The `withSkinToneFallback()` strip
  fires only for a caller that has not published the host's traits.) A
  redundant VS-16 on the base (☝️🏽, raw advance 4) is stripped by the walk
  since 2026-08-28 — the modifier alone forces emoji presentation — and
  the normalized pair renders in exactly the 3 cells the claim allocates.
- **Lone regional indicator** (🇦) advances 1 against a claim of 2 — same as
  Terminal.app; ECH(2)+CUF(1) via `withWarpCursorCompensation()`. The erase
  is measured (2026-08-28, Warp tone card): with CUF alone the second cell
  kept the default background under the right half of the glyph's ink — the
  iTerm2 SF Symbol shape — and both the ECH and styled-space variants filled
  it, glyph intact.
- **Unicode 16.0's seven emoji** (🪉 U+1FA89, 🪏 U+1FA8F, 🪾 U+1FABE,
  🫆 U+1FAC6, 🫜 U+1FADC, 🫟 U+1FADF, 🫩 U+1FAE9) advance 1 against the
  2-cell claim — **Warp's width table is Unicode 15.1**. User-reported on
  U+1FAE9 (every later character on the row shifted one left), then the
  whole 1FA70–1FAFF block DSR-swept on all four hosts
  (`recent_emoji_sweep.py`, 2026-08-28): exactly these seven diverge, on
  Warp alone — Apple Terminal, iTerm2 and Ghostty advance all 113
  emoji-presentation scalars in the block by 2, and Warp's own Unicode
  15.0 emoji (🪈 🫎 🩷) advance 2, so 15.1/16.0 is the exact boundary.
  Modelled in `warpCursorAdvance`; the standard ECH(2)+CUF(1) repair
  covers them. Re-run the sweep when Warp updates or a Unicode version
  ships.
- **BMP emoji-presentation clusters ink only ONE of the two cells they
  own** — ⌚ U+231A, ⌛ U+231B, ⏫ U+23EB, ⏬ U+23EC, ⏳ U+23F3 (but not
  ⏩ ⏪ ⏰, which ink both). **Nothing is emitted for these, and nothing
  should be:** Warp advances the full 2, the claim is 2 and the landing is
  2, so no branch of `withWarpCursorCompensation()` fires and every
  follower lands true. What the reader sees is Warp resolving these to a
  monochrome TEXT glyph — from a UI font rather than its colour-emoji font
  — and drawing that narrow glyph in the left half of the pair it correctly
  reserved. No escape sequence can influence a font-fallback choice, so
  there is no treatment to write; the blank right-hand cell is Warp's, not
  ours.

  Recorded because the symptom — low-fidelity glyph, apparent gap after it
  — is indistinguishable at a glance from the under-advances above, which
  we DO compensate and which do produce a blank cell. The two are told
  apart by the ledger, not by eye: an under-advance has `advance < claim`,
  this has `advance == claim == landing` with `ink` short. Warp alone —
  Apple Terminal, iTerm2 and Ghostty ink both cells for all eight (Apple
  inks 3 for ⏩ ⏪ ⏫ ⏬). Re-measured end to end on
  `v0.2026.08.26.17.59.stable_01` (landing record, `ink` column) once Screen
  Recording came back on 2026-08-28: all four facts for all 69 previously
  measured rows reproduced with **zero drift**, this ink split included.
- **Seven keyboard symbols paint two cells while advancing one** — `⎋` U+238B,
  `⏎` U+23CE, `⌫` U+232B, `⌦` U+2326, `␣` U+2423, `⌥` U+2325, `⌘` U+2318.
  Card-read on `v0.2026.09.02` (2026-09-04, `overhang_card.py`): each marks a
  flank, while the advance battery the same day put all 29 chrome rows at
  exactly 1 here. **`↵` U+21B5 is NOT among them** — the glyph the equivalent
  Ghostty reading is entirely about — so the two hosts' overhanging sets are
  disjoint and the claim had to follow the host. Warp's traits carry
  `ChromeOverhang.keyboardSymbols`, so these seven claim two cells on this host
  and take the ordinary `ECH(2)` + glyph + `CUF(1)`. See "The ink half" above
  for the table and the reasoning; the font was not captured with the reading.
- **OVER-advancers, unhandled** (no escape can pull a cursor back to a
  column the glyph has already painted over — the seven entries in
  `TerminalLedgerConformanceTests.knownAdvanceDivergences`, all Warp's):
  keycaps 1️⃣ #️⃣ *️⃣ advance **3**; 〰️ 〽️ ㊗️ ㊙️ (the EAW-base VS-16
  exceptions) advance **3**; the tag-sequence flag 🏴󠁧󠁢󠁳󠁣󠁴󠁿 composes into one
  glyph but advances and lands at **3**.

  **ZWJ sequences left this list on 2026-08-28 — the walk drops the joiners
  in software.** Warp does not compose ZWJ sequences: it draws the
  components with each kept joiner occupying a blank column between them
  (👩‍🚀 advances 5 raw = 2+1+2), which first became the
  `decomposedKeepingJoiners` claim (2026-08-26, rows align but the joiner
  columns read as gaps) and is now emitted with the joiners removed —
  claim and advance are the bare segment sums (👨‍👩‍👧‍👦 8, 👩🏽‍🚀 6,
  ❤️‍🔥 4, 🏳️‍🌈 4). Card-measured (Warp ZWJ + tone cards, user-read):
  every dropped form renders the same components adjacent, gap-free, with
  sequential and absolute followers landing true, and full decomposition
  was the user's preferred rendering. One anomaly on the first card — the
  dropped toned astronaut's CHA follower one cell left — did NOT reproduce
  on the isolation card (👩🏽 alone / +🚀 / +😀 / +ASCII all true); if it
  resurfaces, that card is the instrument.

  ⚠️ Terminal.app's ZWJ story is different: it COMPOSES the glyph and only
  its column accounting runs ahead, so its decomposition exists to keep the
  store honest — see *ZWJ: where DSR lies*. Keycaps and 〰️ remain
  Warp-specific and DO shear.
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

## xterm.js — the browser (measured 2026-09-05)

**Tested:** xterm.js 6.0.0 in Chromium 148, via `Tools/Web/glyph-probe.html`,
which measures the same corpus the Python probes measure and writes the same
kind of record (`data/xtermjs-6.0.0-graphemes-advance.json`).

A browser terminal is measured differently, and the difference is worth
stating: there is no DSR-versus-paint gap to close, because the buffer *is* the
model. `cursorX` after a write is the advance, the cell a following character
occupies is the landing, and the two cannot disagree. What this record does NOT
carry is `ink` — how many cells the glyph is painted across — because that
would need pixels, and none were read.

### It is a configuration, not an emulator, that gets emoji wrong

xterm.js ships Unicode 6 width tables. Under them an emoji is one cell, so it
is drawn clipped and everything after it on the row sits one column left of
where the app put it — two emoji in a header, two columns of shift, and the
box's right border lands inside the box. That was the WebAssembly demo's first
appearance, and the fix is one script tag:
`@xterm/addon-unicode-graphemes`, with `terminal.unicode.activeVersion` set to
`15-graphemes`. It replaces the tables *and* clusters by grapheme, which is
what makes 🖥️ (pictograph + VS16) two cells rather than one plus a stray.

Measured against the framework's own widths (`data/tuikit-widths.json`), over
the 78 clusters the native probes covered:

| Host | advance agrees with TUIkit |
|---|---|
| Ghostty 1.3.1 | 63 / 78 |
| **xterm.js 6.0.0 + unicode-graphemes** | **61 / 78** |
| iTerm2 3.6.11 | 53 / 78 |
| Apple Terminal 455.1 | 41 / 78 (landing 51) |
| Warp 2026.08.26 | 35 / 78 |
| xterm.js 6.0.0, default tables | 33 / 78 |
| xterm.js 6.0.0 + unicode11 | 31 / 78 |

Two readings matter here. The first is that a correctly configured browser
terminal is not a poor relation: it sits second in a field of five, above two
shipping native terminals. The second is that `addon-unicode11` — the obvious
choice, and the one most projects load — is **worse than doing nothing**: it
widens the emoji but has no grapheme clustering, so every ZWJ sequence and
skin-tone modifier is counted as its parts (👩‍👩‍👧‍👦 advances 8) and the total
agreement drops from 33 to 31.

### Where it still disagrees, and with whom

Over the full 145-cluster corpus, 29 rows disagree with TUIkit. They are not
scattered:

| Class | Rows | What happens | Also disagrees |
|---|---|---|---|
| `recent_emoji` | 10 | one cell — the addon's tables are Unicode 15 and these are newer | Warp (7 of the same rows) |
| `spacing_vowel_sign`, `thai_lao` | 7 | one cell where TUIkit says two — a REGRESSION from the default tables, which say two | — |
| `pua16` (SF Symbols) | 3 | one cell; private-use codepoints carry no width | every native terminal measured |
| `bare_pictograph` | 3 | one cell, matching Ghostty's advance | Ghostty, iTerm2, Apple Terminal, Warp |
| `indic_conjunct` | 3 | three cells where TUIkit says two | — |
| `format_control`, `regional_indicator` | 3 | one cell where TUIkit says zero or two | — |

The SF Symbols row is the one to remember for the demo: the Example's symbol
page will shift, and no terminal can do better, because a private-use codepoint
has no width to look up.

### Capabilities — asked, not assumed

Every answer below came back from the terminal itself during the probe:

| Query | Answer |
|---|---|
| DA1 `CSI c` | `CSI ?1;2c` — identifies, so the framework's identity query completes |
| DA2 `CSI > c` | `CSI >0;276;0c` |
| XTVERSION `CSI > 0 q` | *nothing* — no name/version string |
| DSR `CSI 6 n` | `CSI 1;1R` — cursor reporting works, so the advance probes do |
| DECRQM `?1049` / `?2004` / `?1006` / `?1002` | `;2` (recognised, currently reset) |
| DECRQM `?2027` | **`;0` — not recognised.** No grapheme-clustering mode, so the framework keeps its own advance model |
| SGR 38;2 truecolor | the exact RGB written comes back on the cell |
| Alternate screen `?1049` | enters and leaves |
| OSC 8 hyperlink | the row holds the text and none of the sequence |
| SGR mouse `?1006` | a click sends `CSI <0;3;1M` / `CSI <0;3;1m` |

Not supported, and not worked around: the Kitty graphics protocol. Pictures
fall back to cells, which is what the handshake is for.

### Why not something else

The browser-terminal field is smaller than it looks. Everything that ships a
terminal on a web page — VS Code, ttyd, wetty, Codespaces, Jupyter — is
xterm.js. `hterm` (Google's, inside libapps) is the only other complete VT
emulator for the DOM; it is `wcwidth`-based with no grapheme clustering, which
is the configuration measured at 33/78 above. The rest (jQuery Terminal,
Termino.js, the canvas toys) are consoles, not emulators: no alternate screen,
no SGR mouse, no DECRQM. There is no wasm port of a native terminal that
renders to the DOM.

So the answer to "is there something more capable" is that xterm.js configured
correctly *is* the capable one, and the emoji problem was a missing addon
rather than a missing emulator.

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
`withSkinToneFallback(scope:)` with the measured keep-set):

| Cluster | tmux 3.7b | TUIkit claims | Handled how |
|---|---|---|---|
| `U+100038` etc. (Plane-16 PUA, **SF Symbols**) | **1** | **2** (`String+TerminalWidth.swift`, the Plane-16 arm) | CUF: one `ESC[1C` after each, landing the cursor at the claimed column |
| `U+1F5A5`, `U+1F6E1`, `U+1F577`, `U+1F39E`, `U+1F3D9` (bare SMP pictographs) | **1** | **2** | CUF, same as above |
| `U+1F060` domino, `U+1F0A1` playing card | **1** | 2 | CUF, same as above |
| `U+270A U+1F3FB`, `U+1F919 U+1F3FD` (skin tone on a base tmux **detaches** — 64 of the 134 modifier bases, per codepoint) | **4** | 2 | swatch stripped (`.keepingTmuxMerged` strips exactly the detaching bases) → back to a 2-cell advance |
| `U+2B1B U+FE0E` (VS-15 chrome ⬛︎) | **2** | 2 | ✓ already agrees (both 2) — no action |
| `U+1F1E6` lone regional indicator | 1 | 1 | ✓ |
| `U+4E2D` CJK · `U+1F44D` emoji · ZWJ families · `U+1F1FA U+1F1F8` flag | 2 | 2 | ✓ |
| `U+1F44D U+1F3FD` (skin tone on a base tmux **merges** — the measured 70, `Character.tmuxMergedToneBases`) | 2 | 2 | ✓ — NOT stripped when every attached client renders kept tones |
| `U+0065 U+0301` NFD · `U+E0B0` powerline · `U+2588` block | 1 | 1 | ✓ |

**The defect this closed:** the main menu's "Supports SF Symbols" FeatureBox
renders **three** Plane-16 PUA glyphs. TUIkit reserves 2 cells each (6); tmux
advances 1 each (3). Before 8c1e06d8 nothing compensated, so — measured in
tmux's own grid at 100×60 — that line's right border landed at **cell 65**
while every other line of the box landed at **68**, exactly 3 cells short, one
per glyph, and the border was visibly broken. The tmux path now emits one CUF
per under-advancing cluster, landing the cursor at the claimed column, so the
border closes. Same fix for the bare SMP pictographs and the dominoes/cards.

The claim's comment ("SF Mono: 2 cells") is right about the *font* in a native
terminal and about the width TUIkit paints; tmux's wcwidth has never heard of
SF Symbols and advances 1, which is why the tmux path adds the CUF rather than
changing the claim. `withSkinToneFallback(scope: .keepingTmuxMerged)` is
deliberately narrower than the blanket strip: tmux joins 70 of the 134
modifier bases (👍🏽 👋🏽 🤦🏽 🧑🏽 …) into exactly the 2 cells claimed, and
stripping those would discard clusters it gets right. Which bases merge is
**per codepoint** — the full sweep (2026-08-28,
`advance_probe.py --modifier-bases`, headless tmux, record
`data/tmux-3.7b-tonebases.json`) retired two tidy wrong rules in a row: it is
not by base plane (🤙 and 🤚, SMP, detach at 4 while 🧑, also SMP, merges —
caught 2026-08-26 when the Fitzpatrick row rendered short under a policy that
kept every SMP base) and not by Unicode era (Unicode-6.0 🎅 detaches while
the Unicode-10.0 🧍…🧝 run merges). The measured set
(`Character.tmuxMergedToneBases`) is the rule, and
`TmuxCompatibilityTests` pins it against the record row for row.

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
<!-- The XTVERSION string reports whatever build is running; this row records
     what the July build answered and was not re-run on the 2026-08-26 one. -->
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
`tmuxSkinToneScope`, `.keepingTmuxMerged` for all-Ghostty clients, `.all`
otherwise) — the one fix that survives the hop, because tmux's grid then
holds and re-emits the toneless cluster. The scope rides the same
push-refreshed client probe as the chrome, so a client change restyles both
in the same full redraw. Tones on the 64 bases tmux itself DETACHES (✊🏻 ☝🏽
🤙🏽 — the complement of `Character.tmuxMergedToneBases`) are always
stripped under tmux: its own grid over-advances those, client-independent,
so no client choice can save them.

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
2026-08-24. Ghostty 1.3.1 read from its own configuration 2026-09-01 but not
yet confirmed live. iTerm2 and Warp pending.**
`Tools/TerminalProbes/palette_probe.py` asks a terminal directly (OSC 4 /
OSC 10 / OSC 11) and writes the answer as JSON; run it in each host and record
the results below.

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

### Ghostty 1.3.1, default theme — read from its own configuration

**Provenance: `ghostty +show-config --default`, 2026-09-01, with the user's
`config.ghostty` empty (0 bytes) so the defaults are what runs. NOT yet
confirmed over OSC 4 in a live window — run `palette_probe.py` there to
promote this from "what it ships" to "what it paints".**

Ghostty's stock scheme is Tomorrow Night, and it is muted on purpose. **Slot 0
is not black**, which is the whole of why a near-black photograph renders
visibly lighter here than in Terminal.app:

| slot | Ghostty | Apple Terminal (measured) | xterm (assumed) |
|---|---|---|---|
| 0 black | `#1d1f21` (29, 31, 33) | 0, 0, 0 | 0, 0, 0 |
| 4 blue | `#81a2be` (129, 162, 190) | 0, 0, 179 | 0, 0, 238 |
| 6 cyan | `#8abeb7` (138, 190, 183) | 0, 166, 179 | 0, 205, 205 |
| 7 white | `#c5c8c6` (197, 200, 198) | 191, 191, 191 | 229, 229, 229 |
| 8 br.black | `#666666` (102, 102, 102) | 102, 102, 102 | 127, 127, 127 |
| 12 br.blue | `#7aa6da` (122, 166, 218) | 0, 0, 255 | 92, 92, 255 |
| 14 br.cyan | `#70c0b1` (112, 192, 177) | 0, 230, 230 | 0, 255, 255 |
| 15 br.white | `#eaeaea` (234, 234, 234) | 230, 230, 230 | 255, 255, 255 |

Two consequences for a 16-colour image, and neither is a defect:

- **`#1d1f21` is the darkest colour Ghostty has.** A black pixel cannot paint
  darker, whatever the quantiser picks, so "the background came out lighter"
  is the answer and not a symptom.
- **The blues and cyans are desaturated steel and sage**, so a picture whose
  subject is saturated blue reads as teal. Terminal.app's slot 4 is a pure
  `(0, 0, 179)`; Ghostty's is a grey-blue two thirds of the way to neutral.

Default background `#282c34` and foreground `#ffffff` — but a TUIkit app paints
its own page, so those reach nothing an image draws.

### A host may recolour a foreground it cannot read — measured 2026-09-01

**Status: the framework no longer emits the sequence that provokes it.**

Warp has `appearance.text.enforce_minimum_contrast`, and it defaults to
**`only_named_colors`** — "FG color can be changed, but only if the FG is
specified with default colors" (its own settings schema, read from
`Warp.app/Contents/Resources/settings_schema.json` on 2026-09-01; the three
values are `never`, `only_named_colors`, `always`). So a foreground stated as
one of the sixteen and judged illegible against its background is LIGHTENED.

That is a reasonable thing for a terminal to do to text and a ruinous thing to
do to a picture. A half block whose two pixels quantise to the same colour is
emitted with foreground == background, which is the most unreadable text there
is; Warp lifted the foreground of every such cell, so the lower half of the
cell went grey while the upper half — the background, which the feature does
not touch — stayed put. **The picture banded at cell pitch**, exactly as it did
on iTerm2, and for an unrelated reason: Warp does not brighten bold at all.

Two hosts, two causes, one symptom. The card separates them:
`bold_bright_card.py` draws a flat colour as a space, as a block with
foreground == background, and as that block emboldened.

| what bands | cause | hosts |
|---|---|---|
| the bold block only | bold is read as a colour | iTerm2 |
| the plain block AND the bold one | a named foreground is being made legible | Warp |
| neither | no adaptation applies | Ghostty, Terminal.app |
| the space | the host is not painting a cell background across the whole cell — nothing TUIkit emits can help | none seen |

**The fix** is not to state a foreground the cell does not use: a cell whose two
pixels paint the same colour is emitted as a SPACE with only a background. It
is also the honest spelling — one colour is a field, not a shape — and most of
a picture is such cells: 41.8% at true colour, 73.6% at 256, **86.5% at
sixteen**, since the coarser the palette the more often two neighbours land on
one entry. Measured on the Example's demo photograph at 183×60.

`enforce_minimum_contrast` reaches only NAMED foregrounds at its default, which
is why the report was about 16-colour mode: a `38;2` triple was never touched.
Set to `always` it would reach those too, and there is nothing an application
can do about that — nor should there be.

### Bold is a COLOUR on some hosts — measured 2026-09-01

**Status: the framework no longer relies on it. Per-host readings still wanted;
run `Tools/TerminalProbes/bold_bright_card.py` in each.**

`SGR 1` is documented as a weight. xterm and most of its descendants also treat
it as a colour: with bold in force, a foreground named as one of the standard
eight (`SGR 30`–`37`) is painted in its BRIGHT twin. Backgrounds are never
brightened, and an explicit `38;2;r;g;b` triple has no twin to be swapped for,
so the reinterpretation reaches exactly the sixteen NAMES.

Each host spells the choice differently, and they do not agree:

| host | setting | this machine's value | brightens bold? |
|---|---|---|---|
| iTerm2 | `Use Bright Bold` (profile) | `True` — the default | yes |
| Warp | none | — | **no** — measured on the card 2026-09-01 |
| Ghostty | bold is weight-only; `bold-color` overrides the colour explicitly | unset | no |
| Apple Terminal.app | "Use bright colors for bold text" (profile) | absent from `Basic`, so off | no |

Read from `com.googlecode.iterm2.plist`, `ghostty +show-config --default` and
`com.apple.Terminal.plist` on 2026-09-01, and confirmed by eye on the card in
all four. Warp was assumed to brighten when this was first written, because it
banded; it does not, and the section above is what it actually does. **Two
hosts can produce one symptom for two causes — measure each rather than
generalising from the first one solved.**

**What it cost.** `ASCIIConverter+HalfBlocks` emboldened every `▄` it emitted,
to close a rasterisation gap under SF Mono in Terminal.app (see the advance
table below). In `.trueColor` that is free. In ``ASCIIColorMode/ansi16`` the
foreground is `30`–`37` / `90`–`97`, so on iTerm2 **every cell's lower half was
painted in the bright twin of the colour asked for** while its upper half — the
background — stayed correct. A picture drawn entirely out of half blocks
therefore came out in horizontal stripes at cell pitch. Measured on the
Example's demo photograph at 183×60: 5724 cells, all bold, and 86.5% of them
with foreground == background, which is precisely where a stripe is most
visible because the cell should be flat.

The emission was identical under every `TERM_PROGRAM` — this was never a
per-host code path, just a per-host reading of one universal sequence.

**The fix** is ``ASCIIColorMode/foregroundSurvivesBold``: spend the weight only
where the foreground has no bright twin — a `38;2` triple, or `38;5;n` where
*n* ≥ 16, which is every index the 256-colour quantiser can produce. A palette
is only as safe as its least safe entry, and ``ASCIIPalette/downsampled(to:)``
turns any palette into unsafe names at `.basic16`. Where the weight is refused
the Terminal.app hairline returns, which is the lesser evil: a hairline on one
host beats a ruined image on two.

**The general rule for the framework**: any attribute that a host may read as a
colour must not be used decoratively over a colour stated as one of the sixteen.
Bold is the one that exists today; `SGR 2` (faint) is the same shape of hazard.

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
  **Measured, 2026-09-01:** quantising against Ghostty's real sixteen instead
  of xterm's table changes the slot chosen for **66.8%** of the RGB cube, and
  the colour actually painted lands **24% closer** in OKLab — the same 24% over
  the cube as over dark pixels alone. So the approximation costs about a
  quarter of the accuracy the mode is capable of. Asking `OSC 4` once at
  startup and quantising against the answer is the fix, and is not built.

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

## OSC 8 hyperlinks — measured 2026-09-02

`ESC ] 8 ; <params> ; <URI> ST` attaches a destination to the cells that
follow, until `ESC ] 8 ; ; ST` ends it. What that buys a framework which
already handles clicks itself is that **the terminal now knows where those
cells point**, so the URI becomes something it can show and offer to copy
even though the label reads "Documentation" and the destination appears
nowhere on screen. No application can produce that; a click it handles
itself leaves the URL as invisible as it was.

Measured with `Tools/TerminalProbes/hyperlink_probe.py`, which asks two
different questions and can only answer one of them from inside.

### Safe: measurable, and it is the question that licenses emitting

A terminal with an OSC parser consumes the whole sequence whether or not it
implements the command — costing nothing, painting nothing. A terminal
**without** one prints the payload: the URI sprayed across the row, the
cursor left wherever that ended, and every later write on the row landing in
the wrong column. DSR sees that difference. Print a known-width label wrapped
in OSC 8, ask where the cursor is, and compare against the same label bare.

| Host | version | plain | with `id=` | BEL-terminated | bare close | unknown OSC command |
|---|---|---|---|---|---|---|
| Apple Terminal | 455.1 | swallowed | swallowed | swallowed | swallowed | swallowed |
| iTerm2 | 3.6.11 | swallowed | swallowed | swallowed | swallowed | swallowed |
| Ghostty | 1.3.1 | swallowed | swallowed | swallowed | swallowed | swallowed |
| Warp | v0.2026.08.26.17.59.stable_01 | swallowed | swallowed | swallowed | swallowed | swallowed |

Both screen buffers, every host, every spelling: the cursor lands exactly
where the bare label leaves it. The `unknown OSC command` column is the
control — a command number nothing implements — and it is the reason the
result generalises: these hosts swallow **any** OSC, so the answer is a
property of their parsers rather than of this one sequence.

**So being wrong about the second question costs a link that does nothing,
not a corrupted row.** That asymmetry is what lets the capability table be
generous, and it is the opposite of how the cursor-advance quirks work,
where being wrong corrupts output that was fine. See
`TerminalClient.honoursHyperlinks(_:)`, which says so at the code.

### Which gestures reach it — observed 2026-09-02, in a running TUIkit app

Not measurable from inside: the affordance is a mouse gesture over a live
terminal, which is exactly the gesture no probe in this directory can
perform. `hyperlink_probe.py`'s card asks a human, and this is that answer —
the project owner's, in each terminal, with a TUIkit app running and mouse
reporting held open. It **replaces** an earlier paragraph here that reasoned
from the mouse-event measurements instead and got the important one
backwards.

| Host | Click over an OSC 8 link | Seeing the destination | Shift-click |
|---|---|---|---|
| iTerm2 | **⌘-click: the terminal opens it** (asking which browser). Other clicks reach the application. | hold ⌘ and hover → the URL appears bottom-left of the window | selects text |
| Ghostty | — | hold ⌘-shift and hover → the URL appears | selects text |
| Warp | n/a (does not honour OSC 8) | n/a | selects text |

Three things follow, and the first is the one that was wrong before.

- **In iTerm2 the gesture chooses the opener, and the outcome does not reveal
  which.** ⌘-click is taken by the terminal; any other click is reported to
  the application — which, since 3a96d8fc, does NOT open it by default: it
  raises the destination popover, and opens through ``OpenURLAction`` only
  when the app or the user has said this session is local (the ssh paragraph
  below is why). When the application does open it, the browser that appears
  is identical either way, which is why this entry first read "the terminal
  opens it, on every modifier" — that observation was of the OUTCOME, and the
  outcome cannot tell them apart. Distinguishing them
  needs the application to say when it acted: `Example`'s Buttons & Links
  page now prints a line every time TUIkit does the opening, and that readout
  is the instrument this row should be re-measured with.

  It also means the two openers put the URL on **different machines** over
  ssh — see below.
- **Shift-click is NOT the bypass.** The xterm convention says shift means
  "handle this yourself, do not report it", and the earlier paragraph here
  recommended it on that basis. In practice Ghostty and Warp both take
  shift-click as *select text* — over OSC 8 links and over auto-detected
  ones alike — and iTerm2 opens the link. Nothing observed here treats it as
  a way to reach the application.
- **The destination is shown behind a modifier, not on plain hover.** Both
  hosts that honour OSC 8 reveal the URL while a modifier is held (iTerm2 ⌘,
  Ghostty ⌘-shift) rather than on hover alone. Ghostty's `link-previews`
  setting has an `osc8` mode, but no unmodified hover preview was observed.

### Which MACHINE opens it — the axis this table was missing

`OpenURLAction` runs `/usr/bin/open` or `/usr/bin/xdg-open` **on the machine
the application is running on**. So the gesture above decides more than which
component acts:

| | terminal opens it | application opens it |
|---|---|---|
| local | the user's browser | the user's browser — indistinguishable |
| over ssh | **the user's browser** | the *server's* browser, or nothing at all |

Over a hop, the terminal taking the click is the only path that reaches the
user's own browser. The application path runs on the server, where
`xdg-open` ships in `xdg-utils` — a **desktop** package, absent from Debian
and Ubuntu server images, Fedora minimal, Alpine and every distroless image.
Where it is absent, `systemOpen`'s loop body never executes and **nothing is
spawned at all**: no process, no output, no trace. Where it is present on a
headless box it exits 3 into a `/dev/null` stderr, which the doc comment on
`systemOpen` explains — an `xdg-open` complaint would otherwise land mid-frame
at the renderer's cursor. Both failures are therefore silent by construction,
and the keyboard route (Enter on a focused link) is *always* the application
path, so it never reaches the user's browser over ssh at all.

**As of 2026-09-03 TUIkit does not take the application path at all.**
`OpenURLAction`'s system opener is gated behind
`TerminalClient.urlOpeningSupport` / `TUIKIT_OPEN_URLS`, and both default to
off. The reasoning is that the framework cannot tell which machine it is on:
`SSH_CONNECTION`, `SSH_TTY` and `SSH_CLIENT` are reliable when PRESENT and
prove nothing when absent — gone under `sudo` and `su`, and a tmux, screen or
zellij session started before the hop, or reattached after it, carries the
environment of whenever it began rather than of the client now looking at it.
No escape sequence asks a terminal which machine it is on. And the two wrong
answers do not cost the same: guessing local when remote sends somebody's URL
to a machine they are not at and leaves it in their history, while guessing
remote when local costs a copy and paste.

So the terminal's column above is the only one TUIkit relies on, and a `Link`
is not silent as a result: it carries the OSC 8 escape where the host honours
one, and activating it raises a popover with the destination to read and copy
(`LinkDisplay`). An app that knows it is local sets `urlOpeningSupport = true`;
a user answers for their own session with `TUIKIT_OPEN_URLS=1`; and an app
with its own opening handler is not gated at all, because what is gated is
only the framework launching a process on the user's behalf.

**The remedy that already exists** for the escape is identification, not code:
`TERM_PROGRAM`
does not survive an ssh hop, so a terminal that would have got an OSC 8 escape
often falls to `.unidentified` and gets none. `TUIKIT_HYPERLINKS=1` on the
remote host restores emission (`TerminalHyperlinkSupport.swift`), via `SendEnv`
/ `AcceptEnv` or a line in a remote profile. `LC_TERMINAL` survives the hop on
its own where iTerm2's shell integration is installed.

### Terminals also detect URLs in the TEXT, which is not this feature

Independently of OSC 8, these hosts scan displayed characters for things
that look like URLs and make those clickable too. It matters twice:

- A demo of "this text carries no hyperlink" must not be spelled as a URL,
  or the terminal linkifies it anyway and the demo shows the opposite of
  what it claims. `Example`'s Buttons & Links page uses ordinary words for
  exactly this reason.
- The modifier-hover readout distinguishes them: in iTerm2, holding ⌘ over
  an **OSC 8** link shows the destination bottom-left, and holding ⌘ over an
  auto-detected URL does not. So that tooltip is a usable oracle for
  "did the escape actually land", which is otherwise invisible.

### Honoured: not measurable from inside, and no query reports it

There is no escape sequence that asks. DA1, DA2 and XTVERSION say nothing
about it, no reply distinguishes a terminal that stored the URI from one
that discarded it, and the affordance itself is a mouse gesture the
application never sees. The probe therefore prints a card for a human and
records the answer beside the measurement rather than pretending to have
derived it. What the table below rests on instead:

| Host | Honours | Evidence |
|---|---|---|
| iTerm2 | **yes** | its own setting, `Drawing: Underline OSC 8 hyperlinks` (`underlineHyperlinks`); and tmux gives it the `hyperlinks` feature |
| Ghostty | **yes** | per-page hyperlink storage in its cell model (`cell_hyperlink`, "Maps cell positions to hyperlink IDs"); `link-previews` has an explicit `osc8` mode; and ⌘-shift-hover shows the destination (observed) |
| tmux | **yes** | stores links in its grid, and `capture-pane -H` reads them back — the one machine-checkable oracle here |
| Apple Terminal | **no** | the app names no hyperlink handling at all; the sequence is swallowed and nothing is kept |
| Warp | **no** — deliberately, see below | the only hyperlink handling its binary names is bounded by `HighlightedLink is not within the alt screen` |

**Warp is a decided `false`, not an unknown.** It swallows the sequence like
the others, so emitting there would be safe; the reason not to is that the
alternate screen is the only buffer a TUIkit app ever draws into, and the
one string in Warp that bounds its link handling excludes exactly that.
Claiming a capability this framework's own users could not reach is worse
than claiming none — it turns "this terminal does not do that" into "this
framework is broken here". `TerminalClient.hyperlinkSupport = true`
(or `TUIKIT_HYPERLINKS=1`) overrides it for anyone who finds otherwise.

### tmux honours it, and then decides who else may see it

`capture-pane -H` is the oracle: a pane sent `ESC]8;;https://example.com ST`
reports that URI back, and `capture-pane -F` flags the row `H`. The link is
stored whether or not any client is attached.

Forwarding is a separate decision. tmux sends hyperlinks only to clients
whose `terminal-features` include `hyperlinks`, which it derives from its own
table keyed on XTVERSION. Measured with tmux 3.7c, `-f /dev/null`, one
server per host:

| Client | `#{client_termtype}` | `hyperlinks`? |
|---|---|---|
| iTerm2 3.6.11 | `iTerm2 3.6.11` | **yes** |
| Ghostty 1.3.1 | `ghostty 1.3.1` | no — identified, and still given nothing |
| Warp | `Warp(v0.2026.08.26.17.59.stable_01)` | no |
| Apple Terminal | *(empty — answers no XTVERSION)* | no |

So a link inside tmux inside Ghostty is stored and never shown, until the
user says `set -ga terminal-features "*:hyperlinks"`. That is tmux's
decision and not one an application can override, which is why TUIkit emits
regardless: the link costs nothing where it is dropped and works wherever
the user has told tmux it can.

> **Measurement artefact worth knowing.** tmux's feature detection is
> asynchronous — it probes the client with XTVERSION after the attach. Asking
> `#{client_termfeatures}` immediately reports the terminfo-derived set and an
> EMPTY termtype, which is indistinguishable from a terminal that answers no
> XTVERSION. The first run of this measurement recorded iTerm2 that way. Sleep
> a few seconds after attaching before asking. (The same shape as the July
> reading in "Identifying the client terminal": an empty termtype is not
> evidence of anything.)

### Which terminator, and why the URI is re-encoded

`ST` (`ESC \`), not the `BEL` xterm also accepts. It is the form the
specification gives, it is what tmux writes, both were measured to be
swallowed everywhere above — and `BEL` would put a C0 control inside every
link, which `String.sanitizedForTerminalRow()` then has to reason about in
exchange for nothing.

The sequence **ends** at an `ESC` or a `BEL`, so a destination containing
either does not render oddly: it terminates the sequence, and the rest is
text the terminal draws. A URL is exactly the kind of value an application
builds out of data it did not author, so `TerminalHyperlink` percent-encodes
every byte that is not a printable non-blank ASCII character rather than
assuming the caller did. Same reasoning as `String.sanitizedForTerminal`:
the gate belongs where the escape is written.

---

## Graphics protocols, and a parser gap — measured 2026-09-02, iTerm2's placeholders 2026-09-03

Full treatment, including what TUIkit should do about it, is in
`Documentation/Terminal graphics protocols.md`. Two facts belong here because
they are facts about the terminals rather than about a design.

### Apple Terminal parses OSC and does NOT parse DCS or APC

All three graphics protocols ride string-terminated escape families — DCS for
Sixel, OSC 1337 for iTerm2's, APC for Kitty's — so it is tempting to reason
that any terminal with an escape parser consumes them whole and ignores the
ones it does not implement. That is what all four hosts do with OSC 8
(previous section). Apple Terminal does it for **OSC only**.

Measured with `graphics_probe.py`: a payload printed between two brackets on a
cleared row, and the cursor asked where it landed.

| Payload | Apple Terminal 455.1 |
|---|---|
| OSC 1337 (161 B) | Δ0 — swallowed |
| DCS Sixel (25 B) | **Δcol +21 — printed** |
| APC Kitty (123 B) | **Δrow +1, Δcol +39 — printed** |

`ESC P` has its `P` consumed as though it were a two-byte escape and the rest
of the payload goes to the screen — exactly `25 − ESC − P − ESC − \` visible
cells. Same for `ESC _`. A page-sized image would be tens of kilobytes of
base64 across the screen.

**So a string-terminated escape is not automatically safe, and which family it
is decides.** The same parser weakness is already recorded here twice over:
`probe_stamp.py` skips DECRQM on Apple Terminal because it prints that query's
final byte, and this host is why. Anything DCS- or APC-shaped must be gated on
positive evidence.

### What each host advertises

| Host | version | Sixel in DA1 | Kitty `a=q` | Kitty Unicode placeholder |
|---|---|---|---|---|
| Apple Terminal | 455.1 | no | silent | silent |
| iTerm2 | 3.6.11 | **yes** (`4` in `ESC[?64;1;2;4;6;17;18;21;22;52c`) | **`OK`** | **`OK`** — and draws, given the third mark (below) |
| Ghostty | 1.3.1 | no | **`OK`** | **`OK`** |
| Warp | v0.2026.08.26.17.59.stable_01 | no | **`OK`** | **refused, by name** |
| tmux | 3.7c | **yes** (`ESC[?1;2;4c`) | silent | silent |

**iTerm2 needs the spec-optional third combining mark** (iTerm2 3.6.11,
measured 2026-09-03 with `Tools/TerminalProbes/placeholder_spelling_probe.py`).
The Kitty spec lets a placeholder cell omit the diacritic that carries the
image id's high byte, inheriting it from the cell to the left, and TUIkit did
omit it. kitty and Ghostty read a two-mark cell and a three-mark cell
identically; iTerm2 draws NOTHING for the two-mark cell and the picture for the
three-mark one, whichever way the foreground is spelled (24-bit, or the
256-colour form the spec's own example uses). The encoder therefore writes all
three marks on every cell — `KittyGraphics+Placeholders.swift` says so at the
line — and the section stamp above predates this row. iTerm2 is absent from the
advance table further down: its cursor advance over a placeholder row was not
captured, and the codepoint exemption applies to it regardless.

Warp's refusal is a named answer rather than a silence to be interpreted —
`InvalidKittyAction(InvalidControlData(UnicodePlaceholderUnsupported))` — which
makes the Kitty protocol the only terminal capability in this document that can
be interrogated **per feature** instead of looked up in a table keyed on an
identified host. A table written from Warp's feature list would have recorded
it as supporting placements.

**`XTGETTCAP Su` is not a Sixel signal.** iTerm2 answers `DCS 0 + r … ST` (not
present) while its DA1 advertises Sixel; Ghostty answers `DCS 1 + r 5375 ST` —
a success flag with no value — while supporting no Sixel at all. Use DA1.

### Deflated transmissions (`o=z`) — asked by the handshake, NOT YET MEASURED

TUIkit's startup handshake asks a second question since 2026-09-04: whether a
zlib-deflated transmission is understood. It transmits a 32×32 block as
twenty-six deflated bytes with `o=z` and `q=0`, and credits an `OK` under that
id (`TerminalGraphicsQuery.compressionProbeID`). The size is the honesty of
the probe — twenty-six bytes cannot be a raw 32×32 picture, so a host that
ignored the key would have to refuse it. Where it answers `OK` and the host
has a `libz` to borrow (`SystemZlib`), every image is sent deflated; a
gradient rendered as pixels shrinks by an order of magnitude, a photograph by
a little.

| Host | `o=z` acknowledged | deflated picture DRAWS |
|---|---|---|
| Apple Terminal | never asked (prints APC) | — |
| iTerm2 | unmeasured | unmeasured |
| Ghostty | unmeasured | unmeasured |
| Warp | unmeasured | unmeasured (draws no placeholders anyway) |

Run `Tools/TerminalProbes/graphics_compression_probe.py` inside each host: it
asks both questions and prints the same ramp raw and deflated, one under the
other, for a person to compare. Until a host has a row here, the answer TUIkit
acts on is the host's own at startup — and `TUIKIT_GRAPHICS_COMPRESSION=0`
turns it off for a host that acknowledges and then draws nothing.

### The image placeholder advances ONE cell, on every host — measured 2026-09-02, iTerm2 added 2026-09-04

U+10EEEE, the Kitty protocol's Unicode image placeholder, sits inside the
Plane-16 Private Use Area — the range this document records as painted two
cells and advanced one on every measured host, because that range is where SF
Symbols live. The placeholder is the exception, and it has to be, because
`FrameDiffWriter`'s Plane-16 compensation (`ECH` + glyph + `CUF`) applied to a
picture would move every column of it one cell further right than the last.

Measured with `Tools/TerminalProbes/placement_probe.py`: a row of twelve
placeholder cells written on a cleared row, with the cursor asked where it
landed, against twelve `x` characters.

| Host | plain text | placeholders, diacritics on every cell | placeholders, run-length elided |
|---|---|---|---|
| Ghostty 1.3.1 | 12 | **12** | **12** |
| Warp v0.2026.08.26… | 12 | **12** | **12** |
| Apple Terminal 455.1 | 12 | **12** | **12** |
| iTerm2 3.6.11 | 12 | **12** | **12** |

**Including the two hosts that do not implement the protocol.** No font carries
the codepoint, so it is not painted two cells the way an SF Symbol is; a host
that implements placements intercepts it, and one that does not draws nothing
and moves on. iTerm2's row was the gap this table carried as *not measured*
until 2026-09-04: run from inside an iTerm2 window, `placement_probe.py`
advances one cell per placeholder and draws the card correctly (hue L→R,
fade T→B) — so iTerm2's decode is specification-ordered and its only defect is
that it treats the spec-optional third diacritic as required (the desktop bug
report, and `KittyGraphics+Placeholders.swift`, cover that; the encoder writes
all three marks, so TUIkit is unaffected). Either way it is one cell, which is why the exemption is by
codepoint (`Unicode.Scalar.terminalImagePlaceholder`) rather than gated on
detection.

Three further things that run settled, each of which the encoder would
otherwise have had to guess:

- **Run-length elision works.** A cell with no diacritics continues the
  previous one; a 12-cell row costs a fraction of its explicit form. TUIkit does not
  use it — see `Documentation/Terminal graphics protocols.md` — because a
  self-describing cell survives being written out of sequence and an elided
  one does not.
- **Both id encodings work** — through the 256-colour foreground (`38;5;n`)
  and through a direct-colour triple.
- **Delete by id frees the image**: `a=p,U=1` on a deleted id answers
  `ENOENT: image not found` where it answered `OK` before. Ghostty
  acknowledges the delete itself with silence, so the placement request is the
  only usable evidence.

**Cost, Ghostty at 49×17 cells with 16×34-pixel cells:** a full-screen image is
1.8 MB of base64, transmitted and acknowledged in 43 ms. One-time per image and
size, not per frame.

> **`q=2` or the terminal talks back into your keyboard.** Every graphics
> command is acknowledged with `ESC_G…;OK ESC\` unless suppressed, and in an
> application those bytes arrive on **stdin**, where the input parser reads
> them as keystrokes. Anything on a render path sets `q=2`.

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

| Cluster | Claim | Terminal.app 455.1 | iTerm2 3.6.11 | Ghostty 1.3.1 | Warp 2026.07.08 / 08.26 |
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
| ⤷ *(modelled + pulled back with `CUB(1)` since 2026-08-28 — it used to fall through to the claim and mis-enter the FE0F form's store surgery)* | | ✓ | | | |
| 👍🏽 (SMP base + skin) | 2 | **4** | 2 (merged) | 2 (merged) | **4** |
| ✊🏻 (BMP emoji-pres. + skin) | 2 | **4** | **4** (swatch) | 2 (merged) | **4** |
| ☝🏽 (BMP text-pres. + skin) | 2 | **3** | **3** (swatch) | **1** | **3** |
| ☝️🏽 (…+ VS-16) | 2 | **3** | **3** | **4** | **4** |
| ⤷ *(normalized since 2026-08-28 — the redundant selector is stripped by the non-Apple walks, so what those hosts receive is the ☝🏽 row above; Apple's separation re-promotes it identically either way)* | | ✓ | ✓ | ✓ | ✓ |
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
| iTerm2 3.6.11 | painted *(not reproduced — see the revision below)* | unbroken run *(ditto)* |
| Ghostty 1.3.1 | painted *(not reproduced for SF Symbols — see below)* | unbroken run *(ditto)* |

`withTerminalAppCursorCompensation` therefore
emits **ECH** (`CSI n X`) before the cluster: it erases n cells from the cursor
in the current background and does not move it, so the glyph is then drawn over
cells that already carry the fill. Measured identical advance (2), unbroken
fill, and the glyph is NOT clipped by the erase.

**REVISED 2026-08-28 — the fix is NOT Terminal.app's alone.** User-reported
from the live app (SF Symbols on a coloured run showed the default background
under their second cell on both iTerm2 and Ghostty), then card-measured
(`bgfill` treatment card: each under-advancer drawn three ways — bare `CUF`,
`ECH`+glyph+`CUF`, glyph+styled-space — on a blue run, DSR-verified nets):

- **iTerm2 3.6.11** (alternate screen): SF Symbols, keycaps AND VS-16
  clusters all left the skipped cell at the default background with `CUF`
  alone; both the `ECH` and styled-space variants filled it, with the glyph
  intact. This contradicts the 2026-08-23 row above, which did not reproduce;
  the walk now erases, which is correct under both readings.
- **Ghostty 1.3.1**: only SF Symbols showed the hole — the one class whose
  claimed second cell Ghostty (grid-strict, 1-cell symbol) never paints at
  all. VS-15 chrome (ink across both cells) showed no hole, and `ECH` under
  it measured harmless.

`withITerm2CursorCompensation` and `withGhosttyCursorCompensation` now use the
same `ECH` + glyph + `CUF` shape as Terminal.app — and `withWarpCursorCompensation`
followed the same day, when the Warp tone card showed a lone 🇦 with the
default background under the right half of its ink. Only tmux remains
bare-`CUF`, pending the same coloured-run measurement.

ECH rather than "n spaces, then CUB(n)", which also works and was tried first:
the spaces are visible CHARACTERS, so every width measured after compensation —
`strippedLength` above all — inflates by the width of each emoji on the line.
ECH writes none.

Also measured, on the same run: an ECH-compensated cluster, a natively 2-cell
cluster (`📁`), and plain ASCII each put the character AFTER them in the same
column. The layout arithmetic is exact; what remains is only how Apple's font
paints a narrow glyph inside the two cells it owns.

#### The skin-tone path needed the same erase — FIXED 2026-08-26 (strip-era; SUPERSEDED 2026-08-28)

> This section documents the STRIP-era treatment: a text-presentation tone
> cluster had its modifier removed and `U+FE0F` restored. Since 2026-08-28 the
> modifier is KEPT — the cluster is rewritten as the VS-16-promoted base +
> ZWNJ + modifier (see the treatment-card table) — but the finding stands:
> the promoted form is a paint-2/advance-1 under-advancer, and the
> `ECH`-before-glyph this section measured is exactly what the new emission
> wraps the whole rewritten cluster in.

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

**Measured** (`row_probe.py` — retired 2026-08-28, see `Tools/TerminalProbes/README.md` — with `PROBE_ALT=1`, Terminal.app
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

### Three shears only a real page revealed — 2026-08-26

Checking the Example emoji page on each client, cluster by cluster, found three
advance errors that every unit test and every row-width check had passed.

| host | cluster | claim | model said | terminal does |
|---|---|---|---|---|
| Warp | SF Symbols (Plane-16 PUA) | 2 | 2 | **1** |
| Ghostty | ☝🏻 ✌🏼 ✍🏽 ⛹🏾 (BMP base + tone) | 2 | 2 | **1** |
| iTerm2 | ❤️‍🔥 🏳️‍🌈 (VS-16-leading ZWJ) | 2 | 2 | **1** |

Warp's was the visible one: its model was the only one of the five with no
Plane-16 case, so every SF Symbol sheared its row a cell left and the emoji
page's SF Symbols panel drew its right border displaced, with the scrollbar
jammed against it. Ghostty's and iTerm2's are on rows that have been on that
page all along; iTerm2's had been documented as unhandled for months.

All three are fixed by the same means the framework already uses: the model
reports what the terminal does, and the existing CUF closes the gap.

**The methodological point, and it is the one worth keeping.** A row-width
check does NOT find these. The framework and the model share the same numbers,
so a model that is wrong about the terminal produces rows that add up perfectly
and still render wrong — verified directly: with Warp's Plane-16 case removed,
every one of the 44 rows still summed to exactly the terminal width while every
SF Symbol sheared. Self-consistency is not correctness, and only a measurement
against the terminal tells them apart.

`Tools/TerminalProbes/page_clusters_probe.py` is that measurement: it takes the
clusters an app actually draws — 90-odd for this page — and measures each on
the terminal under test. A hand-picked battery cannot do the same job, because
a battery only contains what somebody already thought to doubt.

### The claim follows the host now — 2026-08-26

For most of this document's life the **claim** — how many cells TUIkit's layout
reserves for a cluster — was host-independent, on the reasoning that it must
cover the widest painter so content is never overwritten, with narrower painters
taking a blank cell rather than a shear. That holds when the spread is one cell
(an SF Symbol: 2 on Apple Terminal, 1 on Ghostty). It does not hold when the
spread is nine, which is what 👨‍👩‍👧‍👦 costs on a host that does not compose
ZWJ sequences.

Where the claim could not stretch, TUIkit **substituted**: stripped the
Fitzpatrick modifier, so 👍🏽 reached the screen as 👍. That kept every row
aligned and changed what the user wrote. Taken to its conclusion the same
remedy turns 🏳️‍🌈 into 🏳️ — a pride flag into a white flag, which is not a
rendering compromise but a different message.

So the claim follows the host, and the layout accommodates the true width. A
cluster Warp draws across eleven cells is allocated eleven: the border lands
where it should, text wraps around it, and every scalar survives.

**The two rules, measured on the alternate screen.**

| host | ZWJ sequences | skin-tone clusters |
|---|---|---|
| Apple Terminal 455.1 | **decomposed reservation** (painted composed) | base + swatch |
| iTerm2 3.6.11 | composed, 2 | base + swatch on a **BMP** base only |
| Ghostty 1.3.1 | composed, 2 | merged, 2 |
| Warp 2026.07 | **decomposed** | base + swatch |
| tmux 3.7b | composed, 2 | **not modelled — still stripped** |

**tmux is deliberately not widened**, and the reason is worth recording because
it is the one host whose skin-tone widths do not follow a rule this model can
state. Measured 2026-08-26 on 3.7b:

| cluster | tmux advance | a base-plane rule predicts |
|---|---|---|
| 👍🏽 🙏🏽 👋🏽 | 2 (merged) | 2 ✓ |
| 🤙🏽 🤚🏽 | **4** | 2 ✗ — also SMP, and they do NOT merge |
| ✊🏻 ✌🏽 ✍🏽 | 4 | 4 ✓ |
| ☝🏽 | **4** | 3 ✗ — a 1-cell base, so base-plus-two gives 3 |

The line falls between Unicode 6.0 modifier bases (👍 🙏 👋) and 9.0 ones
(🤙 🤚), i.e. where tmux's own Unicode data has a modifier base and where it
does not. That is a per-codepoint fact, not a plane or a base width, so until
the whole modifier-base set is measured tmux keeps the old behaviour and the
modifier is stripped: a claim that is wrong in **both** directions misaligns
rows, whereas the strip at least aligns them.

**A tmux rendering defect, distinct from all of this.** While checking the
Example emoji page under tmux, both the BMP skin-tone row and the ZWJ row came
out visually scrambled — brackets displaced, adjacent clusters merged. That is
**not** a width miscount and not TUIkit's: drawing the identical row with no
TUIkit involved, `[c] [c] [c] …` written straight to a tmux pane, reproduces it
exactly, and the arithmetic is right to the cell (measured 29, expected 29).
tmux's cursor accounting says 2 per cluster and its painting does not match.
The BMP row is broken identically on `main`, so it predates the width work. It
is a tmux bug to report, not a TUIkit one to fix.

**How it was caught** is the point. The unit tests passed, the geometry probes
passed, and the defect appeared only when the Example emoji page was rendered
under tmux on a real terminal: the Fitzpatrick row came out SHORT, leaving
unpainted cells at the right edge — which is precisely the defect the strip was
introduced to avoid. Widths that are wrong in a way no synthetic probe asks
about still show up on a real page.

- **Decomposed ZWJ** is the sum of the ZWJ-separated segments **plus one cell
  per joiner** — the joiner takes a column. That predicts every measured case:
  👩‍🚀 = 2+1+2 = 5, 👨‍👩‍👧‍👦 = 11, and 👩🏽‍🚀 = 4+1+2 = 7, the last of which
  resolves its first segment through the skin-tone rule, so the two compose
  rather than duplicating each other.
- **A detached skin tone** is the base's width **plus two** for the swatch:
  👍🏽 and ✊🏻 at 4, ☝🏽 at 3 (a 1-cell text-presentation base). A redundant
  VS-16 on the base (☝️🏽) does NOT widen the claim, because since
  2026-08-28 the walks strip it before emission — the modifier alone
  forces emoji presentation (UTS #51), and the normalized pair is the
  measured-aligned one on both detaching hosts (iTerm2 painted the spelled
  form in 3 cells against the promoted claim of 4, a one-cell hole; Warp
  painted it in 4 where the normalized pair takes 3).

**Claim equals advance for every one of these**, because they are all cases
where the host is self-consistent — it advances as far as it paints. So the
compensation machinery simply stops firing: no CUF, no ECH, no rewrite, and the
Fitzpatrick strip no longer triggers because the over-advance it existed to
prevent is no longer an over-advance.

**Verified on the terminals, by the test that cannot be misread.** A row is
budgeted at the claim and filled; if the cursor's ROW number changes, the
budget was too small and the line wrapped.

| cluster | old claim | at the old claim | new claim | at the new claim |
|---|---|---|---|---|
| 👍🏽 (Apple) | 2 | **wraps** | 4 | fits |
| 👩‍🚀 (Apple) | 2 | **wraps** | 5 | fits |
| 👨‍👩‍👧‍👦 (Apple) | 2 | **wraps** | 11 | fits |
| 👩‍🚀 (Warp) | 2 | **wraps** | 5 | fits |
| 👨‍👩‍👧‍👦 (Warp) | 2 | **wraps** | 11 | fits |
| 👍, 中 (controls) | 2 | fits | 2 | fits |

So the widened claim does not introduce the ragged right edge that drove the
Fitzpatrick strip — **it removes its cause**. A kept modifier at a 2-cell claim
over-runs the line; at a 4-cell claim it fits exactly and the tone survives.

Also checked, on both hosts: full-width rows in normal AND inverted (selection)
video end exactly on the last column — 10/10 on Warp including the 11-cell
family, and every widened case on Apple Terminal. And mid-row, a two-colour
probe (background before the cluster, a different one after) shows **no
unpainted cell** between them: the "swatch" of a detached skin tone is ink, so
every cell the cluster owns is painted.

**Where the claim over-reserves, the existing CUF closes it.** ❤️‍🔥 and 🏳️‍🌈
lead with a VS-16 segment, which Apple Terminal under-advances, so they advance
4 against a claim of 5. The per-host advance model reports 4, the compensation
emits `CUF(1)`, and the cluster lands exactly on the claim — measured. This is
the same trade already accepted for a Ghostty SF Symbol that paints narrower
than the layout allocated.

**Cost.** Measured with `Tools/Profiling/ab_bench.py` over six scenarios
(`megalist`, `kitchensink`, `textwall`, `deep`, `dashboard`, `table`): all six
indistinguishable, −0.5% to +0.0%. The first attempt showed `megalist` at
+1.3%, which turned out to be an inlining artifact — the widening path is now
`@inline(never)` so `terminalWidth`'s inlinable body barely grows, and the
regression disappeared. A null A/B (the same binary against itself) confirmed
the harness resolves ~1% on that scenario, so the effect was real and so is its
absence.

**What this does NOT cover.** Only the two classes TUIkit was substituting —
the ones that can change a message. Classes that merely misalign are unchanged
and still limitations: Warp's keycaps and 〰️ at 3 cells against a claim of 2,
and its tag-sequence flags at 3. Each needs its own measured rule, and none of
them alters what the user said.

### ZWJ: where DSR lies, and where the defect actually is — measured 2026-08-26

> **SUPERSEDED 2026-08-27 — kept as history.** The conclusion below ("the
> claim of 2 is correct and no compensation is wanted") was the second wrong
> answer for this class: the composed glyph paints 2, but the row wraps at the
> internal width AND the stored width displaces everything later on the row.
> The shipped treatment is software decomposition — see the treatment table at
> the top of this host's section. The measurements below remain correct as
> measurements, and the Warp analysis stands.

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

> **CORRECTED 2026-08-26 (same day).** The row below originally read
> "Terminal.app … rows shear? **no**", on the strength of an alignment card
> read by eye. That was wrong, and the error was mine: a row budgeted at a
> 2-cell claim **wraps** on Terminal.app, measured by the cursor's ROW number
> changing — a state the terminal enters, not a number it reports. What is
> true is narrower and is kept below: Terminal.app *paints* the cluster
> composed into about two cells while *reserving* five. The glyph looks right
> and the row still over-runs. The primary/alternate difference I blamed does
> not exist here either: both buffers give 5 / 8 / 11.

| host | composes a ZWJ cluster? | painted cells | reserved | rows shear at a 2-cell claim? |
|---|---|---|---|---|
| Terminal.app 455.1 | yes, one glyph | **2** | 5 / 8 / 11 | **yes — wraps** |
| iTerm2 3.6.11 | yes | 2 | 2 | no |
| Ghostty 1.3.1 | yes | 2 | 2 | no |
| tmux 3.7b | yes (own grid) | 2 | 2 | no |
| Warp 2026.07 | **no — draws the components** | **4–11** | 4–11 | **yes — wraps** |

On Terminal.app the astronaut, the four-person family, the England tag flag,
👍 and 中 all put their `X` in the **same column**, though DSR claimed 21, 39,
30, 12 and 12 for those rows. The composed glyph is two cells and printing
resumes two cells along; only the *report* runs ahead.

**Both hosts are affected, in different ways.** Warp does not compose ZWJ at
all — 👩‍🚀 draws as 👩 then 🚀 — so paint and reservation agree with each
other and disagree with a 2-cell claim. Terminal.app composes the glyph but
reserves the same decomposed width, so it looks right and still over-runs. On
both, a row budgeted at 2 wraps; on both, budgeting the reserved width fixes
it. Warp COMPOSES tag-sequence flags into one glyph — but advances and lands
them at 3 against the 2-cell claim (`flag_scotland` in its landing ledger; a
recorded known divergence, uncorrectable forward), so the class is aligned
everywhere except Warp, where it shears one cell.

**The lesson, again.** The paint card was the right instrument for the
*previous* question (does 🀀 paint one cell or two) and the wrong one for this
one. Neither a cursor report nor a glyph's appearance answers "how much room
does this cluster consume". The instrument that does is a row budgeted at the
claim: if the cursor's ROW changes, the budget was too small. That is a state
change, and it cannot be misread.

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

**A residual, genuinely broken — RESOLVED 2026-08-27:** VS-16-leading ZWJ
(❤️‍🔥 ⛓️‍💥 🏳️‍🌈) on Terminal.app misbehaves visibly — in the same probe its
separating pipes were overpainted and the `X` landed left of the others. Under
software decomposition the leading VS-16 segment gets its own `ECH`'d
under-advance treatment (❤️‍🔥 → `ECH(2)` ❤️ `CUF(1)` 🔥, claim 4), which the
treatment cards measured clean: aligned, background intact, edge-safe.

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
  models (TUIkitCore), pinned to the committed measurement records in
  `Tools/TerminalProbes/data/` by `TerminalLedgerConformanceTests` (which
  also carries the known-divergence ledger), with spot batteries in
  `GhosttyWarpCompatibilityTests` / `StringTerminalWidthTests`.
- `KeyEvent.normalizingLegacyShiftedFunctionKeys()` +
  `Terminal.finalize` — Apple Terminal's shifted-function-key re-coding
  (F13…F20 read back as Shift+F5…F12), gated on `TerminalHost.isAppleTerminal`.
- `String+CursorCompensation.swift` — the per-host line rewriters.
  `withCursorForwardCompensation(advance:)` is the shared erase-and-push
  walk (iTerm2, Ghostty, Warp, tmux), which also drops ZWJ joiners and the
  redundant tone VS-16 where the traits say so; Terminal.app keeps its own
  walk for its rewrites (tone separation) and store surgery.
  `String.withSkinToneFallback(scope:)` — the swatch strip: live only for
  tmux (the measured `.keepingTmuxMerged` set) and as the no-traits
  fallback on iTerm2/Warp.

### Per-host output pipeline (FrameDiffWriter)

The branch is checked in this order, **tmux first** — its grid is what our
output lands in, so it must win over any native host flag that leaked into the
pane. (`FrameDiffWriter.init` also zeroes the four native flags when `isTmux`,
so the tmux-first rule holds at the clip and right-edge repaint too, not only
here.)

| Host | Clip | Then |
|---|---|---|
| tmux | plain | `withSkinToneFallback(scope:)` (`.keepingTmuxMerged` when every client renders kept tones, `.all` otherwise — per-client, push-refreshed) → `withTmuxCursorCompensation()` |
| Apple Terminal | cursor-aware | `withTerminalAppCursorCompensation()` |
| iTerm2 | plain | `withITerm2CursorCompensation()` (the strip is inert under the published `.detachedOnBMPBases` claims — no-traits fallback only) |
| Ghostty | plain | `withGhosttyCursorCompensation()` |
| Warp | plain | `withWarpCursorCompensation()` (strip inert under `.detached` claims, as iTerm2) |
| anything else | plain | **untouched** (compensation would corrupt a correct terminal) |
- `FrameDiffWriter` — applies the rewriters on its build path; Apple-only
  right-edge repaint.
- `ToggleCharacterSet.automatic` + `SwitchIndicatorGlyphs` — chrome glyph
  selection per host.

#### The animation replay reset to the TERMINAL's background — FIXED 2026-08-29

Every styled fragment ends in `ESC[0m`, and a reset returns the terminal to ITS
default: white on Apple Terminal's light profile, black on a dark one. A
rendered row has the page's background put back after every reset by
`FrameDiffWriter.buildLine`, which is why the Animation page's *fading* text was
fixed by splitting the collapsed `ESC[0;…m` so the restoration could find it.

The *breathing* text was still white, and by the one path that does not build a
row: the animation replay splices a run's frame into an already-built line, and
the frame comes straight from the view having been through neither the
compensation nor the background restoration. Captured under
`TERM_PROGRAM=Apple_Terminal`, one tick read

```
ESC[38;3H ESC[0;38;5;34m Still here, still breathing. ESC[0m
```

— no background code anywhere in it, so the run's own cells took the terminal's.
The restoration is now a shared function that `patchingAnimatedRun` applies to
the frame before compensating it; the same capture now reads
`ESC[0;38;5;34;48;5;16m`.

#### The animation replay compensates a second time — FIXED 2026-08-29

A row is compensated when it is rendered. When an `AnimatedCellRun` on that row
ticks, the replay splices a fresh frame over the run's cells — and compensates
THAT, because the frame may carry a different cluster from the one the render
drew (a spinner's frames do).

Both walks therefore own the same cells, and the splice works in COLUMNS while
an escape claims none: the `ECH` the render put before the cluster and the `CUF`
it put after both survived, on either side of a frame that had brought its own
pair. The row was left one `CUF` long and every cell after the run sat one place
to the right — until the next full render redrew it correctly, so the offset
came and went with no period.

Reported against a focused `Toggle` in **Ghostty**, whose `⬜︎` (a chrome glyph
under VS-15) is compensated there and bare on every other host — so only Ghostty
showed it for that glyph. The class is not Ghostty's: the conservation test added
with the fix catches it on Apple Terminal and iTerm2 too, with `⚙️`.

Fixed at the splice (`FrameBuffer.patchingAnimatedCells`), which now removes the
render's compensation for the columns it is replacing before inserting the
frame. Which side a pair belongs to is decided by KIND, not position: at the
span's far edge an `ECH` introduces the cluster AFTER the span and stays, while
a `CUF` there closes the last cluster INSIDE it and goes.

Measured on the Example's Toggles page, Ghostty, the focused row:

    render   ESC[2K ' ' SGR ESC[2X ⬜︎ ESC[1C SGR ' ' SGR 'Enable…'
    replay   ESC[2K ' ' SGR ESC[2X SGR ESC[2X ⬜︎ ESC[1C SGR ESC[1C SGR ' ' …
                              ^^^^^^^^^^^^^^ frame's own pair    ^^^^^^^ leftover

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

## Right-to-left text — measured 2026-09-01, in part

Run in each host with `Tools/TerminalProbes/bidi_card.py`, in the four installs
this document records elsewhere (no version was re-checked at the time). The
card prints nine-cell samples as `|<sample>|X` rows, twice: `plain` as TUIkit
would emit them today, and `forced` with each RTL run wrapped in U+202D LEFT-TO-
RIGHT OVERRIDE … U+202C POP DIRECTIONAL FORMATTING.

| Host | `plain` — RTL runs keep their columns | `forced` — the LRO/PDF controls |
|---|---|---|
| Apple Terminal.app | ✓ every X aligned | ✗ **painted as the missing-glyph box**, one cell wide, shifting every X one column right |
| iTerm2 | ✓ | ✓ consumed at zero width — every X still aligned |
| Ghostty | ✓ | ✓ consumed at zero width |
| Warp | ✓ | ✓ consumed at zero width |

**The decision this settles: TUIkit does not emit the override.** It was the
candidate fix for RTL, and on Apple Terminal — the one host RTL was reported
against — it is a visible regression: two junk glyphs per run and a column of
shear per run, in a host that was already painting the plain row's columns
correctly. The other three neither need it nor object to it. A per-host quirk
could apply it to those three only, but nothing measured here asks for one.

**What the card does not answer.** The X column tests *advance*, and a terminal
implementing the Unicode bidirectional algorithm does not change it: every row
here begins with ASCII, so the paragraph direction is LTR and an RTL run is
reversed *within the columns it already occupies*. Reordering therefore garbles
a run's contents without shearing the layout, which is consistent with the
original report ("using a Hebrew character messes up rendering") and with this
card showing every plain X aligned. A copy-paste cannot settle it either, since
the buffer hands back logical order however it was painted.

One row does expose it to a reader who does not read Hebrew: under the
algorithm `digits_after_rtl` (`אב 123 ab`) displays as `123 בא ab` — the digits
jump to the *left* of the Hebrew, hard against the opening `|`. The card now
says so on the row itself. Until someone reads that row in each host, "does
this terminal reorder?" stays open, and the answer changes nothing about the
override, which is refused on Terminal.app either way.

**The arithmetic is settled.** The bidi controls — LRM, RLM, ALM, the
embeddings and overrides (U+202A…U+202E) and the isolates (U+2066…U+2069) —
are `Default_Ignorable_Code_Point` with no advance, and TUIkit measured them as
one cell each until 2026-09-01. A line carrying one, as text pasted from a
bidirectional document does, measured a cell wider than it drew. They are
zero-width now (`BidiControlWidthTests`).

### RTL characters as image PIXELS — measured 2026-09-01, still OPEN

**Apple Terminal mirrors a picture made of right-to-left glyphs.** A
`TUIkitImage` `.customRamp` of Hebrew letters draws a gradient whose flat end
comes out at the wrong side of every row. The stakes differ from text:
reordering a run of letters is arguably the right thing there and merely looks
odd, but in a picture every character is a pixel, so moving one is corruption
with nothing gained.

`Tools/TerminalProbes/rtl_image_card.py` draws a gradient whose flat run of one
repeated glyph grows along the LEFT edge row by row, so the reading needs no
Hebrew — reversal moves that block to the right, against an ASCII control
drawing the same picture. Read on Apple Terminal:

| Block | Apple Terminal |
|---|---|
| `control` (ASCII ramp) | flat run on the left — this is the picture |
| `hebrew` | flat run on the **right** — mirrored |
| `coloured` (an SGR per cell) | mirrored, identically — the colour changes make no difference |
| `lrm` (U+200E after each cell) | flat run back on the **left**, and every `X` still in one column |
| `positioned` (`ESC[nG` per cell) | mirrored, identical to `hebrew` |

Two of those are settled and one is not:

- **The host reorders what it has STORED, not what it is handed.** Cursor-
  addressing every cell changes nothing, so `FrameDiffWriter`'s span machinery
  was never going to be the answer.
- **It is not the finished line's SGR structure**, since a colour change per
  cell leaves the result identical.
- **U+200E is NOT (yet) the fix, whatever that table says.** Emitting it from
  `ASCIIConverter` for every RTL glyph was tried (171c39c4) and REVERTED
  (this commit): in the Example's Image page it does not merely fail to help,
  it destroys the page — the controls panel is drawn tens of columns left of
  where it belongs and the right of the screen goes unpainted.

**What the card's `lrm` block does not cover, and what the real render adds.**
The card's rows are plain text, about forty cells wide, and stand alone. An
image row is full width, carries a foreground change per cell, and sits inside a
composed layout with a panel beside it. Somewhere in that difference the mark
stops being free. It is not TUIkit's arithmetic: captured from the running app
with `TERM_PROGRAM=Apple_Terminal`, every emitted row is exactly the terminal's
width in cells with the marks costing nothing, no cursor compensation fires, no
right-edge repaint fires, and `strippedLength`, `ansiAwarePrefix` and
`ansiAwareSlice` all measure a marked row as its cell count and not its scalar
count.

The card now has two more blocks — `lrm+coloured` and `lrm+wide` — which are
exactly the two axes the working block lacked. Until those are read, the mark
is not emitted.

**The first version of the probe measured nothing, and why is the useful part.**
It drew a staircase out of ONE repeated Hebrew letter and blanks. A run of
identical characters looks exactly the same reversed, and the blanks are
neutrals which at end-of-line take the paragraph's own direction and do not
move — so a host doing precisely what is suspected drew that card correctly, and
Apple Terminal did. **A card about ordering has to be made of things that can be
told apart** — and, this round's lesson, a card about a rendered PAGE has to be
made of rows like the page's.

That leaves **a known divergence on Apple Terminal in the other direction**: it
paints U+202D and U+202C as a box that occupies a cell TUIkit no longer counts.
Only those two were measured there; the rest of the family was not tested
individually, and the box strongly suggests the host treats none of them as
default-ignorable. Zero is still the right number for three hosts out of four
and for the standard, and TUIkit emits none of these controls itself — this can
only arrive in content the user pastes.

## Complex scripts — 38 corpus rows, and NOT ONE of them measured

Added to the corpus 2026-09-04. Every one is listed in
`TerminalLedgerConformanceTests.awaitingLandingMeasurement`, which is what stops
"nobody has asked a terminal" from reading as "the models pass". **Nothing below
is a measurement. It is a list of questions.**

### Why they exist

Until this date the corpus was emoji, flags, selectors and Plane-16 PUA: 78 rows
whose most complicated member was a four-person ZWJ family. That is not the
whole of what a terminal is handed, and it left one question with no sample able
to ask it.

`Character.terminalWidth` has two rules that answer for the same scalars. The
**cluster** rule (`String+TerminalWidth.swift`) answers a flat **2** for any
multi-scalar cluster carrying a scalar that adds width. The **per-scalar** rule
(`Unicode.Scalar.loneTerminalWidth`) prices each scalar and sums: a combining
mark 0, a consonant or a spacing matra 1. For every cluster in the old corpus
the two coincide, because an emoji sequence has exactly two advancing scalars —
a base and a modifier, or a base and a joined base — and 1 + 1 = 2.

Unicode 15.1's rule GB9c broke the coincidence. Swift 6.2 implements it, so a
Devanagari conjunct is ONE grapheme cluster however many consonants it stacks:

| Cluster | Scalars | Cluster rule | Per-scalar rule |
|---|---|---|---|
| क्ष | U+0915 U+094D U+0937 | 2 | 2 — agree |
| स्त्र | U+0938 U+094D U+0924 U+094D U+0930 | 2 | **3** |
| ष्ट्र | U+0937 U+094D U+091F U+094D U+0930 | 2 | **3** |
| स्त्री | U+0938 U+094D U+0924 U+094D U+0930 U+0940 | 2 | **4** |

The framework therefore contains two answers for the same text, and which one
you get depends only on whether the standard library fused it — nothing about
the host. `ComplexScriptWidthTests` records both numbers for every new row and
wraps the disagreements in `withKnownIssue`, so they are visible in every test
run and neither answer can quietly become the other.

**Five of the 38 rows disagree, and not all in the same direction.** Asking
every new row rather than only the Indic ones turned up a second divergence
pointing the other way:

| Row | Cluster rule | Per-scalar rule | Which is suspect |
|---|---|---|---|
| स्त्र `conjunct_deva_stra` | 2 | 3 | the cluster rule's 2 |
| ष्ट्र `conjunct_deva_shtra` | 2 | 3 | the cluster rule's 2 |
| स्त्री `conjunct_deva_stri` | 2 | 4 | the cluster rule's 2 |
| U+1112 U+1161 U+11AB `hangul_jamo_lvt` | 2 | 4 | the per-scalar rule's 4 |
| U+1112 U+1161 `hangul_jamo_lv` | 2 | 3 | the per-scalar rule's 3 |

한 is two cells however it is spelled, so the cluster rule is right about the
jamo and the per-scalar rule is wrong: it prices the conjoining V and T jamo at
one cell each, where `wcwidth` gives the whole U+1160…U+11FF range zero. That
is why "make one rule call the other" is not the fix for either half.

Both rows are pinned rather than repaired, because what a host does with a bare
jamo is as unmeasured as the rest of this section. A composed syllable always
reaches the cluster rule and is claimed 2, which is right; the per-scalar 1 is
only reachable for a **lone** V or T jamo — orphaned text, not a spelling of a
syllable — and no terminal has been asked what it advances one by. Correcting
it to `wcwidth`'s zero would be a change nothing here measured, in a file whose
per-scalar answers are otherwise derived from measurements.

**The rule has not been changed, and must not be, until these rows are
measured.** Under a wcwidth-per-codepoint host (Ghostty, kitty, xterm, VTE, tmux)
3 is the plausible answer; under a grapheme-cluster host (DEC mode 2027) 1 is.
Both differ from 2, in opposite directions. This project has twice drawn a wrong
conclusion from one of a row's four facts, and this would be the third.

### What the 38 rows cover

- **`indic_conjunct`** — Devanagari क्ष स्त्र ष्ट्र स्त्री, Bengali ক্ষ, Telugu క్ష.
  The GB9c fusions, at two, three and four advancing scalars.
- **`virama_final`** — Tamil ஸ், Kannada ಕ್, Khmer ក្. GB9c's `InCB=Linker` set
  is six scripts, and these three are not in it: க்ஷ, ಕ್ಷ and ក្ក are each **two**
  grapheme clusters, so the half-form is the whole cluster and a shear would be
  per half rather than per conjunct.
- **`spacing_vowel_sign`** — कि को कौ किं ரா កា. `Mc` marks, which the per-scalar
  rule says advance and the cluster rule prices at 2.
- **`nukta`** — क़ ड़. A non-advancing `Mn` that changes the glyph.
- **`chillu`** — ൻ atomic against ന്‍ spelled with a ZWJ: the same Malayalam
  letter reaching two different code paths, the second of them the one shaped
  for emoji.
- **`thai_lao`** — ก่ กิ้ กำ ກີ່. Stacked marks, plus sara am, which is a
  *spacing* vowel.
- **`tibetan_stack`** — ཀྐ ཀྐུ. A vertical stack of three scalars in one cell.
- **`arabic`** — the lam-alef ligature as its presentation form U+FEFB, بَ, بَّ.
  (The لا a keyboard produces is U+0644 U+0627: two letters, two clusters, so
  the corpus cannot hold a row for it — shaping is the renderer's business.)
- **`hebrew_points`** — בִ, בָּ. Marks inside a right-to-left run.
- **`hangul_jamo`** — U+1112 U+1161 U+11AB and U+1112 U+1161: 한 as conjoining
  jamo rather than the precomposed U+D55C already in the corpus.
- **`format_control`** — a‍ a‌ (letter + ZWJ / ZWNJ, which is what pasted Indic
  or Arabic text and a truncated emoji both leave), and LRM/RLM alone.
- Plus **Ａ** (fullwidth Latin) in `cjk` and **e◌́◌̈◌̧** (three stacked NFD marks)
  in `combining`.

### Measure them

The DSR half needs no display, no screenshot and no Screen Recording grant —
`advance_probe.py` carries all 38 under the same ids as the corpus:

```sh
cd Tools/TerminalProbes
PROBE_ALT=1 PROBE_OUT=data/<terminal>-<version>-alternate.json python3 advance_probe.py
```

The full four facts — advance, landing, ink, reserve — come from the landing
pair, which reads `data/width-corpus.json` and so already carries every row:

```sh
cd Tools/TerminalProbes
PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap
python3 landing_analyze.py /tmp/landing.json \
    -o data/<terminal>-<version>-alternate-landing.json
```

Run both inside each of the four hosts this document records, then delete the
measured ids from `awaitingLandingMeasurement`. Read `advance` before believing
anything: it is the internal column, which governs wrapping, and on Apple
Terminal it has disagreed with the paint by nine cells.
