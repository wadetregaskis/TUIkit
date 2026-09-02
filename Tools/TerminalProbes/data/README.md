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
- **`<terminal>-<version>-hyperlinks.json`** — OSC 8 SAFETY records
  (`hyperlink_probe.py`): the DSR column after a known-width label wrapped
  in each spelling of the sequence, on both screen buffers, against the same
  label bare. These say whether emitting the sequence is safe, which is a
  different question from whether the host honours it — no query answers
  that second one, so the `honoured` field is filled in by a person or left
  saying so. Every file carries an `unknown_osc` row: a command number
  nothing implements, which is what makes a "swallowed" result a property of
  the host's OSC parser rather than of this one sequence.
- **`<terminal>-<version>-graphics.json`** — GRAPHICS-PROTOCOL records
  (`graphics_probe.py`): what the host advertises for Sixel, the iTerm2
  protocol and Kitty, plus the cursor deltas after being sent one of each. The
  deltas answer "is it safe to emit", which has a different answer per escape
  FAMILY on the same host; `rendered` is the human half and stays
  `unmeasured` until somebody looks at the card.
- **`tmux-3.7b-tonebases.json`** — the full Emoji_Modifier_Base sweep
  (`advance_probe.py --modifier-bases`): which of the 134 bases tmux merges
  with a following tone (70) and which it detaches (64). The source of
  `Character.tmuxMergedToneBases`, pinned row-for-row by
  `TmuxCompatibilityTests`.

## When a record is superseded — retire it, or keep it?

Both happen, and the reason is not "how old is it".

**An advance record for a superseded version stays.** `warpterminal-v0.2026.07.08.17.54-alternate.json`
is referenced by no test and describes a build nobody has installed, and it
stays anyway: it is the baseline the compatibility document's zero-drift claim
rests on. "The 2026-08-26 self-update reproduced every one of the 63 committed
rows exactly" is only checkable while both files are here. Delete it and that
sentence becomes something the reader has to take on trust, which is the
opposite of what this directory is for.

**A record the instrument got wrong goes.** The July *landing* record was
retired on 2026-08-28, when the probe was found to have been screenshotting
its own cursor inside the ink window (see the compatibility document's
"Measuring paint"). Its `ink` column contains values no terminal ever
produced, it cannot be re-measured — that build is gone — and a wrong number
with a provenance stamp is more dangerous than no number at all, because the
stamp is what makes it look trustworthy.

So the test is **is it wrong, or merely old**. Old is evidence. Wrong is a
trap, and the fact that it was written by a probe rather than by hand is
exactly why somebody would believe it.

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
