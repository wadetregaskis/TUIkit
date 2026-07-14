# Terminal probes

Reproducible measurement tools behind `Documentation/Terminal-compatibility.md`.
Run each INSIDE the terminal under test; the recording probes (advance,
mouse) write to `$PROBE_OUT`, the visual/aspect probes print to the terminal.

- `advance_probe.py` — DSR (`ESC[6n`) cursor-advance measurement of a
  grapheme-cluster battery + terminal-relevant environment dump (JSON).
  `PROBE_ALT=1` measures on the ALTERNATE screen (the app's buffer) —
  iTerm2 advances some clusters differently there.
- `visual_card.py` — static `|<cluster>|X` alignment card with a column
  ruler, for screenshot inspection of PAINTED width (which DSR can't see),
  merged-vs-split clusters, seams, and swatches.
- `mouse_probe.py` — raw-mode SGR mouse byte capture (1000/1002/1006);
  every input sequence is appended human-readably. `q` quits.
- `cell_aspect_probe.py` — the terminal cell's height:width ratio (what
  `Image` needs to render undistorted), via `TIOCGWINSZ` pixel fields and
  the `CSI 14t`/`18t` escape queries. Prints to stdout.

Extend the battery in `advance_probe.py` rather than hand-rolling one-off
probes, and record new results (with `TERM_PROGRAM_VERSION`) in the
compatibility document.
