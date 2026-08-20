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

## Investigated, diagnosed, NOT fixed — needs your call

### 256-colour gradient banding

You reported "out-of-place colours" in default gradients on a 256-colour
terminal (the screenshots did not come through, so this is from first
principles — say if what I found is not what you were looking at).

**It reproduces, and the cause is exact.** The Example's default track gradient
(`FF5050 → FFC850 → 50DC78`) over 40 cells quantises to:

    203×5  202×1  209×5  208×2  215×4  214×3  221×3  185×4  149×4  113×4  77×4  41×1

202, 208 and 214 are the cube's **blue = 0** corner; their neighbours 203, 209,
215 are the same colours at **blue = 95**. The interpolated colour at those
cells has blue = 80. So a 15-point error is being passed over for an 80-point
one — a visibly more saturated cell wedged into a smooth ramp, which is exactly
"out of place".

**Why.** `nearestPalette256Index` compares in OKLab with the components split:
`ΔL² + w·ΔC² + 4·ΔH²`. ΔH² = Δa² + Δb² − ΔC² is the *tangential* part, so it is
blind to movement along the chroma axis — a candidate far more saturated in the
same hue has Δa² + Δb² ≈ ΔC², which cancels. The ×4 hue weight, whose job is
keeping a colour in its family, therefore does the least work exactly where the
family is most at risk, and nothing else prices the chroma. Chroma LOSS is
already charged ×4 for the mirror-image reason (recorded in that function's
comment, from an earlier washed-out-speckle report). Chroma GAIN is charged ×1.

**Three fixes tried, all measured, none shipped.**

1. **Charge chroma gain ×8 as well** (symmetric, hue left at ×4). The gradients
   come out perfect — `203×6 209×6 215×7 221×4 185×4 149×5 113×5 77×3`, eight
   monotonic runs, no speckles, and the "cool" ramp cleans up too. **But** it
   breaks four palette-derivation tests: the surface walk that separates a
   field or a plane from its page reads the *quantised* result to decide when
   it has moved far enough, so changing the metric changes where that walk
   stops. Novel's field ends up 8.99 apart from its page against a floor of 10.
2. **Weight hue ×8 too.** Same gradient result, and additionally reintroduces
   the washed-out speckle the ×4 chroma-loss weight was added to remove.
3. **A chroma CEILING instead of a weight** — no candidate may sit further from
   the target's chroma than the closest one does, plus a leeway. Principled (it
   forbids only the leap, leaving every close-call exactly as it was) but the
   leeway has no good value: 0.03 OKLab is too wide to remove the speckles and
   already too narrow for the surface walk.

**What I think the answer is, and why I did not just do it.** The banding is a
property of a *sequence*, not of a colour, and the quantiser only ever sees one
colour at a time. A gradient knows its whole ramp and could quantise it as a
ramp — enforcing monotonicity, which a per-cell nearest-neighbour search cannot
promise. That means the renderer pre-quantising when the terminal is
256-colour, which means the renderer knowing the terminal's colour depth, which
it currently does not. It is a real piece of work rather than a tuning change,
and it is worth doing properly rather than at the end of a batch.

*Meanwhile:* the metric is untouched, so nothing regressed. The measurement
above is repeatable — the probe is four `TrackRenderer.gradientColor` sweeps
printing run-length-encoded palette indices.

## Deferred, deliberately

**The page-instruction concision sweep.** You asked for the instruction lines at
the foot of each page to be accurate, complete and concise. Accuracy and
completeness are done where they were wrong: the Containers page had no
keyboard help at all and is the page whose keys are least obvious (Left and
Right disclose there now), and the Animation page's loose line of prose became
a `KeyboardHelpSection` like everywhere else.

Concision is a separate, mechanical job I have left whole rather than half
done. About a dozen lines still use the verbose "Use [X] to Y" form while the
rest use the terse "[X] Y" one, and rewriting them means 7 translations each.
The keys: `page.buttons.help.{enterSpace,tab}`,
`page.list.help.{navigate,select,switch,jump,fastScroll}`,
`page.table.help.{navigate,select,switch,jump,fastScroll}`,
`page.picker.help.{openMenu,moveChoose,moveFocus,dateFields}`,
`page.radioButton.help.{navHorizontal,navVertical,select}`,
`page.secureField.help.typeInsert`. The rest of the "not bracket-prefixed"
lines are prose on purpose (`page.theme.help.everyChange`,
`page.list.help.wheel`, `page.contentUnavailable.help.placeholder`) and should
stay that way.

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
