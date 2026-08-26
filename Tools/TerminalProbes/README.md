# Terminal probes

Reproducible measurement tools behind `Documentation/Terminal-compatibility.md`.
Run each INSIDE the terminal under test; the recording probes (advance,
mouse) write to `$PROBE_OUT` (mouse falls back to `./mouse_probe.log`
when unset), the visual/aspect probes print to the terminal.

- `advance_probe.py` — DSR (`ESC[6n`) cursor-advance measurement of a
  grapheme-cluster battery + terminal-relevant environment dump (JSON).
  `PROBE_ALT=1` measures on the ALTERNATE screen (the app's buffer) —
  iTerm2 advances some clusters differently there.
- `probe_stamp.py` — not a probe: the shared provenance stamp every probe
  result carries (date, OS, terminal version, screen buffer, and DEC mode 2027,
  the two conditions this project has been bitten by not recording). It asks
  DECRQM for mode 2027 — and skips it on Apple Terminal, where that query's
  final byte prints to the screen and would move the cursor out from under the
  measurements that follow.
- `data/` — the committed measurement records, one per (terminal, version,
  screen). Written by a probe, never by hand. See `data/README.md`.
- `visual_card.py` — static `|<c>|<c>|<c>|X` alignment card with a column
  ruler, for screenshot inspection of PAINTED width (which DSR can't see),
  merged-vs-split clusters, seams, and swatches. **This is the authority when
  it disagrees with `advance_probe.py`**: DSR is a cursor *report*, and on
  Terminal.app the report and the paint come apart for ZWJ sequences (DSR 5,
  8, 11; painted 2, rows do not shear). Treat a DSR advance that contradicts
  the claim as a hypothesis and confirm it here before compensating.
- `background_probe.py` — does the cell an under-advancing cluster's `CUF`
  skipped keep the background in force? Draws each compensation strategy as a
  RUN of clusters, so a one-cell hole reads as stripes on a screenshot, and
  DSR-measures the advance of each at the same time. `PROBE_WIDE=1` draws the
  rows double-width (DECDWL) for the capture.
- `row_probe.py` — the same clusters on a FULL-WIDTH row, which is what an app
  draws: does the row spend exactly what it claims, or overspend and wrap? The
  measurement is taken four cells short of the edge, because the cursor CLAMPS
  at the last column and reports the same number either way.
- `mouse_probe.py` — raw-mode SGR mouse byte capture (1000/1002/1006);
  every input sequence is appended human-readably. `q` quits.
- `cell_aspect_probe.py` — the terminal cell's height:width ratio (what
  `Image` needs to render undistorted), via `TIOCGWINSZ` pixel fields and
  the `CSI 14t`/`18t` escape queries. Prints to stdout.

`palette_probe.py` asks a different question from the rest: not how the cursor
moves, but what colour the terminal actually paints for a name we emit. The
sixteen ANSI colours are slots in the user's scheme, so `SGR 31` is "red" only
by convention — and TUIkit's contrast floor and 256-colour quantiser both
derive from a table of what those slots conventionally hold. Run it in each
host and record the answers in the compatibility document.

Extend the battery in `advance_probe.py` rather than hand-rolling one-off
probes, and record new results (with `TERM_PROGRAM_VERSION`) in the
compatibility document.

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
