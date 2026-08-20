# Review batch, 2026-08-20

A running log of one review pass: what was asked, what was done, what was
decided along the way, and what is still open. Newest work at the bottom of each
section. Commit subjects are quoted so `git log --grep` finds them.

## Done

### The Animation page
*"missing the app header … oddly padded … doesn't resize well … not in a
ScrollView"*, plus the bar width, the button row, the controls, and the
rearrangement so the curve settings read as page-wide.

- **"A view removed from a stack now gets to leave"** — the framework half.
  `if` inside a stack was the one shape a removal transition could not play in,
  because a `nil` optional flattened to no children and left nothing standing
  where the view stood. A `nil` now keeps one slot, but only while something is
  actually leaving from it, claimed by address (enclosing identity + the wrapped
  view's type) so a `nil` in a tree that animates nothing costs one
  dictionary-empty check and shifts no spacing.
- **"The Animation page, laid out like the rest of the app"** — header,
  `ScrollView`, settings first and labelled as governing the page, duration /
  speed / bounce / four Bézier control points, a full-width bar, centred
  buttons, `ViewThatFits` at every row, and a "Keep the space" toggle for the
  transition demo.

### Disclosure
- **"Left and Right disclose, wherever the triangle is"** — `List(_:children:)`
  had answered these keys for ages; `DisclosureGroup` and a bare `OutlineGroup`
  had not, so the same tree behaved differently depending on what it was inside.
  Both build their header from a `Button`, so the keys travel down the
  environment (`ButtonKeyExtras`) and the button hands them to its focus
  handler — which is what makes them focus-gated for free.
- **"A closed section remembers what was inside it"** — collapsing a group and
  reopening it reset everything within, because a collapsed group does not build
  its content and unbuilt state is collected at the end of the pass. It now
  declares `retainSubtree` while collapsed. **This is a deliberate divergence
  from SwiftUI**, recorded in `SwiftUI-compatibility.md`.

### Hover and focus
- **"A focused control still answers the pointer"** — focus says where the
  keyboard will go, hover says where the mouse would; a control that is both now
  shows both. They collide only where answered in the same ink, which is two
  places (a `Slider`'s and a `Stepper`'s arrows, whose focused state is an
  animation a static hover would freeze); those keep the old rule.
- **"Hover moves two visible steps, not one"** — the walk stopped at the first
  step the 256-colour cube could distinguish, which is not a difference a person
  notices. Two now, guarded so the extra step can never make a hovered label
  harder to read than the minimum-visible one was.
- **"The tint demo now tints something visibly"** — it hardcoded
  `.palette.success`, which under the default Green theme *is* the accent.

### Menus
- **"A scrolled menu lights the row the pointer is now on"** — the reported
  wrong-answer bug: the wheel moved the rows under a stationary pointer and the
  highlight stayed behind, so releasing chose what was under the cursor rather
  than what was lit.

### Layout
- **"Three alignment demos that show what a guide is for"** — the localised
  decimal column (two locales side by side), an acrostic, and a vertical guide
  that keeps three reflowing paragraphs' keywords level.

### In passing
- **"The main menu was showing a localization key as a headline"** —
  `feature.sfSymbols.title` rendered verbatim on the first screen of the app,
  because one non-literal argument took the whole call to the disfavoured
  `(String, String)` overload.

## Decisions I made without asking

- **Removal transitions in stacks**: the fix claims a slot by (parent identity,
  wrapped type). A `nil` whose content would have flattened into SEVERAL
  children has no single address and still jumps. Documented rather than
  guessed at.
- **Collapsed-disclosure state retention** diverges from SwiftUI. It seemed
  clearly the friendlier behaviour and it is what you asked for; say the word if
  you would rather match SwiftUI exactly.
- **Hover/focus coexistence is a sweep**, not a Buttons-and-Links change: a rule
  that holds for some controls and not others is worse than either rule.
- **The acrostic is not localized.** Its point is that a column spells a word.

## Open questions

Nothing blocking. Listed for when you get to them.

- **Q1 — `handleMenuShortcut` in `ContentView` is dead code.** It maps
  characters to pages, omits `f` and `a` (Forms and Animation), and never fires:
  the menu rows carry their own `.keyboardShortcut`, which is what actually
  works. Delete it?
- **Q2 — `row(_:_:)` in `MenuPressTrackingTests` is off by one for a popup tall
  enough to be clamped to the screen.** It returns `overlay.offsetY + line`,
  which is the drawn row, but the popup's hit regions for a clamped popup sit
  one row lower. Existing tests do not notice because their menus are short. Not
  chased; noted because the next person to write a menu mouse test will hit it.
