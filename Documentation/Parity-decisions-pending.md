# Parity work blocked on a decision

SwiftUI APIs that `Tools/APIParity` reports as gaps, where the gap is **not** a
matter of effort. Each needs a call that changes what existing TUIkit code does,
or picks between two defensible meanings. Implementing one of these without the
decision would be guessing on the owner's behalf, so they are parked here rather
than shipped.

Everything *not* on this list is ordinary work and is being done.

**Answered so far:** §9 (`Text.bold(_:)` and its siblings) — resolved by taking
its option (a): `TextStyle`'s five cascaded flags became tri-state, the merge
became nearest-wins, and the parameters followed. §6 (`labelsHidden()`) and §7
(`deleteDisabled`/`moveDisabled`) were both implemented after the last review —
`LabelsVisibility.swift` with `_CollapsingLabel`, `ColorPicker`, `Toggle`,
`ProgressView` and `DatePicker` all honouring it, and
`RowEditRestrictionModifiers.swift` with `RowEditRestrictionTests`. The
reasoning is in those commits; the entries are gone from here rather than
marked done, as this file's last section requires.

Last reviewed: 2026-08-24 — every remaining entry re-checked against the code
that day, and the counts below re-measured rather than carried forward.

**Each entry now ends in a recommendation.** They are recommendations, not
decisions: the point of this file is that the call is not mine to make. But an
option list with no opinion attached is a worse thing to be handed than one
with an opinion you can disagree with.

---

## 1. `Color.primary` / `Color.secondary` — a meaning collision

**The gap.** SwiftUI's `.primary` is the primary *label* colour (what text
defaults to). TUIkit's is `Color.blue`, and `.secondary` is `Color.brightBlack`
(Color.swift:96, :99). The names match and the meanings do not.

**Why it needs a decision.** Re-pointing them at `Color.palette.foreground` /
`foregroundSecondary` is the parity-correct move, and it **changes what already
rendered apps look like**. There are 17 in-tree call sites — `Sources/Example`
and the whole `Sources/Stress` module — that currently mean "blue" and "grey".

**The technical cost, if the answer is yes.** Making them semantic is not a
one-line edit. A semantic colour returns `nil` from `rgbComponents`, and
`opacity(_:)`, `lighter`, `darker`, `lerp` and *both* downsamplers all return the
colour unchanged for one — after which `ANSIRenderer` hits
`fatalError("Semantic color must be resolved before rendering")` on any path
that does not call `resolve(with:)`. `Text` and `BackgroundModifier` do resolve;
the audit is of everything that does not.

**Options.** (a) Re-point at the palette roles, accept the visual change, do the
audit. (b) Keep the current meanings and record `.primary`/`.secondary` in
`parity-map.json` as deliberate divergences. (c) Re-point and add
differently-named constants for the old meanings. (d) **Re-point `.primary` at
`Color.default` and leave `.secondary` alone** — see below.

**Re-measured 2026-08-24, and it splits the item in two.**

`.primary` is `Color.blue` and `.secondary` is `Color.brightBlack`
(`Color.swift:142`, `:145`). Used as colours in `Sources/Example` and
`Sources/Stress`: **2 sites for `.primary`, 13 for `.secondary`.**

Those two numbers are the argument for treating them separately:

- **`.primary` is plainly wrong.** SwiftUI's is "what text defaults to"; blue is
  a decoration. Two call sites care.
- **`.secondary` is approximately right already.** SwiftUI's is a
  lower-emphasis label colour, and in a terminal that is grey. `brightBlack` IS
  the grey. Re-pointing it at `palette.foregroundSecondary` would be more
  themable and is not more *correct*, and it is the option that moves 13 sites.

**Option (d), which the earlier list missed and which costs nothing.**
`Color.default` (`Color.swift:65`) is `.standard(.default)` — SGR 39, the
terminal's own foreground. It is CONCRETE, so it triggers none of the
semantic-colour machinery: no `nil` from `rgbComponents`, no inert `opacity`,
no `fatalError` in `ANSIRenderer`, no audit. And "the terminal's own
foreground" is exactly what "the colour text defaults to" means here, in the
same way SwiftUI's `.primary` means "whatever the system says a label is".

The trade against (a): `palette.foreground` follows the APP's theme, while
`.default` follows the USER's terminal. For a themed app the first is more
consistent; for a library default the second is more honest, and it is the one
an unthemed app already shows everywhere else.

**Recommendation: (d).** Re-point `.primary` at `Color.default`, leave
`.secondary` as it is, and record `.secondary` in the parity map as a
deliberate divergence with the reasoning above. That closes the wrong half,
touches two call sites, and pays nothing for the semantic audit — which can
then be done on its own merits, for the palette roles, rather than as the price
of a rename.

---

## 2. `Color.accentColor` — a second spelling for a thing that exists

**The gap.** SwiftUI has `.accentColor`; TUIkit already has `Color.accent`
(Color.swift:102), with 8 in-tree uses.

**Why it needs a decision.** Adding `.accentColor` alongside `.accent` ships two
spellings of one idea. That is exactly what the "consolidate before adding" rule
exists to prevent — but the alternative is that ported SwiftUI code does not
compile.

**Options.** (a) Add `.accentColor` as an alias of `.accent`. (b) Rename `.accent`
to `.accentColor` and update the sites (pre-1.0, no shim, per the standing
policy). (c) Record `.accentColor` as a deliberate rename in the parity map.

**Re-measured 2026-08-24: ~10 colour call sites**, and one fact that sharpens
the question. There are ALREADY two accent spellings, and they mean different
things: `Color.accent` is `Color.cyan` — a fixed colour — while
`Color.palette.accent` is `.semantic(.accent)`, the themed one. SwiftUI's
`.accentColor` is unambiguously the themed one.

So (a) would ship a THIRD spelling, and the one it aliases is the wrong one of
the two. That reading was not available when the options were first written and
it removes (a) from consideration.

**Recommendation: (b), pointed at the palette.** Rename the fixed `Color.accent`
to something that says it is fixed (`Color.cyan` already exists and is what it
is, so the constant may simply go), and let `.accentColor` be the alias of
`Color.palette.accent`. That leaves one accent spelling per meaning, and the
SwiftUI-shaped name lands on the SwiftUI-shaped meaning. It does pay the
semantic-colour audit of §1 option (a) — `.accentColor` would be semantic — so
it is worth doing in the same pass as whatever §1 decides.

---

## 3. Anything taking `opacity:` — blocked on where alpha lives

**The gap.** `Color.init(_:red:green:blue:opacity:)`,
`init(hue:saturation:brightness:opacity:)`, `init(_:white:opacity:)`.

**Why it needs a decision.** `Color.ColorValue` has no alpha channel, and
`Color.opacity(_:)` currently blends toward BLACK. Shipping a construction-time
`opacity:` now would either lie about the result or pre-commit the design that
**task #511 ("Opacity: resolve at composite time, not render time")** exists to
settle — and would reintroduce the opacity dim-blend bug class through a new
public door.

**Blocked on:** task #511. Not a question that can be answered independently.

**What would unblock it, stated so the dependency is checkable.** #511 decides
where alpha lives. Only two answers change this entry:

1. **Alpha becomes a field of `Color.ColorValue`** — then `opacity:` is a real
   parameter, these three initialisers are mechanical, and `Color.clear` (§4)
   falls out for free as alpha 0.
2. **Alpha stays a composite-time operation on BUFFERS, not on colours** — then
   a colour cannot carry one, `opacity:` can never be honoured, and all three
   initialisers plus §4 should be recorded in the parity map as
   `notImplemented` with that as the `why`.

**Recommendation: none, deliberately** — but note that §3 and §4 are one
decision wearing two hats, and answering #511 answers both. They should be
taken off this list together or not at all.

---

## 4. `Color.clear` — no alpha channel to be clear with

**The gap.** SwiftUI's fully-transparent colour.

**Why it needs a decision.** The tempting mapping is `Color.default` ("the
terminal's own colour"), and for a *background* the two coincide — nothing is
painted. For a *foreground* they do not: `.clear` text is invisible, `.default`
text is perfectly readable. One mapping cannot be right for both.

**Options.** (a) Map to `.default` and document the foreground caveat. (b) Record
as not-implementable pending #511. (c) Add a real alpha channel (see #3).

**Why (a) is worse than it looks.** The caveat is not a footnote: `.clear` on
text is the one thing a reader would reach for to HIDE text, and mapping it to
`.default` makes that line perfectly legible. A modifier that silently does the
opposite of what it says is worse than one that does not exist — and it cannot
be diagnosed at compile time, because both are just a `Color`.

There is a narrow shape that does work, and it is worth recording as it changes
what "not implementable" means here: a `.clear` FOREGROUND is expressible as
"emit no glyph" — draw a space. That is not a colour, it is a substitution, and
it would have to happen where the glyph is chosen rather than where the colour
is resolved. Whether that is worth a special case in `ANSIRenderer` for one
constant is itself a decision, but it means (b)'s `why` should say "no alpha
channel, and the foreground case would need a glyph substitution rather than a
colour" rather than the flat "not implementable".

**Recommendation: (b)** until #511 lands, with that fuller `why`. `--stale`
will bring it back if `ColorValue` ever grows a channel.

---

## 5. `View.help(_:)` — what a tooltip means with no pointer

**The gap.** `help(_:)` in its `LocalizedStringKey`, `Text` and `StringProtocol`
overloads.

**Why it needs a decision.** A terminal has no hover tooltip. The plausible
surface is the **status bar** — "the focused view's help text appears there" —
which is a genuine UX decision about what that bar is for, not a mechanical port.

**Also needs work either way.** `FocusRegistration` is not the universal seam it
looks like: `NavigationSplitView.swift:768` and `Button.swift` register with the
focus manager directly. Any help-on-focus mechanism routed only through
`FocusRegistration` would work for most focusables and silently not for those —
the failure mode already declined twice on this list.

**Found 2026-08-24: most of the mechanism already exists.** The status bar
already carries a string contributed by the focused control —
`StatusBarState.activationLabelOverride`, written by
`FocusRegistration.swift:190` and read by `StatusBar.swift:214`. "The focused
view's help text appears in the status bar" is therefore not a new surface; it
is a second writer of a slot that already has one.

That converts the open question from "what is the status bar for" into two
smaller and much more answerable ones:

1. **What happens when a control has both?** The existing override is a VERB —
   what Return will do ("choose", "open", "select"). A help string is a
   description. They are different things and both are useful, so either the
   bar grows a second slot, or help wins while focused and the verb returns
   when there is none, or help is shown only when the control offers no verb.
   The third is the cheapest and reads worst — the controls most worth
   documenting are the ones that do something.
2. **Does `help(_:)` on a NON-focusable view do anything at all?** SwiftUI
   attaches tooltips to anything. If the answer is "only focusables", then
   `help(_:)` on a `Text` compiles and silently does nothing, which is the
   failure mode this list keeps declining.

**Recommendation: (1) a second slot, and (2) yes-but-inert-is-not-acceptable.**
Concretely: implement `help(_:)` only if it is honoured for every focusable —
which means fixing the two direct registrants first, as its own commit — and
record it as `notImplemented` in the parity map until then, with the reason
being (2) rather than the status-bar question, which is now answered.

---

## 6. `View.focusEffectDisabled(_:)` — which parts of "focused" are an *effect*

**The gap.** SwiftUI's modifier suppresses the focus ring without taking the
view out of the focus ring.

**Why it needs a decision — measured, not guessed.** The obvious seam looked
universal: every control's emphasis resolves through
`SelectionEmphasisClock.cycle(_:)` / `SelectionIndicator.resolve(isFocused:…)`,
two functions. Gating both, then running a sweep that renders each control
focused-with-effects-off and compares it to the same control genuinely
unfocused (a live focus manager, focus parked on a sibling), **seven of eight
subjects still differed**:

| control | what still indicated focus |
|---|---|
| `Button` | the bold attribute (`ESC[1;…`) |
| `Toggle` | the glyph's colour |
| `TextField`, `SecureField` | the text cursor cell |
| `Stepper` | the ◀ ▶ arrow colours |
| `Slider` | the ◀ ▶ arrow colours |
| `DatePicker` | the active field's background |

The clock carries the *pulse*; each control separately branches on `isFocused`
for its base colours and attributes. So this is a change to every control's
focused-styling branch, not two gates — the same "not a universal seam" shape
already declined twice on this list, and the reason a partial version must not
ship: a control that kept indicating focus would read as a bug in that control.

**And one genuine question.** Is a focused `TextField`'s **cursor** a focus
*effect*? SwiftUI keeps the caret under `focusEffectDisabled` — the caret is
the insertion point, not decoration — so "suppress everything that differs when
focused" is the wrong rule for at least one control, and the right rule has to
be stated per control rather than derived.

**Options.** (a) Answer the caret question, then sweep every control. (b) Ship
a narrower TUI-specific modifier that suppresses only the *pulse* (the animated
part), under a name that does not promise SwiftUI's semantics. (c) Record as
not-implemented in `parity-map.json`.

**The rule that makes (a) tractable**, which the table above is really asking
for. "Suppress everything that differs when focused" is the wrong rule, and the
caret proves it. The right one is a distinction each control can be asked
about, one at a time:

> Does this cell tell you WHERE YOU ARE, or WHAT YOU CAN DO?

A `TextField`'s caret says what you can do — type here, at this position. It is
the insertion point and it must survive. A `Button`'s bold, a `Toggle`'s glyph
colour, a `Stepper`'s arrow colours all say where you are, and go. A
`DatePicker`'s active-field background is the interesting one: it says BOTH —
which field the arrows will change is an insertion point of a sort — and by
this rule it stays, which is also what SwiftUI does with a focused date field.

That leaves the table with one answer per row rather than a policy argument,
and it is a rule an implementer can apply to a control this list has not seen.

**Recommendation: (b) now, (a) later, and never a partial (a).** The pulse is
the part apps actually ask to turn off (a dashboard that should not breathe),
it is one gate at
`SelectionEmphasisClock.cycle(_:)`, and under a TUI-specific name it promises
only what it does. Shipping `focusEffectDisabled` itself with six of eight
controls converted would read as a bug in the other two — which is why the
sweep below is the gate on (a), not a nice-to-have.

**The sweep is worth keeping either way** — a byte-comparison against a
genuinely-unfocused baseline is what turned an assumption into the table above,
and it will catch producers a future implementer forgets. It is not currently a
committed test; it should be, whichever option is taken, because the table is
the only thing standing between (a) and a half-done sweep.

---


## Recording the answers

An answered item should end in one of two places, not in this file:

- **Implemented** — with the reasoning in the commit message, and
  `Tools/APIParity/api_parity.py --accept` re-run so the gap count moves.
- **Declined** — as an entry in `Tools/APIParity/parity-map.json` under
  `notImplemented` or `differentShape`, with the `why`. `--stale` will then keep
  that entry honest if the code later changes underneath it.
