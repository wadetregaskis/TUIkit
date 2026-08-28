# TerminalClientQuirks

A combined diagnostic and demonstration of **terminal-client determination** and
the **workarounds** it selects.

```bash
swift run TerminalClientQuirks
```

Terminals disagree about how far the cursor moves over a grapheme cluster.
`Documentation/Terminal-compatibility.md` catalogues the disagreements and TUIkit
compensates for them automatically — but only for a terminal it can *name*, and
only in the ways that terminal has been *measured* to need. This app is the view
into both halves, and the tool for extending them.

## The screens

**Identity** — which terminal, and which signal named it. Over ssh this is
usually the whole story: `TERM_PROGRAM` does not survive the hop (OpenSSH
forwards `LANG` and `LC_*` only), so a terminal that is perfectly well known
locally arrives anonymous. The screen shows every signal, what each holds, and
how far each reaches, plus whatever the terminal answered when asked directly
(DA1, DA2, XTVERSION).

**Render as** — apply another terminal's workarounds, live, to the whole app.
Picking your own terminal should leave the Alignment screen straight; picking a
different one should visibly break it.

**Quirks** — the measured advance model for the terminal in force: for each class
of cluster, the width TUIkit lays it out as, the cells the terminal actually
moves, and the workaround applied where they differ.

**Alignment** — the check that takes none of the above on trust. Every row closes
its bar in the same column; a bar out of line is a cluster this terminal handles
in a way TUIkit does not yet know about. Your font and your terminal's settings
matter here (iTerm2's Unicode-version and ambiguous-width options change the
answer), which is why this is worth looking at even on a terminal that is
already supported.

## Adding a terminal TUIkit does not know

**Custom** builds a workaround set for an unmeasured terminal, one switch per
class of cluster, with the alignment strip rendered through whatever is
selected. Turn a switch on: if a row straightens, that terminal has that defect;
if a row breaks, it does not. The switches are:

| Switch | The defect |
|---|---|
| VS-16 pictographs | 🖥️ ❤️ ✏️ paint two cells, advance one |
| Bare pictographs | 🛡 🖥 — same, with no selector at all |
| VS-15 chrome glyphs | ⬛︎ ⬜︎ — TUIkit draws toggles with these |
| Lone regional indicators | 🇦 on its own (a flag pair is a separate switch) |
| Flag pairs | 🇺🇸 — correct on every terminal measured so far |
| Keycap sequences | 1️⃣ |
| SF Symbols | Plane-16 Private Use Area |
| ZWJ sequences | 👨‍👩‍👧‍👦 — the internal column decomposes while the glyph composes; the walk decomposes in software (joiners dropped) |
| Tag flags | 🏴󠁧󠁢󠁳󠁣󠁴󠁿 — advances 2 + one per tag scalar; pulled back with `CUB` |
| Stores wide composites | flags/keycaps whose row STORE keeps a surplus column; repaired with `CUB(1)` `DCH(1)` `CUF(1)` |
| Skin tones | 🤙🏽 *over*-advances — five treatments to try: keep, strip all, strip only what tmux detaches, pull back (`CUB` — tone lost on repaint), or SEPARATE as base+ZWNJ+modifier, which is how Apple Terminal keeps the tone |
| Background erase | compensated glyphs sit on the terminal's default background |

Then fill in the terminal's name and version and write the report. It records
what the terminal is, what it answered when asked, and the switches that turned
out to be needed — as a `TerminalQuirks(...)` literal, which is valid Swift and
can go straight into a test as the expected model.

Numeric confirmation, for a report worth acting on:
`Tools/TerminalProbes/advance_probe.py` measures every one of these classes with
DSR, and `identity_probe.py` records what the terminal answers when asked who it
is.

## What this app is not

A way to turn workarounds on permanently. Every compensation works around a
measured *defect*, so applying one to a terminal that does not have it breaks
output that was correct — which is why TUIkit compensates nothing for a terminal
it cannot name, and why the overrides here reset when the app exits. To name a
terminal permanently, set `TUIKIT_TERM_PROGRAM` in your shell.
