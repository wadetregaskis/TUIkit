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
`RowEditRestrictionModifiers.swift` with `RowEditRestrictionTests`. §1
(`Color.primary`/`.secondary`), §2 (`Color.accentColor`) and §8
(`focusEffectDisabled`) were answered on 2026-08-24. The colours were
implemented together: the whole "Semantic Colors" block now
means the palette roles it is named after, and the SwiftUI spelling replaced
`Color.accent`. `focusEffectDisabled` took the strict reading — every focus
indication goes, not only the animated part — with the caret and the
`DatePicker`'s field marker surviving as insertion points rather than
announcements, gated through one `RenderContext.indicatesFocus(_:)` so it
cannot be honoured by some controls and forgotten by others. The
reasoning is in those commits; the entries are gone from here rather than
marked done, as this file's last section requires.

Last reviewed: 2026-08-24 — every remaining entry re-checked against the code
that day, and the counts re-measured rather than carried forward. Three left,
and two of them (§1, §2) are now a live question rather than a blocked one:
task #511 has been answered and implemented, which changes what they are
waiting for.

**Each entry now ends in a recommendation.** They are recommendations, not
decisions: the point of this file is that the call is not mine to make. But an
option list with no opinion attached is a worse thing to be handed than one
with an opinion you can disagree with.

---

## 1. Anything taking `opacity:` — blocked on where alpha lives

**The gap.** `Color.init(_:red:green:blue:opacity:)`,
`init(hue:saturation:brightness:opacity:)`, `init(_:white:opacity:)`.

**Why it needed a decision.** `Color.ColorValue` has no alpha channel, and
`Color.opacity(_:)` blends toward BLACK. Shipping a construction-time
`opacity:` would either lie about the result or pre-commit the design that
**task #511 ("Opacity: resolve at composite time, not render time")** existed
to settle.

**#511 is answered, as of 2026-08-24, and the answer is the second of the two
that were on the table**: alpha lives on BUFFERS, as `OpacityRegion` — a
rectangle of cells carried up the tree and resolved at the composite, where
what is behind it is finally known. `View.opacity(_:)` ships on it. The whole
design and its measurements are in
[`Opacity as composition.md`](Opacity%20as%20composition.md).

**So this entry is no longer blocked; it is a smaller question with a new
shape.** A region says a whole CELL is translucent — both its colours and, past
the glyph threshold, its character. A colour carrying alpha is narrower than
that: `Color.red.opacity(0.5)` as a foreground makes the INK translucent and
says nothing about the cell's background, and `.clear` as a background means
"paint nothing" while `.clear` as a foreground means "draw no glyph". Two
things stand between the machinery that exists and that:

1. **The region would need per-channel alpha.** A foreground α and a background
   α rather than one number. The blend already treats the two channels
   separately, so this part is a field and a branch — genuinely small.
2. **There is no choke point that knows WHICH CELLS a colour painted.** A
   region is emitted by a view about its own buffer; a colour is resolved deep
   inside `ANSIRenderer.foregroundCodes(for:)`, which returns SGR parameters and
   has no buffer to mark. Every view that draws text would have to emit the
   region itself, or the renderer would have to emit a sentinel for a later pass
   to find. That is the actual cost, and it is not small.

**Options now.**

(a) **Do it** — per-channel alpha on the region, plus whatever mechanism gets a
    colour's alpha out to the buffer. Closes §1 and §2 properly.
(b) **Record `notImplemented`** in the parity map, with the `why` above: alpha
    is a property of a layer here, not of a colour, and a colour has no cells to
    name.
(c) **A narrow special case for `.clear` alone** — a `.clear` foreground is "emit
    a space", which is a glyph substitution at the point the glyph is chosen and
    needs no alpha anywhere. It closes §2 and leaves §1 open.

**Recommendation: (b) for now, and revisit if `.clear` is asked for.** The
initialisers are the least valuable half — `Color(red:green:blue:opacity:)` with
a real alpha is a colour you cannot see the point of until you put it over
something, which is what `.opacity(_:)` on the view already does better. (c) is
cheap and self-contained if `.clear` turns out to matter.

**Note that §1 and §2 are still one decision wearing two hats** and should be
taken off this list together.

---

## 2. `Color.clear` — no alpha channel to be clear with

**The gap.** SwiftUI's fully-transparent colour.

**Why it needs a decision.** The tempting mapping is `Color.default` ("the
terminal's own colour"), and for a *background* the two coincide — nothing is
painted. For a *foreground* they do not: `.clear` text is invisible, `.default`
text is perfectly readable. One mapping cannot be right for both.

**Options.** (a) Map to `.default` and document the foreground caveat. (b) Record
as not-implementable pending #511. (c) Add a real alpha channel (see §1).

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

**DECIDED 2026-08-24 — (a) is ruled out rather than merely outranked.**
Mapping `.clear` to something that is not clear is not an option at any price:
the one thing a reader reaches for `.clear` to do is hide something, and
`.default` renders it perfectly legibly.

**And the fact it depended on has arrived.** #511 chose buffer-level alpha (see
§1), so `.clear` does not fall out for free — a colour still has no alpha, and
still has no cells to name. What is left is the choice in §1: record it
`notImplemented`, or take §1's option (c), the narrow one — a `.clear`
foreground is "emit a space", a glyph substitution at the point the glyph is
chosen, which needs no alpha channel anywhere and is the only part of this
anyone is likely to reach for.

---

## 3. `View.help(_:)` — what a tooltip means with no pointer

**The gap.** `help(_:)` in its `LocalizedStringKey`, `Text` and `StringProtocol`
overloads.

**Why it needs a decision.** A terminal has no hover tooltip. The plausible
surface is the **status bar** — "the focused view's help text appears there" —
which is a genuine UX decision about what that bar is for, not a mechanical port.

**Also needs work either way.** `FocusRegistration` is not quite the universal
seam it looks like: the split divider registers with the focus manager directly
(`NavigationSplitView.swift:554` and `:569`). It is the only site left — this
entry named `Button` too, wrongly: `Button` has gone through the seam since
`e2474a54` (2026-02-13), at `Button.swift:354`. Any help-on-focus mechanism
routed only through `FocusRegistration` would work for every other focusable
and silently not for that one — the failure mode already declined twice on this
list, at one site instead of a class of them.

**Found 2026-08-24: most of the mechanism already exists.** The status bar
already carries a string contributed by the focused control —
`StatusBarState.activationLabelOverride`, written by
`FocusRegistration.swift:180` and read by `StatusBar.swift:216`. "The focused
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

## Recording the answers

An answered item should end in one of two places, not in this file:

- **Implemented** — with the reasoning in the commit message, and
  `Tools/APIParity/api_parity.py --accept` re-run so the gap count moves.
- **Declined** — as an entry in `Tools/APIParity/parity-map.json` under
  `notImplemented` or `differentShape`, with the `why`. `--stale` will then keep
  that entry honest if the code later changes underneath it.
