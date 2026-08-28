# Measurement records

Written by a probe and never by hand. These are the evidence behind the
tables in `Documentation/Terminal-compatibility.md`. The doc explains what
the numbers *mean*; these say who measured what, when, and under which
conditions. Four kinds of file live here:

- **`width-corpus.json`** — the shared cluster corpus: every cluster the
  probes measure and the Swift tests ask about, one id per row, duplicated
  scalar-for-scalar in `TerminalWidthCorpus.swift` (a parity test pins the
  two). A measurement always answers a question something asks.
- **`<terminal>-<version>-<screen>.json`** — ADVANCE records
  (`advance_probe.py`): DSR cursor reports for the curated battery.
- **`<terminal>-<version>-<screen>-landing.json`** — LANDING records
  (`landing_probe.py` + `landing_analyze.py`): per corpus row, all four
  facts — advance (DSR), landing and ink (pixels), reserve (the wrap test).
  These are what `TerminalLedgerConformanceTests` checks every model
  against, and the known-divergence ledger lives beside that suite. A
  corpus row no landing record has yet measured must be listed in the
  suite's `awaitingLandingMeasurement` set, so its absence cannot read as
  a pass.
- **`tmux-3.7b-tonebases.json`** — the full Emoji_Modifier_Base sweep
  (`advance_probe.py --modifier-bases`): which of the 134 bases tmux merges
  with a following tone (70) and which it detaches (64). The source of
  `Character.tmuxMergedToneBases`, pinned row-for-row by
  `TmuxCompatibilityTests`.

## Why the conditions are in the file

Twice now a measurement in this project has been recorded without the
precondition that made it valid, and both times the conclusion drawn from it
was wrong for a year:

- **Screen buffer.** iTerm2 and Warp advance some clusters differently on the
  primary and alternate screens. An early iTerm2 model was built from
  primary-screen readings and declared the host free of a quirk it has; the
  demo's closing brackets promptly painted into the glyphs.
- **DEC mode 2027.** Every Ghostty number was taken with grapheme clustering
  on — its default, so never wrong, but never checked. Resetting the mode moves
  six of eleven measured classes, and it persists across processes, so a probe
  can land in the other regime without anyone noticing.

So `stamp.screen` and `stamp.mode_2027_grapheme_clustering` are recorded on
every run, along with the date, OS, terminal version and the environment that
named the host. A record missing them is not a weaker record; it is an
uninterpretable one.

## What these numbers are, and are not

`advances` are **DSR cursor reports** — what the terminal *says* it did, and
that is ONE of a row's four facts. On Apple Terminal a ZWJ sequence reports
an advance of 5, 8 or 11 while the glyph composes into two cells — and an
earlier version of this note concluded from the paint that "the row does not
shear at all", which is FALSE: the advance governs wrapping, and a full-width
row budgeted at the painted 2 wraps (measured 2026-08-26). The paint governs
followers, the store governs later absolute writes, the reserve governs the
edge. An advance here that disagrees with TUIkit's width claim is a
hypothesis about rendering; confirm it with the wrap test plus
`landing_probe.py`/`treatment_card.py` — `visual_card.py` answers paint
only — before compensating. The project has reached a wrong conclusion from
a single fact in both directions.

## Adding a terminal

Run the probe, do not write the file:

```sh
cd Tools/TerminalProbes
PROBE_ALT=1 PROBE_OUT=data/<terminal>-<version>-alternate.json python3 advance_probe.py
```

`PROBE_ALT=1` measures the alternate screen, which is where TUIkit apps run and
what every model here is built from. A primary-screen record is welcome
alongside it — the difference between the two is itself a finding — but it is
not what the models use.

A new terminal's numbers are worth having even with no model written for it:
they are what a model would be built from, and until one exists the terminal
stays unidentified and its output is left alone, which is the correct
behaviour rather than a gap.

An advance record alone does not feed the conformance suite — that reads the
LANDING records. The full pipeline for a terminal that is getting a model:

```sh
cd Tools/TerminalProbes
PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap
python3 landing_analyze.py /tmp/landing.json \
    -o data/<terminal>-<version>-alternate-landing.json
```

then write the model from the record, and let
`TerminalLedgerConformanceTests` hold the two together.
