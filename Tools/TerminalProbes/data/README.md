# Measurement records

One file per (terminal, version, screen buffer), written by a probe and never
by hand. `<terminal>-<version>-<screen>.json`.

These are the evidence behind the tables in
`Documentation/Terminal-compatibility.md`. The doc explains what the numbers
*mean*; these say who measured what, when, and under which conditions.

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

`advances` are **DSR cursor reports** — what the terminal *says* it did.

That is not always what it painted. On Apple Terminal a ZWJ sequence reports an
advance of 5, 8 or 11 while the glyph composes into two cells and the row does
not shear at all. An advance here that disagrees with TUIkit's width claim is a
hypothesis about rendering, and `visual_card.py` is what settles it — draw
`|<c>|<c>|<c>|X` and look at the column. Confirm before compensating; the
project has reached a wrong conclusion from advance alone in both directions.

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
