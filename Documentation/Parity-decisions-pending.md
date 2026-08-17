# Parity work blocked on a decision

SwiftUI APIs that `Tools/APIParity` reports as gaps, where the gap is **not** a
matter of effort. Each needs a call that changes what existing TUIkit code does,
or picks between two defensible meanings. Implementing one of these without the
decision would be guessing on the owner's behalf, so they are parked here rather
than shipped.

Everything *not* on this list is ordinary work and is being done.

**Answered so far:** §9 (`Text.bold(_:)` and its siblings) — resolved by taking
its option (a): `TextStyle`'s five cascaded flags became tri-state, the merge
became nearest-wins, and the parameters followed. The reasoning is in those
commits; the entry is gone from here rather than marked done, as this file's
last section requires.

Last reviewed: 2026-08-17.

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

**Options.** (a) Re-point, accept the visual change, do the audit. (b) Keep the
current meanings and record `.primary`/`.secondary` in `parity-map.json` as
deliberate divergences. (c) Re-point and add differently-named constants for the
old meanings.

---

## 2. `Color.accentColor` — a second spelling for a thing that exists

**The gap.** SwiftUI has `.accentColor`; TUIkit already has `Color.accent`
(Color.swift:102), with 8 in-tree uses.

**Why it needs a decision.** Adding `.accentColor` alongside `.accent` ships two
spellings of one idea. That is exactly what the "consolidate before adding" rule
exists to prevent — but the alternative is that ported SwiftUI code does not
compile.

**Options.** (a) Add `.accentColor` as an alias of `.accent`. (b) Rename `.accent`
to `.accentColor` and update the 8 sites (pre-1.0, no shim, per the standing
policy). (c) Record `.accentColor` as a deliberate rename in the parity map.

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

---

## 4. `Color.clear` — no alpha channel to be clear with

**The gap.** SwiftUI's fully-transparent colour.

**Why it needs a decision.** The tempting mapping is `Color.default` ("the
terminal's own colour"), and for a *background* the two coincide — nothing is
painted. For a *foreground* they do not: `.clear` text is invisible, `.default`
text is perfectly readable. One mapping cannot be right for both.

**Options.** (a) Map to `.default` and document the foreground caveat. (b) Record
as not-implementable pending #511. (c) Add a real alpha channel (see #3).

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

---

## 6. `View.labelsHidden()` — what happens to the space

**The gap.** Hides a control's label while keeping the control.

**Why it needs a decision.** In a `Form`, labels occupy an aligned pillar. When
they are hidden, does the pillar collapse to zero (controls slide left, rows no
longer align with unhidden rows elsewhere) or stay reserved (alignment holds,
blank column)? Both are defensible and they look completely different.

**Effort, once decided: large.** There *is* a shared seam — `_CollapsingLabel`
(ControlLabel.swift:54), used by Picker, Slider and Stepper — which corrects an
earlier claim of mine that all eight controls were separate. But `Form` has three
independent measure surfaces (`_FormLayout.renderToBuffer`, `pillarWidth`,
`contentWidth`) that must agree, `groupedRowView` is a second `baseRowView` caller
that a naive fix misses, and `ColorPicker` — the most canonical use of this
modifier in SwiftUI — draws its title in a fixed 18-cell frame and is not on the
seam at all.

---

## 7. `deleteDisabled(_:)` / `moveDisabled(_:)` — where row vetoes live

**The gap.** Per-row veto of delete/move.

**Why it needs a decision.** SwiftUI applies these to individual *rows*. TUIkit's
delete/move actions live on the `ForEach` and dispatch by data offset. Honouring
a per-row veto means collecting vetoes during a lazy render and having them
available to the handler *before* a key arrives — which is a design decision
about where row-level state lives, not plumbing.

---

## 8. `View.focusEffectDisabled(_:)` — which parts of "focused" are an *effect*

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

**The sweep is worth keeping either way** — a byte-comparison against a
genuinely-unfocused baseline is what turned an assumption into the table above,
and it will catch producers a future implementer forgets.

---


## Recording the answers

An answered item should end in one of two places, not in this file:

- **Implemented** — with the reasoning in the commit message, and
  `Tools/APIParity/api_parity.py --accept` re-run so the gap count moves.
- **Declined** — as an entry in `Tools/APIParity/parity-map.json` under
  `notImplemented` or `differentShape`, with the `why`. `--stale` will then keep
  that entry honest if the code later changes underneath it.
