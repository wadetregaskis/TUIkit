# Terminal probes

Reproducible measurement tools behind `Documentation/Terminal-compatibility.md`.
Run each INSIDE the terminal under test; the recording probes (advance,
mouse) write to `$PROBE_OUT` (mouse falls back to `./mouse_probe.log`
when unset), the visual/aspect probes print to the terminal.

- `advance_probe.py` — DSR (`ESC[6n`) cursor-advance measurement of a
  grapheme-cluster battery + terminal-relevant environment dump (JSON).
  `PROBE_ALT=1` measures on the ALTERNATE screen (the app's buffer) —
  iTerm2 advances some clusters differently there.
- `page_clusters_probe.py` — measures every distinct cluster an APP ACTUALLY
  DRAWS, rather than a hand-picked battery: the battery only contains what
  somebody already thought to doubt. **This is the check that separates
  "consistent" from "correct".** Verifying rows against each other cannot:
  the framework and the model share the same numbers, so a model that is wrong
  about the terminal produces rows that add up perfectly and still render
  wrong. Verified — with Warp's Plane-16 case removed, every row still summed
  to the terminal width while every SF Symbol sheared a cell. Found three real
  shears on 2026-08-26 that no unit test saw.
- `probe_stamp.py` — not a probe: the shared provenance stamp every probe
  result carries (date, OS, terminal version, screen buffer, and DEC mode 2027,
  the two conditions this project has been bitten by not recording). It asks
  DECRQM for mode 2027 — and skips it on Apple Terminal, where that query's
  final byte prints to the screen and would move the cursor out from under the
  measurements that follow.
- `data/` — the committed measurement records, one per (terminal, version,
  screen). Written by a probe, never by hand. See `data/README.md`.
- `bidi_card.py` — static `|<sample>|X` alignment card for RIGHT-TO-LEFT
  text, printed twice: plain, and with each RTL run wrapped in
  U+202D … U+202C. Rows whose `X` moves are reordered by the host; if the
  wrapped rows line up and the plain ones do not, the override is the fix
  there. Answers the two questions in Terminal-compatibility.md's
  "Right-to-left text" section, which is otherwise unmeasured.
- `visual_card.py` — static `|<c>|<c>|<c>|X` alignment card with a column
  ruler, for screenshot inspection of PAINTED width (which DSR can't see),
  merged-vs-split clusters, seams, and swatches. It answers exactly ONE of a
  row's four facts — paint. DSR (advance) governs when the row WRAPS, the
  landing governs where followers go, and the store governs later absolute
  writes: on Apple Terminal a ZWJ sequence paints 2 while DSR reports 5/8/11,
  and a full-width row budgeted at the painted 2 really does wrap (measured
  2026-08-26; an earlier note here concluded "rows do not shear" from the
  paint alone, and was wrong). Confirm a divergence with the wrap test and
  `landing_probe.py`/`treatment_card.py` before compensating — no single
  instrument settles it.
- `background_probe.py` — does the cell an under-advancing cluster's `CUF`
  skipped keep the background in force? Draws each compensation strategy as a
  RUN of clusters, so a one-cell hole reads as stripes on a screenshot, and
  DSR-measures the advance of each at the same time. `PROBE_WIDE=1` draws the
  rows double-width (DECDWL) for the capture.
- `mouse_probe.py` — raw-mode SGR mouse byte capture (1000/1002/1006);
  every input sequence is appended human-readably. `q` quits.
- `identity_probe.py` — asks the terminal WHO it is over escape queries
  (DA1/DA2/DA3, XTVERSION, XTGETTCAP), DSR-fenced so a silent terminal
  cannot stall it. This is the measurement behind identifying a host over
  ssh, where `TERM_PROGRAM` does not survive the hop.
- `cell_aspect_probe.py` — the terminal cell's height:width ratio (what
  `Image` needs to render undistorted), via `TIOCGWINSZ` pixel fields and
  the `CSI 14t`/`18t` escape queries. Report to `$PROBE_OUT` (default
  `./cell_aspect_probe.txt`); stdout stays attached to the terminal for the
  queries themselves.

`palette_probe.py` asks a different question from the rest: not how the cursor
moves, but what colour the terminal actually paints for a name we emit. The
sixteen ANSI colours are slots in the user's scheme, so `SGR 31` is "red" only
by convention — and TUIkit's contrast floor and 256-colour quantiser both
derive from a table of what those slots conventionally hold. Run it in each
host and record the answers in the compatibility document.

Extend the battery in `advance_probe.py` rather than hand-rolling one-off
probes, and record new results (with `TERM_PROGRAM_VERSION`) in the
compatibility document. (`Tools/EmojiBugScanner` is the Swift bulk variant of
the same DSR question — a GENERATED corpus of tens of thousands of clusters,
for sweeps the curated battery cannot cover; its 46k-cluster diff of the
quirks mirror against the hand-written model is how the missing skin-tone
erase was found. Prefer the battery for anything the corpus already names.)

A note on the PTY harnesses: `pyte` drops everything after a **U+FE0F** in the
same write (VS-16 is width 0 with combining class 0, so its `Screen.draw` hits
the `else: break`). A dump containing ⚙️ ⚠️ ✂️ ⚒️ therefore shows a truncated
row whatever the app emitted, which is a trap `tui_walk.py` and
`tui_screens.py` both sit in.

Two ways round it, and they answer different questions. For what a TERMINAL
draws, use the probes here, against the real host. For what the APP emitted,
use `Tools/Smoke/raw_probe.py`, which decodes nothing: it drives the app
through a key script and counts patterns in the bytes themselves — including
whether a cluster carried its cursor compensation, and `--term-program` to
force a host model from any terminal.

## `landing_probe.py` + `landing_analyze.py` — where the next character PAINTS

`advance_probe.py` asks the terminal where its cursor went. These two measure
where the glyph after a cluster is actually drawn, which is not the same
question and is the one a layout needs answered. Apple Terminal reports an
advance of 4 for 🤙🏽 and paints the next character two cells along; every model
built on the report put borders where nothing was drawn.

Run the probe inside the terminal under test:

```sh
PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap
```

then read the pictures:

```sh
python3 landing_analyze.py /tmp/landing.json -o data/<host>-<version>-alternate-landing.json
```

Prefer `PROBE_SYNC=1` and have **another process** take the screenshots (the
probe writes `<shot>.ready` and waits for `<shot>.done`). macOS asks the
terminal to confirm direct screen access and puts the dialog **over the window
being measured**, which hid a calibration mark for five runs. Without Screen
Recording permission the capture fails outright ("could not create image from
display 0") — grant it in System Settings, or fall back to the DSR halves
(`advance_probe.py` measures advance; `--wrap` here measures reserve) and
record the row in `TerminalLedgerConformanceTests.awaitingLandingMeasurement`
until the pixel halves can run.

Both clusters and expectations come from `data/width-corpus.json`, shared with
the Swift tests so a measurement always answers a question something asks.
`TerminalLedgerConformanceTests` is where the records are checked against the
models.

## `border_probe.py` — did any row shear, end to end?

The per-cluster probes say what a terminal does to one cluster in isolation.
This says whether the whole pipeline put the right edge where it belongs on a
screen full of real content: it finds the rightmost inked column of every
scanline and asks whether they agree.

```sh
screencapture -x /tmp/app.png
python3 border_probe.py /tmp/app.png
```

It crops to the app's own painted background first, so the desktop and other
windows cannot contribute an edge, and exits 1 on any outlier — so it can gate a
smoke run rather than only inform one.

## `matrix_probe.py` + `matrix_analyze.py` — the whole truth table in one run

Every corpus cluster × every applicable emission strategy (verbatim, `CUF`,
`ECH+CUF`, `CUB`, `CUB+CUF`, software strip, and the detach candidates: ZWNJ,
DECSC/DECRC separator, SGR separator, absolute positioning), measured in a
single run inside the terminal under test:

```sh
PROBE_OUT=/tmp/matrix.json python3 matrix_probe.py                 # DSR phase
PROBE_OUT=/tmp/matrix.json PROBE_SHOT=/tmp/mx PROBE_SYNC=1 \
    python3 matrix_probe.py                                        # + pixels
python3 matrix_analyze.py /tmp/matrix.json -o data/<host>-matrix.json
```

The DSR phase needs no display and answers, per (cluster, strategy): the net
internal advance, and whether a full-width row wraps — budgeted BOTH at the
composed claim and at the strategy's own advance, because a detach strategy's
premise is that the layout would claim its wider extent. The pixel phase adds
where the next character paints, the glyph's ink, and an APPEARANCE
classification (composed / stripped / detached / other) computed by comparing
each cell against reference glyphs rendered in the same run — no human reads
the screenshot.

Strategies are built from the cluster's advance measured live in the run, not
from a model, so the probe works unchanged on a terminal nobody has measured.

(`row_probe.py`, retired 2026-08-28, asked phase A's wrap question for four
clusters by hand; the matrix asks it for every corpus cluster × strategy.)

## `treatment_card.py` — the shipped emissions, verifiable at a glance

Where `matrix_probe.py` explores every strategy, this shows only the ones the
walk SHIPS for Apple Terminal — each as an expect/actual row pair on a blue
background, so "is it right" is a vertical comparison a human (or a
screenshot diff) makes in seconds. Page 2 ends a full-width blue row with
each emission, which is the white-cells-at-the-row-edge and wrap check.

```sh
PROBE_OUT=/tmp/treatment.json python3 treatment_card.py
```

The DSR half is fully automatic: `PROBE_OUT` records, per row, the net
advance against the claim, where sequential followers ended, where an
absolute CHA landed, and (page 2) whether the row wrapped — each with an `ok`
verdict. The pixel half (alignment of `ab` and `X`, background holes, glyph
appearance) needs eyes or a capture.

Four generations of this card settled the 2026-08-27 treatments: it is how
the ZWNJ separation, the ZWJ decomposition and the flag/keycap `DCH` store
surgery were chosen over the cursor-move repairs they replaced. The emissions
here mirror `String.withTerminalAppCursorCompensation()`, and
`TerminalWidthTraitsTests` pins the same literals on the Swift side.

## `recent_emoji_sweep.py` — does this host's width table know the new emoji?

Fully automatic (no eyes needed): DSR-measures the cursor advance of every
emoji-presentation scalar in the 1FA70–1FAFF block — where new emoji land
version after version — plus controls, and reports the ones the host
advances 1 against the 2-cell claim.

```sh
PROBE_OUT=/tmp/sweep.json python3 recent_emoji_sweep.py
```

First run (2026-08-28, all four hosts): Warp v0.2026.07.08 advances exactly
the seven Unicode 16.0 additions (🪉 🪏 🪾 🫆 🫜 🫟 🫩) by 1 — its width
table is Unicode 15.1 — while Apple Terminal, iTerm2 and Ghostty advance
all 113 by 2. That measurement is `Character.warpCursorAdvance`'s
`unicode16EmojiWarpDoesNotKnow` set. Re-run when a Unicode version ships,
when a terminal updates, or when one emoji misbehaves — the sweep costs
seconds and answers for the whole block; extend `SWEEP` when new emoji land
outside it.
