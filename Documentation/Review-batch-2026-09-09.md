# Review batch, 2026-09-09

Three deep dives — a bug hunt, a documentation audit and a performance pass —
each run as a twelve-lens fan-out whose every finding was then checked by a
second, adversarial pass. What follows is the whole verified backlog, so the part
that was not fixed on the day does not evaporate with the session that found it.

Numbers first: **35 defects confirmed** (2 more were raised and knocked down),
**64 documentation inaccuracies confirmed**, **23 optimisations judged worth
measuring** out of 42 proposed. Fixed here: 10 defects, 5 documentation commits
(including all 82 broken DocC links and the CI check that stops them coming
back), 2 measured optimisations and 1 measured revert.

Each open item below is a *verified* finding, not a suspicion: a lens proposed
it, a second agent tried to refute it and could not. They are not ranked against
each other beyond their severity.

## Closed — the second pass, later the same day

**Everything below was drained.** All 25 open defects are fixed, all the
documentation inaccuracies are corrected, and the 23 performance candidates were
re-derived, staged as patches, and each either measured or declined for a stated
reason. Eighty-seven commits.

The re-derivation was not a formality, and this is the part worth keeping. Every
item was handed to a fresh agent to prove from the code at HEAD, and then to a
second agent told to refute both the finding and the proposed fix. All 25 defects
survived — but **six of the fixes did not**, and two of those would have shipped
a new bug:

- The `ViewThatFits` fix (`199dd147`) was refuted with a counterexample: its
  detector missed a `Table` with a `.ratio(_:)` column, which reports a
  *fraction* of the probe. The landed version compares two probes one cell apart
  instead, which is sound for every greedy shape. Then running it falsified the
  review's claim that a bare `Slider` names a real minimum — it does not, because
  its body is an `HStack` — so the deviation is pinned by a test rather than a
  footnote.
- The stack-gap fix (`ad1b7b25`) would have introduced a new UNDER-report: a
  `Text("")` renders one line of pure escape bytes, so it took the contributing
  branch while the new measure counted it unoccupied. Which exposed the more
  interesting bug behind it — the drawn width of such a row was colour-depth
  dependent, 6 cells in colour and 4 with `--no-color`.
- The greyscale fix (`5631fde3`) was refuted for its *placement*: putting the
  ramp posterisation in the shared quantiser would have fed the glyph path a
  value it bands a second time, and the ramp entries are not fixed points of the
  bands, so a dithered highlight would have come out a step dark — silently,
  since nothing covers `.grayscale` with dithering.
- `@AppStorage` (`3b4d779f`) kept its mechanism but not its cost story: the claim
  that it pays "the same cost an `@Observable` mutation already pays" is false at
  HEAD, and this is the framework's first per-user-action full cache clear.
- `D12`'s fix was replaced by the two-line grounding idiom the codebase already
  uses, and `D20`/`D21`'s test plans were rewritten around tests that could not
  fail.

### Performance: measured, not assumed

Eighteen candidates were staged as applyable patches. Eleven measured as wins and
landed, three measured and were reverted, four were declined without measuring
and for the record why:

| Landed | Scenario | Change |
|---|---|---|
| `bff6f47e` | `tables-scroll` | −7.6% [−8.3, −6.7], `table-multiline` −6.5% |
| `0f2db8f2` | `table-multiline` | −8.7% [−10.0, −8.2] |
| `7db94fe9` | `fanout` / `modifiers` / `anyview` | −6.4% / −6.3% / −6.3% |
| `5e239298` | `deep` / `menus` | −5.1% / −5.3%, and 1.7 MB off `deep` |
| `9348de75` | image pixel path | −19.8% (sharpened), glyph −8.0% |
| `5d9e7006` | image pixel path | −16.5% ansi256, −23.5% truecolor |
| `21be6743` | `translucent` | −3.5% [−4.1, −3.1] |
| `3b935ee5` | `translucent` | −3.6% [−4.1, −2.3] |
| `fa71351d` | `menus` / `fanout` / `anyview` | −2.6% / −2.4% / −1.9% |
| `097a0c2d` | `gradients` | −1.4% [−2.3, −0.9], its pre-registered prediction |
| `288d33ce` | `modifiers` / `fanout` | −1.3% / −0.9% |

Reverted after measuring: **P06** (`RenderContext`'s depth as a packed
`UInt16`) — `anyview` **+3.0%**, `modifiers` **+1.6%**, both CIs clear of zero;
**P20** (static `childViews` requirements) — warm `deep` **+1.6%** against a cold
`fanout` −1.8%, so a steady-state regression to buy one first frame; **P04** (one
POD slot array per HStack row) — a wash with `menus` **+0.8% slower**.

Declined: **P02** and **P09**, whose hotness the adversarial pass refuted (both
below what the harness resolves — P02's own multiplier is rows-rebuilt-per-frame,
not per cell); **P16**, whose own pre-registered prediction is "the WASH of the
batch" behind a profiling gate; **P08**, superseded by `fa71351d`.

**P13 was re-derived and measured on 2026-09-10.** Both of its drifts were real:
the staged patch would have silently reverted `5631fde3`'s greyscale fix, and its
measurement plan named two `ImageHarness` modes that do not exist. Its first
commit landed — the glyph renderer's per-cell lock, **ansi256 −18.3%**
(`4f1d89ea`) — and its second measured as a wash and was reverted, as its own
pre-registered prediction had bet. §57 of
`Documentation/Performance-profile-2026-08.md` has both tables and the reason
they differ.

### What the drain itself turned up

Four things worth their own entries, all found while fixing something else:

- **`ItemListHandler+Resting.swift`'s resting-offset snap.** With text indicators
  drawn, a resting offset of 1 is pushed back to 0 on every render pass, and the
  `restingMidRow` escape that would let it stand is `.line`-only. Its premise —
  offset 0 shows strictly more content, because the row is whole and the
  indicator is gone — is false when the row at offset 0 is itself clipped. This is
  why `663d98cc` reaches the tail on the scrollbar arm and not the text one.
- **`DragAndDropSession` reads `hasContentBelow` through
  `any ScrollableOffsetState`,** so a mid-drag auto-scroller gets the extension's
  arithmetic — extent including the borrowed drop slot — rather than
  `ItemListHandler`'s override. That happens to be what a drag wants, but by
  luck: promoting any of `hasContentBelow` / `rowsBelow` / `visibleRange` to a
  protocol requirement would silently take it away. `ee2cc94a` writes the split
  down at both declarations.
- **`contentY(in:)`, `_ListCore.dragContentY` and `Table`'s equivalent are three
  copies of the same two questions** in two coordinate spaces. `c9ae127f` fixed
  the copy that had drifted; consolidating them needs `contentColumns` and
  `topInset` on a shared type.
- **`StderrSuppressionTests`' concurrency case is order-dependent.** It failed
  once under `swift test --filter 'Image'` — stderr left redirected — and passes
  alone and in the full suite. Nothing in the change being tested is even
  compiled on macOS, so it is a pre-existing race with whatever else suppresses
  stderr concurrently, and the suite's silence about it should not be trusted
  until it is reproduced under a seeded order.

The three reverts are the reason this section exists in this shape: the ratio
this batch actually produced is 11 wins to 3 reverts to 4 declines, and the
predictions were wrong in both directions — `bff6f47e` beat its own by a factor
of two, `P06` and `P20` were predicted as wins and measured as regressions.

## Fixed

- **Sources/TUIkit/Views/ScrollView+Content.swift:362** — `.scrollIndicators(.visible)` with the text style makes a ScrollView permanently overwrite its first and last content lines, so those lines are unreachable at every offset.
- **Sources/TUIkit/Views/Table.swift:942** — The single-line Table's "which indicator lines to draw" latch is published only when the table overflows, but read every frame, so a table that stops overflowing keeps drawing a stale "▼ 0 more rows below" line.
- **Sources/TUIkit/Views/Table.swift:612** — `analyticSingleLineSize` (and its multi-line twin) still measure a fitting table as "rows only", so a table under `.scrollIndicators(.visible)` + `.text` measures two lines shorter than it draws.
- **Sources/TUIkit/Focus/Focus.swift:592** — `resolvePendingDefaultFocus` walks an unordered Dictionary, so when two `.defaultFocus` declarations are live in one frame the winner is decided by Swift's per-process randomized hash seed.
- **Sources/TUIkitCore/Input/MouseEvent.swift:385** — `MouseEvent.parseLegacy` decodes xterm's extended buttons 8–11 as left/middle/right, the exact mistake `parseSGR` was fixed to decline.
- **Sources/TUIkitCore/Environment/PreferenceKey.swift:97** — `PreferenceValues.merge(_:)` overwrites a key instead of applying `PreferenceKey.reduce`, so `pop()` discards every contribution the parent scope had already accumulated for that key.
- **Sources/TUIkit/AppHeader/AppHeader.swift:82** — The app header drops its content's `animatedCells`, and the run loop only records runs from the content buffer, so any run-based animation placed in `.appHeader { … }` is frozen at frame 0 forever.
- **Sources/TUIkit/AppHeader/AppHeader.swift:93** — The same bare `FrameBuffer(lines:)` in the app header also discards the header content's `overlays`, so a `Menu`, `.popover`, `.sheet` or `.alert` declared inside `.appHeader { … }` opens but never draws.<br>Listed here too early: carrying the layer through the header's rebuild (`03d0a557`) was a prerequisite and not the fix. The header buffer is written straight to the terminal and never passed through `compositingOverlays`, so the layer reached the screen and was dropped there instead — the presentation still drew nothing. `RenderLoop` now moves a header-anchored layer onto the content buffer, in the content area's coordinates, before the page's own layers are composited; `AppHeaderOverlayCompositeTests` pins the route and the feature.
- **Sources/TUIkit/State/StorageFailure.swift:127** — `StorageDiagnostics.onFailure` is a `nonisolated(unsafe)` mutable closure property read from the background save queue with no synchronisation, while the API invites the app to assign it from the main actor at any time.
- **Sources/TUIkit/Views/TableColumn.swift:92** — TableColumn.lineLimit is an unclamped public stored var, so a value ≤ 0 set directly (bypassing the .lineLimit(_:) modifier) disables the line-limit fold entirely instead of behaving like 1

Plus: the adaptive-palette depth targeting and the Table bottom blank line that
opened the day, 82 broken DocC references with a `--strict` docs build behind
them, the front-door doc counts, and two measured performance changes (an Otsu
pass every non-mono picture paid for, −13.6% on the pixel path; and the row
shortcut table, −2.8% on `tables-vstack`).

## Defects — all fixed 2026-09-09

Severity as the verifier rated it after checking. Every one of these is closed;
the entries stay because the traces in them are the record of how each was
proved.

### `Sources/TUIkit/Focus/ItemListHandler.swift:331` — medium

`bottomWalk()` returns the shortfall measured against the budget of the *candidate* top row rather than the accepted one, so whenever the walk stops at `top == 1` the reported shortfall is one line too large.

**How it fails.** A `List`/`Table` with `.scrollIndicatorStyle(.text)` (default `.line` granularity, `alwaysShowsVerticalTextIndicators` off), multi-line rows, and content that only just overflows — so the bottom walk stops at `top == 1`. Example: contentHeight 10, three rows of heights 5, 6, 3. `bottomWalk()` returns `(top: 1, shortfall: 1, straddling: 5)`; the true shortfall at top 1 is 0, because rows 1 and 2 (6 + 3) exactly fill the 9-line budget left by the "▲ 1 more row above" line. Any route to the bottom (End, the clamp, a wheel tick, an anchor, a drag's auto-scroll) then has `fillBottomShortfall` rewrite the exact bottom to `scrollOffset = 0`, `scrollTopClipLines = 4` (correct would be 5, which is out of range — i.e. there is nothing to spend). `ScrollRowWindow.resolve` does not absorb a 4-line clip, so it reserves the above line, gives the rows 9 lines, and fills row 0 → 1 line, row 1 → 6, row 2 → clipped from 3 to 2. The last line of the LAST row is not drawn, and because the window reached `count` no "▼ N more below" is drawn either: the view claims to be at the bottom while hiding a line. The state is stable across frames (`scrollOffset >= walk.top` fails at offset 0) and a further down step lands on offset 1 / clip 0, which the same frame's settle pushes straight back — so that line is unreachable. The off-by-one is not limited to a true shortfall of 0: at every `top == 1` exit the clip is one line too small, so the destination overfills its budget by one and the bottom row loses a line. Six three-line rows in a 17-line content area — the shape of the bug report commit 44896b70 was fixing — gives clip 1 instead of 2 and clips the sixth row's last line.

**Sketch.** In `bottomWalk()` (Sources/TUIkit/Focus/ItemListHandler.swift:305-333), stop returning the last candidate's budget: keep the loop's `budget` as a `let` local to the loop again, and compute the ACCEPTED top's budget at the return, changing only `top - 1 == 0` to `top == 0`: ```swift let acceptedBudget = alwaysReservesIndicatorLines ? max(1, contentHeight - 2) : ((!reservesIndicatorLine || top == 0) ? contentHeight : contentHeight - 1) return (top, max(0, acceptedBudget - used), straddling) ``` Regression test: `BottomShortfallTests` needs a fixture with a SMALL row count (its current ones all use 300 rows, so `walk.top ≈ 295`). E.g. three rows of heights 5, 6, 3 in a 17→10-line area expecting `shortfall == 0` and no move, plus the report's own shape at six three-line rows in 17 expecting `scrollTopClipLines == 2`.

### `Sources/TUIkit/Focus/ScrollableOffsetState.swift:426` — medium

`ScrollableOffsetState.scroll(by:)` gates on `extent > viewportHeight`, but `ItemListHandler.viewportHeight` counts the partially-clipped straddling bottom row, so under `.scrollGranularity(.row)` a list whose window covers every row cannot be scrolled at all.

**How it fails.** A List or Table with `.scrollGranularity(.row)`, multi-line rows, and a content height that makes the last on-screen row straddle the viewport bottom exactly when `extent == viewportHeight` (e.g. 3 rows × 3 lines in an 8-line content area) cannot be wheel-scrolled at all, even though `resolvedMaxOffset`/`maxOffset` correctly reports one more valid offset (which would fully reveal the straddling row's clipped tail). The wheel tick is treated as unconsumed and, per `handleWheelEvent`'s documented chaining contract, bubbles to the enclosing scroller instead of moving the list — the last row's tail is unreachable by wheel.

**Sketch.** Change `ScrollableOffsetState.scroll(by:)`'s guard from `extent > viewportHeight` to `maxOffset > 0` (mirroring what `userScrollFine`'s own case-3 fallback already uses), so the "can we scroll" check goes through each conformer's precise bound instead of a raw extent/viewportHeight subtraction that can't account for a partially-visible straddling row.

### `Sources/TUIkit/Focus/ItemListHandler+Keys.swift:630` — medium

The reveal's scroll-down branch overrides the scroll-up branch it explicitly promises not to fight, so a focused row taller than `rowLineBudget` is always revealed at its TAIL — including row 0 on Home.

**How it fails.** Same as claimed: a List/Table with contentHeight such that rowLineBudget is smaller than the height of some row, reached either via Home or via Tab (any onFocusReceived) landing focus on that row while the viewport is scrolled elsewhere (or, more generally, any Up-arrow navigation that reveals a row whose own height exceeds rowLineBudget, not only row 0). The up branch correctly clears scrollTopClipLines to show the row from its head; the down branch then unconditionally re-clips it to show the row's tail flush to the bottom instead, because a single oversized row makes `covered` already exceed `budget` before the walk-up loop can run, and the guard on Keys.swift:630 treats that clip increase as an allowed 'scroll down' even at the same offset the up branch just set for a different reason.

**Sketch.** Skip the down-branch's clip override when the up branch already positioned scrollOffset == focusedIndex specifically to show the row's head — e.g. gate the `top == scrollOffset && clip > scrollTopClipLines` disjunct on the up branch not having just run this call, or special-case rowHeight(focusedIndex) > budget when top == focusedIndex == scrollOffset to prefer clip 0 (show the head) over clip = covered - budget (show the tail), at least for the single-row-exceeds-budget case.

### `Sources/TUIkit/Focus/Focus.swift:1020` — medium

Dismissing a modal restores focus to a remembered element without validating it, so the end-of-pass validation fires a second, unpaired `onFocusLost` on a control that was never told it received focus.

**How it fails.** Not the narrated deletion scenario (refuted: the page beneath a presented modal renders through an isolated throwaway FocusManager, so a vanished control is absent from both `sections` and `previousSections` at dismissal and the drop-the-dead block's notifyFocusLost() finds nothing to call). The real defect is the "present but unfocusable" variant the claim also mentions: a TextField holds focus; a modal/alert/popover opens (activateSection correctly pairs onEditingChanged(false) with the prior onEditingChanged(true) via previousSections) and remembers the field as `sectionFocusMemory["__default__"]`. While the modal is up, some OTHER state (independent of `isPresented`) sets `.disabled(true)` on the field. The modal is dismissed while that disabling condition is still true. `deactivateSection` (Focus.swift:1007-1025) sets `focusedID = sectionFocusMemory[target]` unconditionally (line 1020, no `canBeFocused` check — contrast `restoreFocusForActiveSection` at 1037-1044, which filters on it) and defers the arrival to `pendingRestoreNotificationID`. This same pass, the dismissed branch of `ModalPresentationModifier` renders the content through the REAL FocusManager (not isolated), so the disabled field DOES re-register — present, but `canBeFocused == false`. `endRenderPass`'s drop-the-dead block (~1155-1161) finds it present-but-unfocusable via the current pass's `sections`, and calls `notifyFocusLost()`, which (finding it in the current `sections`, not `previousSections`) fires `onFocusLost()` on it — `TextFieldHandler.onFocusLost()` is unguarded and calls `onEditingChanged?(false)` a second time with no intervening `onFocusReceived()`/`true`, since the arrival notification for this restore was skipped by the very same validation.

**Sketch.** In endRenderPass's drop-the-dead block (~1155-1161 in Focus.swift), before calling notifyFocusLost() for the dropped `focusID`, check whether it equals the still-pending `pendingRestoreNotificationID` (i.e. this focus session's arrival was never announced, because it's the exact same restore being invalidated). If so, clear `pendingRestoreNotificationID` and `self.focusedID` without calling notifyFocusLost() — a loss must not be announced for an arrival that was never announced. (Equivalently, validate the restore target's `canBeFocused` at the point it's read back in that block, in addition to whether it exists.)

### `Sources/TUIkit/Views/_UserResizableCore.swift:216` — medium

`_UserResizableCore`'s disabled/pinned early return skips `FocusRegistration.register`, and with it the `markActive` that keeps the view's persisted drag handler alive, so a disabled resizable loses the size the user dragged it to.

**How it fails.** Text(logText).userResizable(width: 20...80).disabled(isBusy): while enabled, user drags to width 65 (handler.requestedWidth = 65, persisted at (identity, -41)). isBusy flips true -> handler.canBeFocused becomes false -> the guard at _UserResizableCore.swift:216 returns before FocusRegistration.register, so context.identity is never marked active this frame (persistFocusID/storage(for:) don't mark it, and content — a Renderable leaf at the SAME identity — doesn't either). StateStorage.endRenderPass prunes the handler and focusID StateKey entries at that identity. On the very next render pass (still disabled, or after re-enabling — it makes no difference since the state is already gone), _UserResizeHandler is rebuilt fresh with requestedWidth == nil, and the offered width recomputes to widthBounds.maximum (80 here) instead of the dragged 65. The user's resize is permanently lost; toggling isBusy back to false does not restore it.

**Sketch.** Either (a) call FocusRegistration.register unconditionally (as Button's primary path does), passing handler.canBeFocused through so the focus ring still filters it out at move time — matching the codebase's own documented convention at Focus.swift:286 — or (b) if register() must stay skipped when canBeFocused is false, add an explicit context.stateStorage?.markActive(context.identity) call on that early-return path, mirroring Button.swift:377 / _MenuPopupCore.swift:65 / ContextMenuModifier.swift:74.

### `Sources/TUIkit/App/RenderLoop.swift:555` — medium

The status bar's hit regions are shifted by a content height computed from the PREVIOUS frame's app-header height, so on any frame where the header changes height every status-bar item becomes unclickable.

**How it fails.** Any frame on which the app header's height differs from the previous frame's publishes status-bar hit regions offset by the wrong amount, in either direction, and the bad set stays armed because the run loop renders nothing more on a static screen. Grow case (Example, 24 rows, 1-row status bar, header 3 → 4 because its content goes 1 → 2 lines): `renderContent` lays out at the estimate 3, gets `contentHeight = 20`, re-renders correctly at 19, and returns 20. The bar is drawn on terminal row 23; App.swift translates a click there to content y = 23 - 4 = 19, but the merged regions sit at y = 20. No region matches, dispatch returns false, no re-render is requested — so Back/Quit/any `.statusBarItem` stays dead to the mouse until an unrelated event forces a frame. Shrink case (Theme page, chrome style `.bordered` → `.compact`, header 3 → 1): estimate gives `contentHeight = 20` while the true one is 22, so the status-bar regions are merged at content y = 20 — a real content row, two rows above the bar. Because `matchingRegions` searches reversed and the status-bar regions were appended last, a click on that content row is routed to a status-bar handler instead of the control under the pointer: clicking near the bottom of the page can synthesise `q` and quit the app. Clicking the actual bar does nothing.

**Sketch.** Shift the status-bar regions by the ACTUAL content height, the same figure the drawing and the input translation use. Hoist the value already computed for overlays at RenderLoop.swift:497-499 out of its `if` and use it at :555: let contentAreaRows = contentAreaHeight( terminalHeight: terminalHeight, statusBarHeight: statusBarHeight, headerHeight: appHeader.height) if !buffer.overlays.isEmpty { buffer = compositeOverlays(buffer, maxWidth: terminalWidth, maxHeight: contentAreaRows, palette: environment.palette) } … shifted.offsetY += contentAreaRows Then `renderContent` no longer needs to return a content height at all (it is its only consumer), so drop the tuple and the now-wrong "pre-correction value" sentence from its doc comment. Add a test that renders a frame, changes the header's height, renders again, and dispatches a press at `terminalStatusBarRow - appHeader.height` — it fails on today's code in both directions.

### `Sources/TUIkit/Views/_ListCore.swift:1742` — medium

`_ListCore` hand-rolls the row hit-region clip and never records `topClip`, so a control inside a List row that is half-scrolled off the top receives clicks with local y short by the clipped line count.

**How it fails.** A List under .scrollGranularity(.line) with a row containing a multi-line interactive control (e.g. TextEditor, or a Box with .onMouseEvent spanning >1 line) at the TOP of the row (region.offsetY < the row's current origin.topClip). Once scrolled so that row's clip cuts into the control's own span, every click/drag routed to that control's handler is localized `clip-amount` lines too high (e.g. a click on the control's second visible line is reported to the handler as its own line 0), because the merged HitTestRegion built at _ListCore.swift:1741-1749 always has topClip=0 regardless of how much of the underlying region was clipped away.

**Sketch.** In the row hit-region merge loop (_ListCore.swift ~1732-1750), build the region the same way ScrollView does: shift the child region into the row's frame and clip it with the shared `HitTestRegion.clipped(toColumns:rows:)` (passing rows: clip..<(clip+position.height)) rather than hand-rolling a fresh HitTestRegion via the plain initializer -- or, minimally, add `topClip: region.topClip + (start - region.offsetY)` (and carry `leftClip`, `revealOutsetTop`/`revealOutsetBottom` forward from `region`) to the constructed HitTestRegion.

### `Sources/TUIkit/Input/DragAndDropSession.swift:550` — medium

Drop-target hover and reorder column hit-testing localise the cursor's X against `rect.offsetX` instead of `rect.localOriginX`, so both are wrong by the left clip inside a horizontally scrolled ScrollView.

**How it fails.** In `ScrollView(.horizontal) { List(...) { ForEach(rows) { ... }.onMove { ... } } }` scrolled right so the list's HitTestRegion carries `leftClip > 0`: (1) `contentY(in:)` in DragAndDropSession+Reorder.swift tests `host.contentColumns.contains(event.x - rect.offsetX)` — since `contentColumns` is local-space but the subtraction only removes the clipped offset, points that are genuinely inside the visible content columns get shifted by `leftClip` and can fail the `contains` check (reported as 'off the rows', cancelling the reorder) or, if they land in a different but still-valid sub-range, resolve to the wrong content column. (2) The `hovering` callback in DragAndDropSession.swift:550 similarly reports an X position offset from the true local content position by `leftClip`, so a landing-slot indicator or hover highlight a `dropDestination` draws from that X value is drawn `leftClip` columns away from the actual pointer position.

**Sketch.** Change `rect.offsetX` to `rect.localOriginX` at DragAndDropSession.swift:550 and at DragAndDropSession+Reorder.swift:325, matching the paired `localOriginY` usage on the adjacent lines and the pattern used throughout MouseEventDispatcher.swift. Add a horizontally-clipped-region regression test (mirroring ScrollViewClippedHitRegionTests / ScrolledClickLocalizationTests but with `ScrollView(.horizontal)`) covering both the reorder content-column hit test and a `dropDestination`'s `hovering` callback.

### `Sources/TUIkit/Views/Table.swift:2567` — medium

A Table's sort order can only be changed by clicking a column header — there is no keyboard route, violating the project's no-mouse-only-interactions rule.

**How it fails.** `Table(rows, selection: $sel, sortOrder: $order) { TableColumn("Name", value: \.name) }` run in a terminal with mouse reporting unavailable (no 1006 support, mouse reporting off, a multiplexer swallowing it, ssh to an old host). The sortable header draws its ▲/▼ affordance and reserves the glyph's width, but nothing can operate it: `toggleSort` has exactly one call site, inside the header region's mouse handler, and the Table registers no key handler, no `keyboardShortcut`, and `ItemListHandler+Keys` has no sort verb. The sort binding the app declared is inert for that user.

### `Sources/TUIkit/Views/ViewThatFits.swift:142` — medium

ViewThatFits probes candidates at 1,000,000 cells, so any candidate containing a Spacer or other width-flexible child reports 1,000,000 wide and is rejected at every real width — the fallback is always chosen.

**How it fails.** In a 200-column terminal, `ViewThatFits { HStack(spacing: 1) { Text("Name"); Spacer(); Text("Size") }; VStack { Text("Name"); Text("Size") } }` always renders the two-line VStack. chosenIndex measures candidate 0 with availableWidth = 1_000_000; the HStack distributes that budget, the Spacer absorbs 999,990 cells, and the candidate reports width 1_000_000 (isWidthFlexible = true). 1_000_000 <= 200 is false, so candidate 0 is skipped and the loop returns the last index. The same holds for any candidate containing `.frame(maxWidth: .infinity)`, a bare Slider or TextField, or — on the vertical axis, via availableHeight = 1_000_000 — a ScrollView, a List, or a column with a Spacer (whenever `.vertical` is in `axes`, which is the default). The preferred candidate can never win, at any terminal width, no matter how wide.

**Sketch.** Make a flexible axis report the minimum the ViewSize contract already promises, so the probe gets a real ideal. In `_HStackCore.clipSizeThatFits` (and the VStack twin), when `layout.fills` is true report the rigid ideal — the sum of the non-flexible children's ideals plus the flexible children's own minimums (`spacerMinLength ?? 0`, i.e. `nonFlexTotal + flexTotal + allSpacing` before distribution) — clamped to the available extent, instead of the post-distribution `totalWidth` which equals the whole budget. `isWidthFlexible` already tells parents it will fill, and the equivalence harness's flexible-axis invariant (rendered == E, reported <= E) still holds. Then ViewThatFits's existing `size.width <= context.availableWidth` test does the right thing: the Name/Spacer/Size row reports 10, fits at 200, and is chosen; a row whose rigid content genuinely exceeds the width is still rejected, matching SwiftUI. This touches shared stack sizing, so re-run MeasureRenderEquivalenceTests and the snapshot corpus. Narrower, lower-blast-radius alternative if that proves too invasive: keep the 1_000_000 probe in chosenIndex but, when the probe reports flexibility on a tested axis, ignore the probe extent for that axis (a flexible candidate fits) — this accepts a flexible candidate whose rigid content overflows, which SwiftUI would reject, so it is strictly a stopgap. Either way add a ViewThatFitsRenderTests case with `HStack { Text("Name"); Spacer(); Text("Size") }` as candidate 0 at a wide and a narrow width, and fix the now-false comment at Sources/Example/Pages/ProgressViewPage.swift:105-109.

### `Sources/TUIkit/Views/HStack.swift:215` — medium

The eager stacks charge inter-child spacing for children that render nothing, so `sizeThatFits` reports a size the render never produces (one `spacing` per non-rendering child).

**How it fails.** `HStack(spacing: 2) { Text("A"); EmptyView(); Text("B") }` renders `"A B"` — 4 cells, pinned by an existing test — but measures 6. Trace: EmptyView is Renderable-not-Layoutable so measureFixedByRendering reports (0, 0); resolvedLayout gets ideal [1, 0, 1] and `totalSpacing = max(0, 3 - 1) * 2 = 4`, so `totalWidth = 2 + 4 = 6`, while renderClip's `appendHorizontally` takes its contributes-nothing branch for the empty buffer and charges no gap. Put that row in `HStack(spacing: 0) { thatRow; Spacer(); Text("Z") }` at width 20: the spacer is sized from the 6-cell claim, so it gets 13 cells and `Z` lands at column 17 instead of flush right at 19. The identical arithmetic is in _VStackCore (`totalHeight += max(0, children.count - 1) * spacing`, VStack.swift:139) against a PASS 3 that relies on appendVertically dropping the empty child's spacing slot — and the over-counted height also feeds `contentHeight` and `gradientOffsets` in renderClip (VStack.swift:341-351), so every child after an EmptyView is sampled one row further down a `.gradientExtent(.subtree)` ramp than it draws.

**Sketch.** In `resolvedLayout` (HStack.swift), compute spacing gaps only between children that will actually occupy a column at render time — i.e. count children whose final rendered width is nonzero (mirroring the `!other.isEmpty || other.width > 0` predicate FrameBuffer.appendHorizontally already uses), and use `max(0, contributingCount - 1) * spacing` instead of `max(0, children.count - 1) * spacing`. This also requires threading that same "contributes nothing" predicate through `distributeLinearSpace`'s own `allSpacing` calculation, since it independently over-counts gaps around zero-ideal children. Apply the mirror fix to `_VStackCore`'s `totalHeight += max(0, children.count - 1) * spacing` (VStack.swift:139) using appendVertically's equivalent predicate.

### `Sources/TUIkit/Views/ViewThatFits.swift:118` — medium

_ViewThatFitsCore picks its candidate from `context.availableWidth` and ignores `proposal.width`, so a parent that measures it narrower than the context measures one candidate and renders another.

**How it fails.** A single ordinary `renderToBuffer`/`render` call on `HStack(spacing:1){ Text(wide); ViewThatFits{ wideRow; narrowVStack } }` at a width where the HStack must squeeze the ViewThatFits below its ideal width (e.g. width 30 with a 20-wide Text sibling and an 18-wide ViewThatFits row candidate) triggers the bug entirely internally to that one render call — no external caller needs to measure and render at two different widths on purpose. `_HStackCore.resolvedLayout`'s squeeze branch (HStack.swift ~189) re-measures the squeezed child via `child.measure(proposal: ProposedSize(width: widths[index], height: nil), context: context)` without first grounding `context.availableWidth` to `widths[index]` (unlike `ContainerViewCore.sizeThatFits` and `Layout.grounded`, which do exactly this grounding for the same reason). Because `_ViewThatFitsCore.chosenIndex` decides purely from `context.availableWidth`, this measure call sees the *unnarrowed* outer width and picks the wide row candidate, reporting a 1-row height that becomes the row's `rowHeight`. The subsequent actual render of that same child goes through `renderChild`, which *does* set `context.availableWidth` to the narrow width, so `chosenIndex` now correctly picks the narrow VStack candidate (3 rows) — which `renderChild` then clamps down to the stale 1-row `rowHeight`, silently dropping two of the three rows.

**Sketch.** Smallest fix: make `_ViewThatFitsCore.chosenIndex` (and `sizeThatFits`) ground the proposal into the width it uses for the fit check, the same way `Layout.grounded(_:in:)` and `ContainerViewCore.sizeThatFits` do: use `proposal.width ?? context.availableWidth` (and similarly `proposal.height ?? context.availableHeight`) instead of reading `context.availableWidth`/`availableHeight` unconditionally. This makes ViewThatFits's candidate choice agree with whatever width a caller's measure pass actually proposed, regardless of whether that caller (HStack, VStack, a custom Layout cell, etc.) also grounds its own context — closing the divergence at the one place all such containers funnel through, rather than requiring every squeeze/re-measure call site in the codebase to be audited and fixed individually.

### `Sources/TUIkit/Views/Layout.swift:188` — medium

`_LayoutCore` publishes no `containerAxis`, so a `Divider` inside `HStackLayout`/`VStackLayout` (the `AnyLayout` stacks) picks its orientation from whatever stack encloses the layout — and a mis-oriented Divider is width-flexible and eats the row's entire slack.

**How it fails.** `AnyLayout(HStackLayout()) { Text("a"); Divider(); Text("b") }` rendered at width 40, even standing alone (not nested in any other stack), draws Divider as a full-width `─` rule that consumes the row's entire slack — `a ────...──── b` instead of `a │ b` — because `_LayoutCore` never publishes `containerAxis` for any `Layout` value including `HStackLayout`/`VStackLayout`, so `Divider` falls back to its no-axis default (a horizontal rule, width-flexible). The mirror case, `AnyLayout(VStackLayout())` nested inside a real `HStack`, makes a Divider inside it inherit the outer HStack's `.horizontal` axis and draw a single-cell `│` instead of the full-width `─` separator it should be between rows.

**Sketch.** In `_LayoutCore` (Layout.swift), publish the correct containerAxis before resolving children when the wrapped `Layout` is axis-bearing — e.g. give `Layout` an internal axis hook (the currently-unused `LayoutProperties.stackOrientation` concept mentioned in Layout.swift's doc comment is exactly this shape) that `HStackLayout`/`VStackLayout` set, and have `_LayoutCore.resolve` call `context.publishingContainerAxis(...)` accordingly before `resolveChildViews`, mirroring what `Grid.renderToBuffer`/`sizeThatFits` already does with `.publishingContainerAxis(.vertical)`.

### `Sources/TUIkitImage/ASCIIConverter+Dithering.swift:147` — medium

`.grayscale` dithering carries its error unbounded in sRGB, so hue error the grey ramp cannot express pins a channel and lifts the greys after it — the exact bug `be7294e4` fixed for `.palette` only.

**How it fails.** `ASCIIConverter(colorMode: .grayscale, dithering: .floydSteinberg).convert(image, width: 8, height: 2)` on a uniform field of RGBA(200, 0, 0) (a saturated red, so mono spread is 0 and monoThreshold falls back to 128). Cell (0,0): grey(200,0,0) = luminance 59.8 -> 59; rErr = +141, gErr = bErr = -59. The right neighbour receives (141*7/16, -59*7/16, -59*7/16) = (+61, -25, -25), so it becomes (255, 0, 0) — red saturates at 255 and the two negative errors are silently discarded at 0. Its grey is now luminance 76.2 -> 76, and every remaining pixel repeats that fixed point. The row renders greys [59, 76, 76, 76, 76, 76, 76, 76] for eight identical source pixels; through `cellColor` the emitted picture is one cell of `38;5;237` (grey 58) followed by seven of `38;5;239` (grey 78). Undithered the same field is uniformly grey 58. Turning dithering on lightens 7/8 of a flat region by 17 of 255 levels — the same runaway the `.palette` OKLab carry was introduced to stop.

### `Sources/TUIkitImage/ASCIIConverter+Dithering.swift:424` — medium

`.grayscale` is a 24-entry palette to the glyph renderer and continuous 8-bit luminance to the pixel renderer, so one setting draws two different pictures depending on the terminal.

**How it fails.** Draw the same RGBAImage with .imageColorMode(.grayscale) via TUIkit's Image view. On a terminal without graphics-protocol support (e.g. Apple Terminal, Warp) the glyph path emits SGR 38;5;n through cellColor's 24-step ramp (n in 232...255, RGB roughly 8...238 -- never true black or white). On a terminal with kitty/Sixel graphics support (Ghostty, kitty) the pixel path (_ImageCore -> ASCIIConverter.recoloured -> PixelQuantiser.grey()) transmits raw 8-bit luminance per pixel with no posterisation at all -- full 0...255 range, continuous. Same setting, two different pictures depending solely on terminal capability, in direct contradiction of recoloured's documented contract that the pixel path get 'the same first half' as the glyph path except for three enumerated, unrelated differences. A secondary effect: Floyd-Steinberg dithering under .grayscale diffuses no error at all for already-neutral input pixels (grey(p) - p == 0), so it cannot smooth the 24-step banding that the glyph path's cellColor step introduces after the dither has already run.

**Sketch.** Make PixelQuantiser's .grayscale case (and thus recoloured, and the Floyd-Steinberg dither's quantisation target) posterise to the same 24-level ramp cellColor uses, instead of passing through continuous luminance -- e.g. quantise luminance to one of 24 discrete RGB grey levels matching ASCIIPalette.ansi256's grey-ramp entries (232...255) before returning from grey(_:), so both renderers draw the identical 24 shades and dithering diffuses the real posterisation error.

### `Sources/TUIkit/Views/ScrollView+Content.swift:314` — medium

A ScrollView clips carried opacity regions on the Y axis only, so a faded rectangle wider than the viewport fades the cells of whatever sits to the right of the scroller.

**How it fails.** A ScrollView that scrolls HORIZONTALLY carries an opacity region wider than its own viewport out into the page, and every cell to the right of the scroller that the region still covers gets faded. Two reachable shapes: (a) With a sibling. `HStack { ScrollView(.horizontal) { Text(<60-cell line>).opacity(0.4) }.frame(width: 20); Text("SIDEBAR") }`. The content renders 60 wide (contentExtents: `renderWidth = max(contentWidth, natural.width)`), `_OpacityView` stamps `OpacityRegion(offsetX: 0, width: 60, opacity: 0.4)`, `windowedBuffer` slices the lines to 20 but returns the region at width 60, and `clamped`'s fast path never trims it because the buffer's declared width is 20. `appendHorizontally` puts "SIDEBAR" at columns 20…26 and shifts the left child by nothing, so at the root `resolvingOpacity` finds those columns inside the region and blends them toward the surface at 0.4. "SIDEBAR" renders dimmed even though it is outside the scroller. Scrolling right does not help: `dx = -horizontalOffset` moves the region to `offsetX = -k, width = 60`, which still covers columns 20…26. (b) With no sibling at all — the case the introducing commit named. `ScrollView([.horizontal, .vertical]) { wideAndTallContent.opacity(0.6) }` over content overflowing both axes gives `wantsScrollbar == true`; `appendVerticalScrollbar` writes the bar at column `contentWidth`, which is inside the over-wide region, so the scroll view's own vertical scrollbar renders faded. Commit 79d7c9ef's message says explicitly that "a region wider than a row must not reach the scrollbar" — the code it shipped only clipped Y.

**Sketch.** Clip the X axis in the same block, in Sources/TUIkit/Views/ScrollView+Content.swift:305-315. The Y trim is done in content coordinates before the shift; X must be trimmed in viewport coordinates, so do it after the shift (translation and clip commute here — unlike HitTestRegion, OpacityRegion records no clip counters): ```swift let shifted = clipped.shifted(byX: dx, y: -scrollOffset) let left = max(0, shifted.offsetX) let right = min(shifted.offsetX + shifted.width, viewportWidth) guard right > left else { return nil } var trimmed = shifted trimmed.offsetX = left trimmed.width = right - left return trimmed ``` Better, and in line with the repo's consolidate-before-adding rule: give `OpacityRegion` a `clipped(toColumns:rows:)` mirroring `HitTestRegion`'s (minus the clip accumulators, which opacity has no use for), use it for BOTH axes here so the whole trim reads as one operation — `region.shifted(byX: dx, y: -scrollOffset).clipped(toColumns: 0..<viewportWidth, rows: 0..<viewportHeight)`, exactly the hit-region line twelve lines above — and then have `FrameBuffer.clamped` (:965-976) and `_ListCore.attachRowOpacity` (:1848-1856) call it too, so the third and fourth copies of this arithmetic stop being places it can drift again. Regression test: render `HStack { ScrollView(.horizontal) { Text(String(repeating: "x", count: 60)).opacity(0.4) }.frame(width: 20); Text("SIDEBAR") }`, assert every returned `opacityRegion` satisfies `offsetX + width <= 20`, and assert the resolved root line is byte-identical to the unfaded one from column 20 on. (Tests/TUIkitTests has no ScrollView-opacity coverage at all today.)

### `Sources/TUIkitCore/Rendering/OverlayLayer.swift:296` — medium

A pointer-anchored overlay cut back onto the screen drops rows/columns from its content without shifting the hit regions, animated runs, opacity regions or nested layers riding on it.

**How it fails.** A `.draggable` card containing a `ProgressView`/spinner (an `AnimatedCellRun`) or an `.opacity(0.5)` subview is grabbed at column 5 of the card and dragged until the pointer sits at screen column 2. `DragAndDropSession.previewOrigin` returns x = -3, App.swift emits `OverlayLayer(offsetX: -3, …, clampsToScreen: false)`, and `placed` sets x = 0, dropX = 3 and cuts three columns off every preview line — leaving the run at content column c and the opacity rectangle at column r, three cells right of the glyphs they now name. The root then fades the wrong three-column band of the preview, and every replay tick splices the spinner's next frame three cells right of where the spinner is drawn: it repaints over the neighbouring cells of the preview (and, at the preview's right edge, over the page beside it) while the visible spinner freezes at the frame it rendered with. The same happens vertically when the pointer rises above the grab row (dropY), putting the run one row below its glyphs. The second reachable route is a spring-overshooting `.transition(.move(edge: .trailing))` / `.transition(.offset(x:))` on a view sitting at page column 0 outside any ScrollView, where `slotBuffer()` floats the content (runs, opacity regions and nested overlays intact) at a negative offset and takes the same uncorrected cut.

**Sketch.** In `placed`'s `!clampsToScreen` branch, build the cut lines first and hand them to `replacingLines` with the shift, exactly as the sibling `clipped(toWidth:height:)` does at OverlayLayer.swift:404: var lines = dropY > 0 ? Array(clamped.lines.dropFirst(dropY)) : clamped.lines if dropX > 0 { lines = Self.cutting(lines, leadingColumns: dropX) } var visible = (dropX > 0 || dropY > 0) ? clamped.replacingLines(lines, overlayShiftX: -dropX, overlayShiftY: -dropY) : clamped visible = visible.clamped(toWidth: max(0, maxWidth - x), height: max(0, maxHeight - y)) The trailing `clamped(...)` then trims rectangles that are already in the cut content's coordinates, which is what it expects. Worth a test in the same block as `pointerAnchoredOverlayClipsLeftEdge` asserting that a run/opacity region on a layer at `offsetX: -3, offsetY: -1` comes back moved by (-3, -1).

### `Sources/TUIkit/Rendering/ViewRenderer.swift:135` — medium

`renderOnce` never composites overlay layers or resolves opacity regions, so `.opacity` is a silent no-op and `.offset`/`.position`/`.popover`/`.alert` draw nothing at all through the public one-off API.

**How it fails.** `renderOnce { HStack { Text("A").offset(x: 1); Text("B") } }` prints only "B" — the "A" glyph, carried in an `OverlayLayer` on the placeholder `FrameBuffer` that `OffsetView.renderToBuffer` returns, is silently dropped because `ViewRenderer.flush` only walks `buffer.lines`. Separately, `renderOnce { Text("faint").opacity(0.3) }` prints "faint" at full un-faded strength, because `_OpacityView.renderToBuffer` only records an `OpacityRegion` for a later compositor to blend, and `ViewRenderer`/`renderOnce` never runs one. The same applies to any modifier that relies on the overlay/opacity mechanism: `.position`, `.popover`, `.alert`, `.sheet`, etc. — all draw nothing (or draw un-faded) through the public one-off `renderOnce` API.

**Sketch.** In `ViewRenderer.render`, after computing `buffer` and before `flush`, resolve the same two steps `RenderLoop` runs at the screen root: `buffer.resolvingOpacity(surface: <background>, palette: <palette>)` then `.compositingOverlays(maxWidth: size.width, maxHeight: size.height, palette: <palette>)`, and flush the composited result. Needs a palette source for the snapshot context (the live path takes one from the environment/App); a reasonable default (e.g. environment's resolved palette, falling back to a standard terminal palette) would need to be threaded in the same way `context.environment` already is.</fixSketch> </invoke>

### `Sources/TUIkit/Rendering/OpacityResolution.swift:271` — medium

Two cycling opacity regions covering the same buffer row each emit a full-row animated run, and the second overwrites the first, so one of the two repeating fades freezes.

**How it fails.** Two sibling (or one inner + its enclosing outer-rectangle) views on the same output row each carry a repeating `.opacity` cycle. `cyclingRuns` builds one whole-row `AnimatedCellRun` (offsetX 0, width = full row) per cycling region, independently rebuilding the row while holding every other region — including the other cycling one — at its snapshotted static opacity. `replayAnimations` groups the resulting runs by row and applies `patchingAnimatedRun` for each in turn, and because each claims the full row width, the run applied last on a given tick completely overwrites the span the earlier run just wrote (via `FrameBuffer.patchingAnimatedCells`'s literal span replacement, not a cell-level merge). The region whose run is *not* last for that tick has its live cells reverted to the static opacity value baked into the winning run's rebuild, so that region's fade freezes (repeatedly, every tick) while the other keeps animating.

**Sketch.** In `OpacityResolution.cyclingRuns`, stop looping per-region. Instead, first collect, per row, the set of *all* cycling regions covering that row. For any row with more than one, build a single merged cycle: iterate a combined tick space (e.g. the LCM of each region's phase count, or simply the union clock's tick) and call `rebuild(row, line, substituting:)` once per combined phase with a closure that maps *every* cycling region on that row to its own phase for that tick (not just one region at a time, with the rest pinned) — producing one `AnimatedCellRun` per row instead of one per region. Only regions with no other cycling region sharing their row can keep the current single-region fast path. This keeps the "one row, one run" invariant `AnimatedBufferCycle.runs`/`patchingAnimatedRun` already assume, instead of violating it silently.

### `Sources/TUIkit/State/AppStorage.swift:474` — medium

`@AppStorage` / `@SceneStorage` writes request a re-render but never invalidate the render cache, so a value-memoized subtree that reads one keeps serving the buffer it drew under the old value.

**How it fails.** Any cached subtree (an automatically `_MemoizedRow`-wrapped `ForEach` row over `Equatable` elements, or any `.equatable()`-wrapped view) whose `body` reads an `@AppStorage`/`@SceneStorage` property directly serves its previously-rendered buffer forever after an external write to that key, because the property wrapper's setter (AppStorage.swift:472-476, SceneStorage.swift ~89-92) calls only `AppState.shared.setNeedsRender()`, which requests a new render pass but never sets `needsCacheClear` (State.swift) and so never reaches `RenderCache.clearAll()`/`clearAffected` (RenderLoop.swift ~417-419). The existing environment-value staleness fix (`EnvironmentModifier`/`TintModifier` calling `noteAppliedEnvironment`) only protects `@AppStorage` values threaded through an environment key/modifier — not a bare `@AppStorage` field read inline inside the cached view's own body. The row's element key is unchanged by the toggle, so the cache hit is legitimate by its own key contract, and the value is simply never in that contract.

**Sketch.** Make `AppStorage.wrappedValue`'s `nonmutating set` (and `SceneStorage`'s identical setter) call `AppState.shared.setNeedsRenderWithCacheClear()` instead of `setNeedsRender()` — the same variant `@Observable` property changes already use, matching the asymmetry the claim points at. This costs a full cache clear per AppStorage write, which is the same cost class already accepted for `@Observable` mutations and is fine given AppStorage writes are UI-action-driven, not per-frame.

### `Sources/TUIkitView/Core/ValueMemo.swift:171` — medium

`RenderContext.measureGeneration` is folded only into `MeasureKey`, so `invalidatingMeasureMemo()` does not reach the value memo's size half — a `_MemoizedRow` / `EquatableView` still answers the post-change ask with the pre-change size.

**How it fails.** Any container that (a) opts into `RenderContext.invalidatingMeasureMemo()` after changing an environment value a subtree's size depends on, and (b) re-measures a subtree wrapped in `_MemoizedRow` or `EquatableView` at the same identity, proposal (width/height), available extent (width/height), and explicit-width/height flags as before the bump, gets back the PRE-change `ViewSize` from `measureValueMemoized`'s `sizeEntries` cache. `RenderCache.SizeKey` (RenderCacheKeys.swift:21-60) carries no generation field and `lookupSize` (RenderCache.swift:526-533) checks only `SizeKey` equality plus the memoized element's own `==`, so it cannot see that the environment shifted — even though the *outer* wrapper's own `measureChild` call correctly missed its `MeasureKey` (which does fold `measureGeneration` in, ChildInfo.swift:606-613) and re-entered `sizeThatFits`. The inner, generation-blind `SizeKey` hit then short-circuits before the subtree is ever measured again, so the stale size persists in the cross-frame `sizeEntries` table (only cleared by `clearAffected`/`clearAll`, not per-pass) until the memoized element's value itself changes.

**Sketch.** Add a `measureGeneration: UInt8` field to `RenderCache.SizeKey` (RenderCacheKeys.swift), populate it from `context.measureGeneration` at the construction site in `measureValueMemoized` (ValueMemo.swift:171), and fold it into `SizeKey.hash(into:)` the same way `MeasureKey.identityHash` already folds it (ChildInfo.swift:606-613) — the compiler-synthesized `==` for `SizeKey` picks up the new stored property automatically, so a generation bump alone is then enough to miss.

### `Sources/TUIkitImage/ImageLoader.swift:178` — medium

PlatformImageLoader.loadImage(from path:) passes UTF-8 filenames straight into stb_image's default (non-UTF8) Windows `fopen`, so any path with non-ASCII characters fails to decode

**How it fails.** On Windows, PlatformImageLoader().loadImage(from:) (or the maxPixelCount overload) called with a path containing a character outside the process's ANSI codepage (e.g. a CJK character, or even a Latin-1 accented character if the codepage doesn't cover it) reaches decodeWithSTB(path:), which passes the UTF-8-encoded C string to stbi_load. stb_image's stbi__fopen calls the narrow fopen, whose UCRT implementation reinterprets those UTF-8 bytes under the ANSI codepage rather than UTF-8, so it looks for the wrong byte/character sequence on disk, fails to locate the real file, and stbi_load returns NULL — surfacing as ImageLoadError.decodingFailed('stb_image: Unable to open file') for a file FileManager.fileExists confirmed exists moments earlier.

**Sketch.** Define STBI_WINDOWS_UTF8 for the CSTBImage target on Windows (e.g. a cSettings .define("STBI_WINDOWS_UTF8", .when(platforms: [.windows])) in Package.swift), which switches stbi__fopen to the _wfopen_s/_wfopen path stb_image already provides; alternatively, on Windows, convert the path to UTF-16 and open the file with the wide Win32 API / FileHandle yourself and hand stb_image the already-open FILE* or memory buffer via stbi_load_from_memory instead of a path string. Either way, add a regression test (or at least a Windows-only PTY/manual check) that loads a real image through a non-ASCII path.

### `Sources/TUIkit/Focus/Focus.swift:435` — low

`FocusManager.clear()` drops the focused element without telling it, so a focused control's editing session is never closed at app teardown — the same gap that was fixed for `unregister`.

**How it fails.** A TextField (or any Focusable using onFocusLost to commit state) holds focus when the app quits (q, Ctrl-C, or any path reaching App.cleanup). cleanup() calls focusManager.clear() before StorageDefaults.backend.synchronize(); clear() nils focusedID without calling notifyFocusLost(), so the focused element's onFocusLost() — and therefore TextFieldHandler's onEditingChanged?(false) commit callback — never fires. Any state that a view intentionally defers to focus-loss (a draft value, a recents list, a synced setting) is silently dropped on quit even though synchronize() runs specifically to flush late writes.

**Sketch.** In FocusManager.clear() (Focus.swift:434), call notifyFocusLost() as the first statement, before sections.removeAll() and before focusedID = nil — mirroring the fix already applied to unregister() in commit 77c9bdd6. Add a test analogous to unregisterFiresFocusLost that asserts a focused MockFocusable's focusLostCount == 1 after manager.clear().

### `Sources/TUIkit/Views/_ImageCore.swift:625` — low

`_ImageCore`'s placeholder and error rows are neither wrapped nor truncated, so a buffer that declares `width` columns paints more than that and shears its HStack siblings on those rows.

**How it fails.** `centerContent` (called by both `renderPlaceholder` and `renderError` in _ImageCore.swift) builds a line wider than the requested `width` whenever the content (placeholder text, spinner+text, or "Error: …") is wider than the box, but still returns `FrameBuffer(lines:width:)` declaring the narrower `width` with `uniformWidth: false`. Because the declared width is by construction always exactly `context.availableWidth`, the framework's general `FrameBuffer.clamped` safety net (invoked after every `Renderable`'s render) takes its `self.width <= maxWidth` fast path and never truncates the oversized line — this is the one path in the framework where that safety net cannot fire. When this buffer is later combined via `appendHorizontally` (e.g. inside an `HStack`), the non-uniform per-row measurement correctly detects the real (over-wide) width of that one row and appends the next sibling immediately after it instead of at the nominal box edge, shearing that row relative to every other row of the same buffer, while the composed buffer's own reported `width` still understates the actual content extent — corrupting any enclosing border/sibling/scroll math that trusts it.

**Sketch.** In `centerContent`, clip each content line to `width` (visible columns) before computing `padding`/prepending spaces — e.g. via the existing `ansiAwarePrefixWithWidth(visibleCount:knownVisibleWidth:)` (already used by `FrameBuffer.clamped` itself) when `visibleWidth > width`. Once every emitted line is guaranteed ≤ `width`, also pass `uniformWidth: true` to `FrameBuffer(lines:width:uniformWidth:)` so downstream consumers (e.g. `appendHorizontally`) get the correct fast-path hint too.

### `Sources/Example/Pages/TogglePage.swift:106` — low

The Toggle page's checkbox comparison table never shows which glyph style is actually the terminal's automatic default

**How it fails.** Open the Toggle demo page (any terminal, e.g. Terminal.app or a plain terminal). In the "toggleCharacterSet" comparison section, none of the three columns (.unicode / .emoji / .ascii) ever shows the "(default)" suffix, regardless of which glyph style `.automatic` actually resolves to on that terminal — because checkboxColumn (TogglePage.swift:69-71) is only ever invoked with the three concrete ToggleCharacterSet values, never with `.automatic`, so the guard `style == .automatic` at line 106 compares a concrete value against a marker it can structurally never equal (per ToggleCharacterSet.swift's deliberate Equatable semantics) and is always false. This silently defeats the doc comment's and the page's own stated purpose of visually indicating the terminal's actual default glyph style.</correctedFailure> <parameter name="fixSketch">Compare against the resolved value instead of the literal marker: read `EnvironmentValues.supportsEmojiChrome` (already used by RenderLoop/TerminalHost to decide automatic's resolution) in TogglePage, compute `let resolvedAutomatic: ToggleCharacterSet = supportsEmojiChrome ? .emoji : .unicode` once per render, and change line 106 to `style == resolvedAutomatic ? ... : name`.

## Documentation — all fixed 2026-09-09

Every one is a statement that is no longer true, checked against the code by a
second pass. The DocC *link* rot is already fixed; these are the sentences.

### design-records-a

- **`/Users/robot/Documents/TUIkit/Documentation/Composing List and Table on ScrollView.md:29`** (high) — says: "The two handlers differ in exactly one place: their `extent`. ``ScrollViewHandler.extent`` returns `contentHeight` (lines); ``ItemListHandler.extent`` returns `itemCount` (rows). Every formula above is written in terms 
  <br>truth: `ItemListHandler` now overrides four of the seven formulas the doc lists as protocol-supplied, and its `extent` is not `itemCount`. Sources/TUIkit/Focus/ItemListHandler+Keys.swift:291 `var extent: Int { itemCount + (dropSlotAddsRow ? 1 : 0) }`; :371 `var hasContentBelow: Bool { drawnOffset + viewportHeight < itemCount 

- **`/Users/robot/Documents/TUIkit/Documentation/Composing List and Table on ScrollView.md:135`** (high) — says: "The right tool would be a separate `.focusable(false)` modifier that suppresses only the Focusable registration. The mouse handler stays active and wheel events still scroll the viewport." — and the body sketch at line 
  <br>truth: `.focusable(_:)` shipped (Sources/TUIkit/Modifiers/FocusableModifier.swift:35, and the `interactions:` overload at :45) with SwiftUI's meaning — it ADDS a focus stop around otherwise non-focusable content and publishes `\.isFocused` to it (:74-91). It does not suppress anything: `FocusableModifier` with `isFocusable: f

- **`/Users/robot/Documents/TUIkit/Documentation/Composing List and Table on ScrollView.md:239`** (medium) — says: "If you find yourself reaching for `LazyVStack` inside a `ScrollView` and discovering that the lazy doesn't actually defer rendering for off-screen children, that's the same trigger." — and, at line 117, of the windowed-
  <br>truth: It exists and it is what the trigger asked for. Sources/TUIkit/Views/ScrollView+Content.swift:118 publishes `ScrollContentWindow(offset:viewportHeight:contentIdentity:reply:edgeInset:reportsIDAt:seek:)` into the environment precisely so, per the comment at :103-113, "a direct `LazyVStack` renders only the rows intersec

- **`/Users/robot/Documents/TUIkit/Documentation/Image palette mapping.md:36`** (medium) — says: ```swift .imageColorMode(.palette(.sampled(8))) // eight, spread over the gamut ``` and the prose that follows it: line 60 "`.sampled(_:)` is a generated subsample", line 64 "**`.sampled(_:)` is deliberately not a palett
  <br>truth: The generator is `spread(_:)`, not `sampled(_:)` — Sources/TUIkitImage/ASCIIPalette.swift:245 `public static func spread(_ count: Int) -> Self`. There is no `sampled` member anywhere in Sources. The doc records the rename itself in a block quote at line 72 ("`.sampled(_:)` is `.spread(_:)` now") but the code block and 

- **`/Users/robot/Documents/TUIkit/Documentation/Animating your own view efficiently.md:80`** (medium) — says: Of `View.animatedCells(_:)`: "That modifier is **internal**. Making it public is a one-line change."
  <br>truth: It is public: Sources/TUIkit/Modifiers/AnimatedCellsModifier.swift:37 `public func animatedCells(_ runs: [AnimatedCellRun]) -> some View`. The same document says so at line 167 ("Shipped as `View.animatedCells(_:)`, `String.styled(foreground:…)` and the `AnimatingYourOwnView` article"), so §3.1's present tense contradi

- **`/Users/robot/Documents/TUIkit/Documentation/Drawers-sheets-and-slideovers.md:88`** (medium) — says: "So the work is: generalise `DialogDrag` into a 'grab this edge and give me a delta' helper" (line 88), the glyph table at lines 104-112 concluding "`▁▁▁▁` is the recommendation", and the mechanics row at line 225 "Grab 
  <br>truth: The grabber question was answered and shipped elsewhere on 2026-08-21 (commit 7aba17dd) as `.userResizable(_:)` — Sources/TUIkit/Modifiers/UserResizable.swift:145 — with its own core rather than a generalised `DialogDrag`: Sources/TUIkit/Views/_UserResizableCore.swift:118-136 defines `GripSize` (7 cells horizontal, 3 v

### design-records-b

- **`Documentation/Locating things without drawing them.md:6`** (high) — says: "**Status:** proposed. Nothing here is implemented except the prerequisite fix in §11." — reinforced by §1 ("Type this into TUIkit today … Six buttons work. The other 494 cannot be focused or Tabbed to", lines 18–31) and
  <br>truth: Stages 1, 3, 4 and 6 of this very design have shipped, and the acceptance tests name the document and the stage: Tests/TUIkitTests/WindowedFocusReachTests.swift:4-20 is "Stage 1 acceptance of 'Locating things without drawing them' (§1, §5d): every row of a windowed lazy stack is reachable by focus", with the suite lite

- **`Documentation/Parity-decisions-pending.md:153`** (high) — says: "`FocusRegistration` is not the universal seam it looks like: `NavigationSplitView.swift:768` and `Button.swift` register with the focus manager directly. Any help-on-focus mechanism routed only through `FocusRegistratio
  <br>truth: Button.swift does NOT register directly and has not since 2026-02 (`git log -S "focusManager.register" -- Sources/TUIkit/Views/Button.swift` ends at e2474a54, 2026-02-13). It goes through the seam: `FocusRegistration.register(context:handler:focusID:)` at Sources/TUIkit/Views/Button.swift:354, `FocusRegistration.isFocu

- **`Documentation/SwiftLint-rule-review.md:135`** (medium) — says: `direct_return` is listed under "Enable after a small, mechanical fix" with the verdict "two sites is thin justification for a standing rule. **Your call.**", and at line 182 `private_swiftui_state` is "Mechanical and sa
  <br>truth: Both were decided and enforced before this document's own last edit: commit b08531db (2026-08-25) "Enforce direct_return and private_swiftui_state" precedes de6f53e5 (the doc's final update, same day). They are in the config today — `.swiftlint.yml:50` (`- direct_return`) and `.swiftlint.yml:76` (`- private_swiftui_sta

- **`Documentation/Styling-and-theming-design.md:64`** (medium) — says: The `StyleAttributes` declaration in §3.1: "`public struct StyleAttributes: Sendable, Equatable {`" (line 56) with "`public var textCase: TextCase? // .uppercase / .lowercase / nil`" (line 64).
  <br>truth: Sources/TUIkit/Styling/StyleAttributes.swift:70 declares `public struct StyleAttributes: Sendable, Hashable`, and :89 declares `public var textCase: TextCase??` — a DOUBLE optional, deliberately, with the reason spelled out at :79-88: "`nil` is 'nothing was said', `.some(nil)` is 'cleared here'… collapsing them made `.

- **`Documentation/Out-of-band-styling-surface.md:243`** (medium) — says: "`Equatable` extends today's contract (`lines == overlays == hitTestRegions ==`) to `text == styleRuns == overlays == hitTestRegions`" — and the same two-payload inventory drives the one-paragraph summary (line 14, "`ove
  <br>truth: `FrameBuffer` now carries FOUR side payloads, not two: `overlays` (Sources/TUIkitCore/Rendering/FrameBuffer.swift:135), `hitTestRegions` (:145), `animatedCells: [AnimatedCellRun]` (:150) and `opacityRegions: [OpacityRegion]` (:164) — and `==` compares all five fields (:319-329), with a comment at :324-328 explaining th

- **`Documentation/Unifying the menu implementations.md:147`** (medium) — says: §"Chrome parity, once the assemblies agree": "What differs inside is the label's column (Picker starts at popup column 4, `Menu` at 3), the highlight extent (Picker spans the whole interior, `Menu` only the label width, 
  <br>truth: That is the pre-merge state, and the same file's "Also landed: the renderer merge (step 3)" section (lines 122-133) records that it is gone: a pop-up `Menu` gained "a **highlight spanning the whole interior**" and "a **flush divider** that pulses with the border". The code agrees: the pop-up path goes through `renderMe

### docc-references

- **`Sources/TUIkit/TUIkit.docc/Articles/AnimatingYourOwnView.md:193`** (high) — says: Splice ``AnimatedCellRun/frame(at:)`` back over the buffer at the run's own offset and compare the visible cells.
  <br>truth: AnimatedCellRun has no `frame(at:)`. It has `frame(atElapsed:)` and `frame(atIndex:)` (Sources/TUIkitCore/Rendering/AnimatedCellRun.swift:198,208) — the doc comment on `frame(atIndex:)` (lines 204-207) explicitly says a bare `frame(at:)` was rejected as ambiguous between the two. The article's own code sample two lines

- **`Sources/TUIkitCore/Rendering/FrameBuffer.swift:1122`** (medium) — says: a container paints its background across the whole finished row afterwards (``ANSIRenderer.applyPersistentBackground`` re-injects it after every reset)
  <br>truth: Two problems: (1) DocC member links use `/`, not `.` — `ANSIRenderer.applyPersistentBackground` cannot resolve as written. (2) `ANSIRenderer` lives in the `TUIkit` target (Sources/TUIkit/Rendering/ANSIRenderer.swift:136), which depends on `TUIkitCore` — not the reverse (Package.swift target graph) — so a doc comment in

- **`Sources/TUIkit/Extensions/View+Tag.swift:11`** (medium) — says: `_TaggedView` is produced by the ``View/tag(_:)`` modifier.
  <br>truth: `tag` has taken two parameters since commit 4052ab36 (2026-08-23, "tag(_:includeOptional:), and the promotion it names"): `public func tag<V: Hashable>(_ tag: V, includeOptional: Bool = true)` (Sources/TUIkit/Extensions/View+Tag.swift:72). `View/tag(_:)` no longer resolves. The same stale spelling recurs at View+Tag.sw

- **`Sources/TUIkit/Rendering/TrackRenderer.swift:161`** (medium) — says: a property of the SEQUENCE — see ``Color/quantisedRamp(stops:count:depth:)``, which is where the whole ramp is quantised at once and repaired into a monotone one.
  <br>truth: `Color.quantisedRamp` takes an unlabeled first parameter: `public static func quantisedRamp(_ gradient: Gradient, count: Int, depth: ColorDepth)` (Sources/TUIkitStyling/Color/Color+Downsampling.swift:111). There is no `stops:` label. The same wrong label appears at Color+Downsampling.swift:222.

- **`Sources/TUIkit/Focus/ItemListHandler+Resting.swift:255`** (low) — says: ``ScrollRowWindow/resolve(scrollOffset:count:contentHeight:topClip:drawsTextIndicators:height:)`` is the only caller, and it clamps the offset into the row range first.
  <br>truth: `ScrollRowWindow.resolve` at Sources/TUIkit/Views/ScrollRowWindow.swift:96 takes seven labels: `scrollOffset:count:contentHeight:topClip:drawsTextIndicators:alwaysDrawsIndicators:height:`. `alwaysDrawsIndicators` was added by commit f55a9f92 (today, 2026-09-08, "One flag, two meanings") and this cross-reference was not

- **`Sources/TUIkit/Rendering/TextFieldMouseHandler.swift:17`** (low) — says: moves the caret to the clicked column (mapping the column back through the field's horizontal scroll via ``TextFieldHandler/characterIndex(forColumn:contentWidth:)``)
  <br>truth: `characterIndex` takes three parameters: `func characterIndex(forColumn column: Int, contentWidth: Int, displayWidths: [Int]) -> Int` (Sources/TUIkit/Focus/TextFieldHandler.swift:223).

### docs-vs-code-core

- **`Sources/TUIkitView/Rendering/RenderCache.swift:45`** (high) — says: "Only ``EquatableView`` and `_MemoizedRow` consult the cache at all — `measureChild` / `renderChild` do not. A tree with neither is walked in full every frame, cache or no cache."
  <br>truth: `measureChild` consults the cache on every measured child: Sources/TUIkitView/Rendering/ChildInfo.swift:542-560 builds a `RenderCache.MeasureKey` and calls `cache.lookupMeasure(...)`, storing at :580-586. `resolveChildViews` also consults it (ChildInfo.swift:900-908, `cache.lookupChildViews` / `storeChildViews`). Rende

- **`Sources/TUIkitView/Rendering/Renderable.swift:30`** (high) — says: The "Who conforms to Renderable?" list: "- **Layout containers**: `VStack`, `HStack`, `ZStack`" (line 30), "- **Interactive views**: `Button`, `ButtonRow`, `Menu`, `StatusBar`" (line 32), "- **Containers**: `Panel`, `Con
  <br>truth: None of those eleven types is `Renderable` today; every one is a public `View` with a real `body: some View` that wraps a private `_*Core`. `VStack` — Sources/TUIkit/Views/VStack.swift:32 (`public struct VStack<Content: View>: View`), `body: some View` at :58, `body: Never` only on the private core at :78. Likewise `Bu

- **`Sources/TUIkitView/Rendering/RenderContext.swift:96`** (high) — says: On `isMeasuring`: "Set to true during two-pass layout when measuring non-Layoutable views. Views should skip side-effects like focus registration when this is true."
  <br>truth: It is set for `Layoutable` views too — in fact that is the primary path. Sources/TUIkitView/Rendering/ChildInfo.swift:709-714: when the parent is not already measuring, `measureResolved` copies the context, sets `measureContext.isMeasuring = true`, and calls `V._measureSelf(view, proposal:context:)` — the `Layoutable.s

- **`Sources/TUIkitView/Rendering/RenderCache.swift:127`** (medium) — says: "Every ``lookup(identity:view:contextWidth:contextHeight:gradientFrame:)`` pulls an entry out of the dictionary…" — the same link spelling recurs at :463 ("The size twin of …"), :510 ("The measure-side counterpart to …")
  <br>truth: Both functions gained a seventh parameter on 2026-09-06 (54977d08, "A memoized buffer holds ink already blended, and was served over a new surface"): `lookup` is declared `identity:view:contextWidth:contextHeight:gradientFrame:surfaceBackground:` (RenderCache.swift:378-385, `surfaceBackground: Color? = nil` at :384) an

- **`Sources/TUIkitView/Rendering/ChildInfo.swift:60`** (medium) — says: "…do not re-derive it without a clean-built A/B on both sides (§40.2 of the performance profile)."
  <br>truth: Documentation/Performance-profile-2026-08.md has §40 ("The row pipeline's paper cuts…", line 2908) and §40.1 ("The experiment that did not ship…", line 2984) and then jumps to §41 — there is no §40.2. The section this comment is pointing at is **§41.1, "The struct that would not shrink, and a benchmark that lied"** (li

- **`Sources/TUIkitCore/Rendering/FrameBuffer.swift:55`** (low) — says: On `width`: "Accessing `width` is O(1) — the expensive ANSI-stripping regex runs only once per mutation, not per access."
  <br>truth: There is no regex anywhere on the width path, and none anywhere in TUIkitCore or TUIkitView — this doc line is the last remaining mention of the word in either module. `width` is recomputed by `FrameBuffer.measure(_:)` (FrameBuffer.swift:1266-1276), which sums `String.strippedLength`; that is an ASCII byte-at-a-time CS

### docs-vs-code-focus-app

- **`Sources/TUIkit/App/SignalManager.swift:177`** (high) — says: "Installs signal sources for SIGWINCH, SIGINT, and SIGTERM." The type-level doc says the same at line 63: "SIGWINCH (terminal resize) and SIGINT / SIGTERM (graceful shutdown) are monitored with `DispatchSource.makeSignal
  <br>truth: `install(wake:)` registers five sources, not three, and also changes SIGPIPE's disposition process-wide: `signal(SIGPIPE, SIG_IGN)` at Sources/TUIkit/App/SignalManager.swift:202, then `register(SIGINT…)`, `register(SIGTERM…)`, `register(SIGWINCH…)`, `register(SIGTSTP, kind: .suspend…)` and `register(SIGCONT, kind: .res

- **`Sources/TUIkit/App/InputHandler.swift:9`** (high) — says: "Dispatches key events through a five-layer priority chain (layers 0–4). The dispatch order is: 0. Text input … 1. Status bar … 2. View handlers … 3. Focus system … 4. Default bindings — `q` (quit), `t` (theme), `a` (app
  <br>truth: `handle(_:)` has seven dispatch steps, and two of them are missing from the list — including one that beats the status bar. Sources/TUIkit/App/InputHandler.swift:122-124 runs "Layer 0.5: mid-drag navigators" (`dragAndDropSession?.handleDragNavigator(event)`) BEFORE the status bar, and lines 155-157 run "Layer 3.5: sema

- **`Sources/TUIkit/App/StdinArrivalStream.swift:50`** (medium) — says: "That means the source's event handler runs on the main thread — the same thread the MainActor's executor lives on, on both macOS (where the main actor's executor pumps the main queue via the Cocoa run-loop) and Linux (w
  <br>truth: That premise is false on Linux and the repo says so twice. The inline comment on the very handler this paragraph describes (Sources/TUIkit/App/StdinArrivalStream.swift:120-128) reads "Deliberately says nothing about *threads*: which OS thread drains the main actor is not fixed. On Linux it is a cooperative pool thread,

- **`Sources/TUIkit/App/CursorTimer.swift:64`** (medium) — says: "See ``RenderLoop/timeUntilNextChange(from:)``." — repeated as an inline reference at line 126 ("(`RenderLoop.timeUntilNextChange(from:)`)"), and at line 228 "Starting bright is what makes ``reset()`` mean \"show me now\
  <br>truth: Both symbols were renamed by commit 7c5514aa ("Pressing Tab restarted every animation in the app", 2026-09-01), which left these three references behind. The method is now `func timeUntilNextChange(elapsed: (AnimationClock) -> Double)` — Sources/TUIkit/App/RenderLoop+Replay.swift:77, and every real call site spells it 

- **`Sources/TUIkit/Focus/TextFieldHandler.swift:31`** (medium) — says: The "## Keyboard Controls" table (lines 31-54) presents itself as the handler's full key map: printable, Backspace, Delete, Left, Right, Home, End, Shift+Left/Right, Shift+Up/Down, Shift+Home/End, Ctrl+A, Ctrl+E, Option+
  <br>truth: Four bindings the handler implements are absent, and one row is wrong by omission. Word navigation: `Option+Left` / `Option+Right` and `Shift+Option+Left` / `Shift+Option+Right` (Sources/TUIkit/Focus/TextFieldHandler.swift:517-538) plus their readline twins `Alt+b` / `Alt+f` (lines 442-463). Erase-line: `Ctrl+U` delete

- **`Sources/TUIkit/App/MouseEventDispatcher.swift:11`** (medium) — says: "Routes terminal mouse events to the view tree using hit-test regions emitted by `.onMouseEvent` modifiers. The dispatcher resets its state at the start of every render pass … Drags are tracked too: the dispatcher rememb
  <br>truth: There is no `///`-free line between the dispatcher paragraph (lines 11-25) and the `MouseFeature` sentence (lines 26-27), so the whole block is one doc comment and it attaches to `public enum MouseFeature` at line 28 — the public symbol's documentation therefore opens by describing a routing class that is not it. `fina

### docs-vs-code-rendering

- **`Sources/TUIkitView/Rendering/RenderCache.swift:36`** (high) — says: "The whole cache is dropped only by: an `@Observable` mutation (which arrives with no identity, via `setNeedsRenderWithCacheClear`), a palette / appearance / locale / toggle-glyph change, or an explicit `nil` invalidatio
  <br>truth: An `@Observable` mutation has been SCOPED since commit 96c12acb (2026-09-05, "An observable change invalidates the view whose body read it, not the whole render cache"). Sources/TUIkitView/Rendering/Renderable.swift:239-244 captures `context.renderCache` and `context.identity` in the `withObservationTracking` onChange 

- **`Sources/TUIkitCore/Rendering/AnimatedCellRun.swift:11`** (high) — says: On ``AnimationClock``: "One, now. There were two — a breathing clock for focus indicators and a blink clock for text cursors — and having two was a bug rather than a feature … Both cadences now come from one clock and on
  <br>truth: There are two clocks again, deliberately, since commit 7c5514aa (2026-09-01, "Pressing Tab restarted every animation in the app"): the enum declares `case cursor` (AnimatedCellRun.swift:26) and `case content` (AnimatedCellRun.swift:34), and `.content`'s own doc two lines below contradicts the header — "Never restarted 

- **`Sources/TUIkit/Rendering/FrameDiffWriter.swift:67`** (high) — says: "Whether the host terminal is Ghostty, which advances every composed emoji class exactly as claimed (alone among the measured terminals) but under-advances the VS-15 chrome glyphs ⬛︎ / ⬜︎ and Plane-16 PUA SF Symbols. Its
  <br>truth: Both halves are out of date. (a) A composed emoji class does NOT advance as claimed: a Fitzpatrick tone on a text-presentation base (☝🏽 🏋🏽) merges to ONE cell against a 2-cell claim, and with a redundant VS-16 (☝️🏽) detaches to FOUR — Character+CursorAdvance.swift:543-559, and Documentation/Terminal-compatibility.md:11

- **`Sources/TUIkit/Rendering/FrameDiffWriter.swift:280`** (medium) — says: On `buildOutputLines(buffer:terminalWidth:terminalHeight:bgCode:reset:)`: "This is a **pure function** — no side effects."
  <br>truth: Its first statement is `invalidateIfProgramChanged()` (FrameDiffWriter.swift:289), which writes `appliedModel` and, when the model changed, calls `invalidate()` (line 739-755) — emptying `previousContentLines`, all three reuse caches, all three cell caches and `terminalStyle`. Introduced by 0745a47b (2026-08-26, "Which

- **`Sources/TUIkitView/Rendering/RenderCache.swift:374`** (medium) — says: `lookup`'s `- Parameters:` block documents identity, view, contextWidth, contextHeight and gradientFrame and stops; `store`'s (line 429-436) does the same. Three DocC links spell the method `` ``lookup(identity:view:cont
  <br>truth: Both methods gained a sixth parameter, `surfaceBackground: Color? = nil`, in commit 54977d08 (2026-09-06) — declarations at lines 378-385 and 437-445, and it is a load-bearing part of the key: the guard at line 405-409 misses when it differs, because a memoized buffer holds ink already blended against the surface it wa

- **`Sources/TUIkit/Rendering/FrameDiffWriter.swift:284`** (medium) — says: The pure builder's `- Parameters:` block lists buffer, terminalHeight, bgCode, reset. The class's ## Usage block (line 31) shows `writer.writeContentDiff(newLines: outputLines, terminal: terminal, startRow: 1)`.
  <br>truth: The declaration takes five parameters including `terminalWidth: Int` (line 291), which is undocumented while its four siblings are — and it is the one that decides clipping and right-edge padding. `writeContentDiff` takes six arguments, all required: `newLines`, `terminal`, `startRow`, `terminalWidth`, `bgCode`, `reset

### docs-vs-code-styling-image

- **`Sources/TUIkitImage/ASCIIConverter.swift:244`** (high) — says: "This mode with every colour it names made concrete. / Only ``palette(_:)`` names any; the rest are returned unchanged. Callers that render do this once, before consulting a cache keyed on the mode —" and then, mid-sente
  <br>truth: Those four lines are `resolved(with:)`'s doc comment, spliced. In f1ea107e:Sources/TUIkitImage/ASCIIConverter.swift:169-173 that paragraph sat on `resolved(with:)` and ended "— see ``ASCIIPalette/resolved(with:)``."; b50d5114 inserted the new `derived` doc between "keyed on the mode —" and "see ``…``", leaving the firs

- **`Sources/TUIkitStyling/Color/Color+Downsampling.swift:17`** (high) — says: On the public `downsampledToPalette256()`: "`.rgb` is quantized to the nearest 6×6×6 cube color (16–231) or grayscale ramp entry (232–255), whichever is closer."
  <br>truth: A colour with any chroma at all can never take a grey-ramp entry, however close it is. `nearestPalette256Index` computes `mustKeepHue = targetChroma >= hueFloor` (Color+Downsampling.swift:342, hueFloor = 0.01 at line 396) and then `if mustKeepHue && !keepsItsHue[offset] { continue }` (line 355), where `keepsItsHue` is 

- **`Sources/TUIkitStyling/Color/Color+Downsampling.swift:321`** (medium) — says: "candidates (the whole 6×6×6 cube plus the grayscale ramp) are compared in OKLab with the HUE difference weighted double."
  <br>truth: The hue term is weighted ×4, not ×2: `return deltaL * deltaL + chromaWeight * deltaC * deltaC + 4 * deltaH2` (Color+Downsampling.swift:519), and that function's own doc says so — "hue weighted ×4, and chroma LOSS weighted ×4" (line 487-489). It has been 4 since the metric was introduced (5e374e74), so the two doc comme

- **`Sources/TUIkitImage/ASCIIConverter.swift:105`** (medium) — says: On `case ascii(glyphs:)`: "the ideal subset is chosen from the calibrated repertoire (95 glyphs; ~19 distinct density levels for luminance rendering)".
  <br>truth: 95 is right; ~19 is the neighbouring `unicode` pool's number, not ASCII's. Recomputing `GlyphRepertoire.asciiDensityLevels` (GlyphRepertoire.swift:88) over the committed table — the 95 single-scalar glyphs below U+0080 from ImageGlyphCalibration.generated.swift, collapsed by `duplicateLevelEpsilon = 0.010` exactly as d

- **`Sources/TUIkitImage/ASCIIToneCurve.swift:73`** (low) — says: On `Stop.position`: "A curve is a function of LUMINANCE alone — see ``negatesChannels``".
  <br>truth: There is no `negatesChannels`. It was a public stored property added in a2c23221 and deleted in adb51cee, which replaced it with `channels: Channels?` (ASCIIToneCurve.swift:59). The sibling reference was updated in that commit — `stops` now reads "Empty when this is a per-channel curve — see ``channels``" (line 41) — b

### docs-vs-code-views

- **`Sources/TUIkit/Views/Scrollbar.swift:47`** (high) — says: On `ScrollIndicatorVisibility.visible`: "A scrollbar then draws a full-length thumb. The text style has nothing to say about content that isn't there, so it still draws nothing — ``automatic`` and ``visible`` are the sam
  <br>truth: Commit d1c54212 made `.visible` + `.text` draw BOTH "N more" lines at every offset, with a legitimately zero count. The same file, 130 lines below, states the opposite: `alwaysShowsVerticalTextIndicators` is `verticalScrollIndicatorVisibility == .visible && scrollIndicatorStyle == .text` (Sources/TUIkit/Views/Scrollbar

- **`Sources/TUIkit/Views/ScrollFollowMargin.swift:18`** (high) — says: "- `lines(_:)` / `rows(_:)`: scrolling starts once fewer than that many lines (terminal rows) / rows (logical items — a multi-line row counts once) remain visible beyond the selection. For single-line items the two are i
  <br>truth: Neither factory exists. Commit c825d360 ("Follow margin: one unit, meaning whatever the scrollable scrolls by") replaced them with a single `steps(_:)` — Sources/TUIkit/Views/ScrollFollowMargin.swift:93 `public static func steps(_ count: Int)`, whose own doc says so at lines 84-92 ("One knob rather than separate line a

- **`Sources/TUIkit/Views/Spinner.swift:303`** (medium) — says: On the public `Spinner`: "The animation runs automatically via a background task that triggers re-renders at a fixed interval. The task is started when the spinner first appears and cancelled when it disappears."
  <br>truth: There is no task and no appear/disappear lifecycle: `Spinner.swift` contains no `Task`, `.task`, `onAppear` or `onDisappear` at all. `_SpinnerCore.renderToBuffer` picks the frame from the shared content clock (`context.environment.cursorTimer?.elapsed(for: .content)`, Sources/TUIkit/Views/Spinner.swift:455-458) and att

- **`Sources/TUIkit/Views/Scrollbar.swift:78`** (medium) — says: On `ScrollIndicatorStyle.text`: it "costs a row only at an edge that actually has something to report."
  <br>truth: True only under `.automatic`. Under `.scrollIndicators(.visible)` both rows are reserved at every offset whatever is hidden: `ScrollRowWindow.resolve` computes `let always = drawsTextIndicators && alwaysDrawsIndicators` and then `reservesAbove = drawsTextIndicators && (always || showsAbove)` / `reservesBelow = drawsTex

- **`Sources/TUIkit/Views/ScrollFollowMargin.swift:24`** (medium) — says: "- ``centered``: keep the selection centred while scrolling — exactly ``fraction(_:)`` of `0.5`."
  <br>truth: It stopped being `fraction(0.5)` in commit 7c74c271, which gave it its own case carrying a row anchor: `case centered(RowAnchor)` (Sources/TUIkit/Views/ScrollFollowMargin.swift:37), `public static let centered = Self(value: .centered(.center))` (line 68). It coincides with `fraction(0.5)` only for line-space consumers 

- **`Sources/TUIkit/Views/OutlineGroup.swift:37`** (medium) — says: "With the mouse it is the **triangle** that discloses, not the whole row — unlike ``DisclosureGroup``... an outline row's text belongs to whatever the outline is inside, so that a ``List`` can select the node whose trian
  <br>truth: Since commit 8c363353 that is only true of a `List` that selects. In a `List` with no selection binding a click anywhere on the row discloses it: `_ListCore` captures `let clickDiscloses = singleSelection == nil && multiSelection == nil` (Sources/TUIkit/Views/_ListCore.swift:2194) and `resolveRowClick` calls `outline.s

### parameter-docs

- **`Sources/TUIkit/Rendering/FrameDiffWriter.swift:614`** (high) — says: - terminalWidth: The row's full width, which is what says whether the row continues past the run — see `compensatingCursorAdvance`.
  <br>truth: patchingAnimatedRun's signature at Sources/TUIkit/Rendering/FrameDiffWriter.swift:617 is `(in line: String, with frame: String, atColumn column: Int, width: Int, bgCode: String)` — there is no `terminalWidth` parameter. Commit 80ae47c2 ("patchingAnimatedRun's terminalWidth was dead, and its doc promised an end-sensitiv

- **`Sources/TUIkit/Rendering/FrameDiffWriter.swift:282`** (high) — says: - Parameters: - buffer: ... - terminalHeight: ... - bgCode: ... - reset: ... (no `terminalWidth` entry)
  <br>truth: buildOutputLines's signature at Sources/TUIkit/Rendering/FrameDiffWriter.swift:288-293 still takes `terminalWidth: Int` as its second parameter, and it is actively used (passed straight into `buildLine(raw:terminalWidth:bgCode:reset:eraseLine:emptyLine:)` at line 309, and named in the `See` cross-reference two lines be

- **`Sources/TUIkit/Views/Table.swift:250`** (high) — says: The doc comment for the single-selection `Table.init(_:selection:sortOrder:focusID:columnSpacing:emptyPlaceholder:columns:)` appears (reading the source) to document all seven parameters plus a summary sentence.
  <br>truth: Line 250 (and, identically, line 360 for the multi-selection init) is a genuinely blank line with no `///` prefix, sitting between the `- focusID:` bullet (line 249) and the `- columnSpacing:` bullet (line 251), with the `public init(` declaration immediately following at line 254 (resp. the multi-selection init after 

- **`Sources/TUIkitCore/Rendering/OverlayLayer.swift:188`** (medium) — says: - Parameters: bullets for offsetX, offsetY, content, level, zIndex, anchorHeight, centered, dimsBackground, isOpaque — every parameter of `init` except one.
  <br>truth: The init at Sources/TUIkitCore/Rendering/OverlayLayer.swift:200-210 has a ninth parameter, `clampsToScreen: Bool = true` (line 209), with no corresponding `- Parameter` bullet in the init's doc comment, even though all eight of its siblings are documented there. (The stored property itself is separately documented at l

- **`Sources/TUIkitCore/Extensions/KittyGraphics.swift:103`** (medium) — says: - Parameters: - compressed: [long, thorough explanation] — and nothing else.
  <br>truth: `public static func transmit` at Sources/TUIkitCore/Extensions/KittyGraphics.swift:114-117 takes six parameters (`pixels`, `format`, `width`, `height`, `id`, `compressed`), but the doc comment's `- Parameters:` block documents only `compressed`. `pixels`, `format`, `width`, `height`, and `id` (e.g. its valid range rela

### test-docs

- **`Tests/TUIkitTests/TerminalLedgerConformanceTests.swift:42`** (low) — says: On iTerm2, Ghostty and Warp it equals `advance` for every corpus cluster; on Apple Terminal it diverges on 25, and the walk closes the gap per class with measured move sequences...
  <br>truth: The committed measurement record this comment describes, Tools/TerminalProbes/data/apple-terminal-455.1-alternate-landing.json, has 28 entries where advance != landing today, not 25. The '25' was correct when this doc was written (commit ea452100b / de28a2bb8, 2026-08-26/27, when the file held 69 measurements), but com

- **`Tests/TUIkitTests/TerminalLedgerConformanceTests.swift:295`** (low) — says: a backward move on Apple Terminal moves the paint position by an amount that depends on what the glyph did, so `CUB(advance − claim)` lands seven of twenty-five clusters somewhere other than the claim.
  <br>truth: This is the same measurement referenced at line 42 (written in the same original commit, ea452100b, 2026-08-26, when the Apple Terminal record held 69 measurements and 25 divergences). The record has since grown to 78 measurements / 28 divergences (see finding above), so the 'twenty-five' denominator is stale in the sa

### undocumented-public-api

- **`Sources/TUIkitImage/ASCIIConverter.swift:244`** (high) — says: This mode with every colour it names made concrete. Only ``palette(_:)`` names any; the rest are returned unchanged. Callers that render do this once, before consulting a cache keyed on the mode — [this then runs straigh
  <br>truth: That opening paragraph describes `resolved(with:)` (line 268-271: `public func resolved(with palette: any Palette) -> Self`), which turns a `.palette` mode's semantic colours into concrete ones via a `Palette` — not `derived(from:image:depth:)`, which instead picks an adaptive palette's colours from an image. `git show

- **`Documentation/Locating things without drawing them.md:1094`** (medium) — says: `lookupSize`/`storeSize` are called from exactly ONE place in the whole codebase — `measureValueMemoized` in `ValueMemo.swift`, reached only by `EquatableView` and `_MemoizedRow` (it used to be the same code written twic
  <br>truth: `Sources/TUIkit/Views/_ListCore.swift:276` and `:312` (inside `widestRowWidth`, a list's hug-width memo) call `memo.cache.lookupSize(key:view:)` and `memo.cache.storeSize(key:view:size:)` directly, entirely bypassing `ValueMemo.swift`/`EquatableView`/`_MemoizedRow`. This call site was added in commit 32b878384 on 2026-

- **`Sources/TUIkitView/Rendering/RenderCache.swift:16`** (low) — says: `RenderCache` is Phase 5 of TUIkit's render pipeline optimization. It stores the output of ``EquatableView`` instances keyed by their `ViewIdentity`, allowing unchanged subtrees to skip rendering entirely.
  <br>truth: The same cache also stores `_MemoizedRow`'s output — stated two paragraphs later in the same doc comment, line 45: 'Only ``EquatableView`` and `_MemoizedRow` consult the cache at all — `measureChild` / `renderChild` do not.' Confirmed in code: both wrappers route through the shared `renderValueMemoized`/`measureValueMe

- **`Sources/TUIkit/Styling/Theme.swift:40`** (low) — says: public var listStyle: (any ListStyle)? — and public var pickerStyle: (any PickerStyle)? on line 41 — carry no doc comment at all.
  <br>truth: Their sibling property immediately above, `buttonStyle` (line 39), is documented at line 38: '/// Control styles to install, or `nil` to keep the inherited/default style.' Per DocC's adjacency rule that comment attaches only to `buttonStyle`; `listStyle` and `pickerStyle` — otherwise identical in shape and semantics — 


## Performance — 11 landed, 3 reverted, 4 declined (see above)

Twenty-three candidates survived screening (thirteen more were rejected as
not-hot, four as too risky for the gain, two as already tried and reverted). Each
carries its own measurement plan; none of them may be landed without one, and the
two that were measured today came out at −13.6% and −2.8% while a third measured
as a WASH and was reverted — which is the ratio to expect.

### `Sources/TUIkitCore/Extensions/SGRState.swift:218` — per-cell-render

`SGRState.apply(_:)` heap-allocates a `[Parameter]` array for every SGR escape it parses; parse into a fixed inline buffer instead.

**Per.** Per SGR escape sequence. `var codes: [Parameter] = []` grows 1→2→4→8, so `ESC[0m` costs one malloc/free pair and `ESC[48;2;r;g;bm` costs four; `Parameter` carries a `String` payload, so the element type is non-POD and every growth copy and the final destruction pay ARC. Seven call sites, all on per-cell or per-row paths: `ANSIRowCells.init` (String+CellSpanDiff.swift:263, every changed row every f

**Change.** Two parts, separable. (a) Replace `var codes: [Parameter] = []` with a fixed inline buffer of numeric parameters — `InlineArray<16, Int32>` plus a count (Swift 6.2, already sanctioned by CLAUDE.md) — since every parameter this framework emits is numeric and no SGR sequence it emits carries more than sixteen. Keep the existing `[Parameter]` path verbatim as the fallback, taken only when the byte walk meets a non-numeric parameter or a seventeenth one; that keeps the passthrough semantics (`.text`, order-preserving) exactly as they are with no second copy of the netting rules. The 38/48/58 looka

**Measure.** `ab_bench.py` on `translucent` and `gradients` (the blend and the ramp cutter are in the render half), plus `emit_bench.py --scenarios dashboard --window 8.0` for the collapse and the cell-diff decomposition, which `--bench` never runs. The number that should move is cpu-per-frame on `translucent`/`gradients`; malloc/free and `swift_bridgeObjectRel

**Careful.** Ordered by how likely each is to bite. 1. **The measurement plan in the proposal is aimed at the wrong half — fix this first or the run is wasted.** The analyst's headline multiplier (120 escapes per gradient row → ~9,600 `apply` calls per frame, via `collapsingAdjacentSGR` and `ANSIRowCells.init`) is entirely on the **writer/emit** path, which `ab_bench.py --bench` never runs (per `ab_bench misses emission`). `Sources/Stress/Scenarios/Gradients.swift` says so in its own doc comment about band 2: "A horizontal ramp at truecolor is one SGR run per CELL, which is the emission half rather than the render half; `ab_bench.py` cannot see it, so `emit_bench.py` is the tool for this band." So the pr

### `Sources/TUIkit/Rendering/FrameDiffWriter.swift:500` — per-cell-render

`FrameDiffWriter.buildLine` assembles every rebuilt row with a five-link `+` chain and a fresh `String(repeating:)` pad, copying the whole row three times.

**Per.** Per rebuilt row, per frame — every row on a page change, a resize or a scroll, and every row a pulse or a ramp moves. `String.+` is `var result = lhs; result.append(rhs)`, and `result` is a second reference to `lhs`, so each of the four `+` operations makes a full copy of everything to its left. A 120-cell gradient row is ~2.5 KB of escapes and glyphs, so the row is copied three times and allocate

**Change.** Replace line 500 with a reserve-then-append: `var line = ""; line.reserveCapacity(bgCode.utf8.count + eraseLine.utf8.count + mainWithBg.utf8.count + padding + reset.utf8.count); line += bgCode; line += eraseLine; line += mainWithBg; line += asciiSpaces(padding); line += reset` — the same five pieces in the same order, into one buffer sized exactly once. `asciiSpaces` is `public` in TUIkitCore and already imported here.

**Measure.** `emit_bench.py` — `ab_bench.py` is structurally blind here, since `--bench` never calls `buildOutputLines` (Tools/Profiling/README.md is explicit about this). Run `emit_bench.py /tmp/old /tmp/new --scenarios gradients,churn,dashboard --window 8.0` and watch process CPU over the window; lengthen the window before believing a small number, per that R

**Careful.** 1. **Copy the shipped idiom, don't invent one.** Sources/TUIkit/Rendering/BorderRenderer.swift:415-437 is the reference (§41, commit 9056cea4), including the `if pad > 0 { line += asciiSpaces(pad) }` guard. Keep the guard for symmetry even though `asciiSpaces(0)` is `""`. 2. **No new import.** `asciiSpaces` is a public free function in TUIkitCore and FrameDiffWriter.swift imports only Foundation — it is reachable module-wide via `@_exported import TUIkitCore` in Sources/TUIkit/Exports.swift, which is how BorderRenderer.swift and VStack.swift already reach it (neither has any `import` line). 3. **`asciiSpaces` returns `Substring`.** `line += asciiSpaces(n)` compiles through RangeReplaceableCo

### `Sources/TUIkitView/Rendering/ChildInfo.swift:542` — measure-and-layout

Mirror `volatileReadTracker` onto `RenderCache` so the measure memo's gate stops probing the environment dictionary once per measured view.

**Per.** Once per `measureChild` call. From §53's own probe counts (stores/pass: churn 8,516, gradients 17,743, fanout 10,710, deep 6,642) and §56's hit rates (churn 11.7%, framedcolumns 6.2%, kitchensink 1.1%), that is roughly 9,600 probes on a `churn` frame, ~19,700 on `gradients`, ~11,400 on `fanout`. Every one of them is a `[ObjectIdentifier: Any]` hash + probe + `swift_dynamicCast` + retain.

**Change.** `RenderLoop.renderContent` (Sources/TUIkit/App/RenderLoop.swift:441) mints a fresh `VolatileReadTracker()` per frame and puts it in the environment. Have `RenderCache` own that per-pass object instead: mint (or accept) it in `beginRenderPass()`, expose it as a stored field, and have RenderLoop read it back to install in the environment (keeping every `context.environment.volatileReadTracker?.recordVolatileRead()`/`recordRenderSideEffect()` call site untouched — those are on cold-ish modifier paths, not per measured view). Then ChildInfo.swift:542 becomes `if let cache = context.renderCache, le

**Measure.** `Tools/Profiling/ab_bench.py`, 120x40, 15+ reps, scenarios `churn`, `fanout`, `gradients`, `modifiers`, `anyview`, `deep`. cpu-per-frame should fall on all of them, most on the ones with the most measure probes (`fanout`, `gradients`, `churn`); `dashboard`/`megalist` should be flat. Confirm the mechanism with `analyze_timeprofile.py --blame` before

**Careful.** 1. `beginRenderPass` must ACCEPT, never MINT. Spell it `public func beginRenderPass(volatileReadTracker: VolatileReadTracker? = nil)` and assign the field from the parameter every pass (so it resets to nil when not passed). Minting inside it opens the gate on Sources/TUIkit/Rendering/ViewRenderer.swift:112 (a shipped path with no env tracker, where nothing would ever increment the cache's tracker, so every unsafe measurement gets stored) and — the real damage — silently memoises the UN-memoised control arm of Tests/TUIkitTests/MeasureMemoEquivalenceTests.swift (lines 75-77 call `beginRenderPass()` on the `memoised: false` context), making that suite's pixel diff tautological while it keeps p

### `Sources/TUIkit/Views/HStack.swift:127` — measure-and-layout

Collapse `_HStackCore.resolvedLayout`'s five parallel per-child arrays (and `_VStackCore.renderClip`'s four) into one slot array.

**Per.** Per row per walk, and a row is walked 2-4 times a frame (the enclosing column's natural ask, each ScrollView probe, sizeThatFits, renderToBuffer). `resolvedLayout` allocates 5 arrays (`ideal` :127, `idealHeight` :128, `fills` :129, `distributeLinearSpace`'s returned `widths` :173, `finalHeight` :184) plus, inside `distributeLinearSpace`, `result` and (when a spacer is present) `flexIndices`/`weigh

**Change.** Define a private POD slot — `struct RowSlot { var ideal, idealHeight, width, finalHeight: Int; var fills: Bool }` — and build ONE `[RowSlot]` per row, with `ResolvedRowLayout` holding that array instead of separate `widths`/`childHeights` (it is `private`, so this is a local refactor; `fillsHeight(ofChildAt:)` and the `UInt64` mask stay as they are). Give `distributeLinearSpace` a core that writes allocations into a caller-supplied buffer (`UnsafeMutableBufferPointer` or the slot array by key path), keeping the existing `[Int]`-returning signature as a thin wrapper for its other callers; repla

**Measure.** `ab_bench.py`, 120x40, 20 reps, scenarios `menus`, `framedcolumns`, `fanout`, `churn`, `kitchensink`, `dashboard` (the set `8704dcac` moved), plus `deep` and `modifiers` as the null controls. cpu-per-frame should fall on the row-dense ones. Cross-check with `analyze_timeprofile.py --blame` on `Stress --bench --scenario menus`: `_HStackCore.resolved

**Careful.** **Stage it, and measure the stages separately.** Stage 1 (no signature changes, ~2/3 of the allocations, near-zero risk): (a) merge `idealHeight` into `finalHeight` in `resolvedLayout` — mutate `idealHeight` in place at HStack.swift:187/192 and pass it as `childHeights`; spacers are 0 in both spellings, so it is identical by inspection. (b) Remove `flexIndices` from `distributeLinearSpace` (LinearSpaceDistribution.swift:75) and its `weights` companion, in favour of index loops. (c) Replace `childSizes.map(\.width).max() ?? 0` (VStack.swift:340) with a running max taken in PASS 1 — safe because the value is only read when `!hasFlexible`, which excludes every spacer and every flexible child, s

### `Sources/TUIkit/Views/VStack.swift:105` — measure-and-layout

`_VStackCore.clipSizeThatFits` and `_ZStackCore.sizeThatFits` build the `guideSizes` array unconditionally — the two sites `8704dcac` missed.

**Per.** One `[(width: Int, height: Int)]` allocation (16 bytes/element, `reserveCapacity(children.count)`) plus one tuple append per child, per column measure, per walk. `_VStackCore.clipSizeThatFits` is the single most-entered `sizeThatFits` in the framework; `_ZStackCore.sizeThatFits` (ZStack.swift:179-180) is the same pattern.

**Change.** Hoist `let hasGuides = anyAlignmentGuide(in: children)` above the measure loop in both functions, declare `guideSizes` only when `hasGuides` (or `reserveCapacity` only then and skip the appends), and gate the append inside the loop on it. The `if anyAlignmentGuide(in: children)` at VStack.swift:148 / ZStack.swift:194 becomes `if hasGuides`, so the predicate is evaluated once instead of once per measure. Nothing else moves.

**Measure.** `ab_bench.py`, 120x40, 20+ reps, on the scenarios `8704dcac` moved: `menus`, `framedcolumns`, `fanout`, plus `churn`, `deep`, `anyview` (column-dense) and `dashboard` as control. Expect the same shape of result as `8704dcac`, roughly half the size since this is one array rather than two or three. Also worth a Mode A run on the `alignment` tree to c

**Careful.** **The one real trap — ZStack index parallelism.** ZStack.swift:196-205 indexes `guideSizes[$0]` with indices drawn from `children.indices` (`let drawn = children.indices.filter { !children[$0].isSpacer }`). `guideSizes` MUST therefore stay exactly parallel to `children`: gate the append as `if hasGuides { guideSizes.append(...) }` and nothing more. Do not "improve" it by appending only drawn children or skipping spacers — that shifts every index and silently misplaces guides in any ZStack containing a Spacer, in a case no default-alignment test would reach. Keep the `child.isSpacer ? (0, 0) : (size.width, size.height)` ternary inside the append verbatim; the zero entry is load-bearing (the r

### `Sources/TUIkitView/Core/ViewModifier.swift:147` — environment-and-context

Three of the four `AnimationStore.value` call sites still lack the `isSettled` fast path that f7942168 added to the fourth — each pays three environment probes plus a copy-out/write-back per view per walk.

**Per.** Per `.padding()`, per `.foregroundStyle`/`.foregroundColor`, and per gradient stop+geometry number — once per render walk and once per uncached measure walk. `modifiers` has 2 `.padding` + 2 `.foregroundStyle` per row; `deep` has 1 of each per recursion level; a ramp costs 2N+4 store calls (PaintAnimation.swift:78-86, :100-120). On a 40-row/40-level scenario with two-pass layout that is hundreds t

**Change.** Insert the same guard `f7942168` added, immediately before the first environment read, at three sites. (a) `ViewModifier.swift`: move `let key = …` and `let target = modifier.animatableData` (lines 149-151) above the `animation` binding, then `if storage.animations.isSettled(key, at: target, isMeasuring: isMeasuring) { return nil }` before line 147. (b) `ColorAnimation.swift:67`: after `let wanted = data(components)` and before the `storage.animations.value(` call, `if storage.animations.isSettled(key, at: wanted, isMeasuring: context.isMeasuring) { return target }`. (c) `PaintAnimation.swift:

**Measure.** `Tools/Profiling/ab_bench.py OLD NEW --scenarios modifiers deep gradients menus framedcolumns dashboard`. `cpu-per-frame` should fall on `modifiers` and `deep` (padding + foregroundStyle per row/level) and hardest on `gradients` (2N+4 store calls per ramp). Cross-check with the same benchmark f7942168 used, `RenderPerformanceTests/menuPerformance`,

**Careful.** **Pass the same `isMeasuring` the `value(` call at that site passes — this is the only way to get it wrong quietly.** Site (a) `ViewModifier.swift:146` uses the *parameter* `isMeasuring`, NOT `context.isMeasuring`; sites (b) `ColorAnimation.swift:69` and (c) `PaintAnimation.swift:135` use `context.isMeasuring`. The doc on `resolvingAnimation` (AnimatableResolution.swift:24-28) explains why those differ: `context.isMeasuring` means the narrower "a render performed only in order to measure" and is false on the ordinary structural measure walk. Using `context.isMeasuring` at (a) would stamp `lastPass` on walks that must not write, changing which records survive the prune. Do NOT "harmonise" (b)

### `Sources/TUIkitView/Rendering/RenderContext.swift:161` — environment-and-context

`RenderContext.environmentApplicationDepth` is an `Int` that lands alone in an 8-byte slot; as a `UInt16` the struct drops from 104-byte stride to 96 and every context copy in the framework gets a word narrower.

**Per.** Every `RenderContext` copy: `withChildIdentity` (x4 overloads), `withEnvironment`, `withAvailableWidth/Height/Size`, `forBorderedContent`, `placingGradientChild`, `invalidatingMeasureMemo`, plus every `var copy = context` in a container. That is several copies per view per walk, on both walks — the single most-copied struct in the codebase.

**Change.** Rename the stored property to a `private var _environmentApplicationDepth: UInt16 = 0` declared among the existing flags (after `measureGeneration`), and keep `public var environmentApplicationDepth: Int { get { Int(_environmentApplicationDepth) } set { _environmentApplicationDepth = UInt16(truncatingIfNeeded: newValue) } }`. Truncating rather than trapping, for the reason `9fa3453f` gives about narrowing conversions on cache-key paths. All six existing uses (`Environment.swift:49,87,140`, `TintModifier.swift:128,138`, `Theme.swift:118,156`, `ColorEnvironment.swift:198,207`) keep compiling unc

**Measure.** Verify the layout first, exactly as `render-context-field-cost` prescribes: `print(MemoryLayout<RenderContext>.size, MemoryLayout<RenderContext>.stride)` must go from `97 104` to `89 96`. If it does not, the change is worthless and should be dropped without benchmarking. Then `Tools/Profiling/ab_bench.py OLD NEW --scenarios anyview modifiers deep f

**Careful.** **Declaration position IS the change.** The `UInt16` must go immediately after `measureGeneration: UInt8` (which ends at offset 51), because offset 52 is padding that already exists and is 2-aligned. Put it before the Bools, or after `gradientFrame`, and it re-pads and the win silently evaporates — Swift lays fields out in declaration order and never reorders. **Verify the layout before benchmarking anything.** `print(MemoryLayout<RenderContext>.size, MemoryLayout<RenderContext>.stride)` must read `89 96`. If it reads anything else, drop the candidate without spending a bench run — that is the whole gate. **`swift package clean` on BOTH sides — this is the one that bites.** This is a stored-

### `Sources/TUIkitView/Rendering/RenderContext.swift:37` — environment-and-context

`RenderContext.environment`'s `didSet` re-derives both mirrored services from the dictionary on every environment write, though nothing in a render pass ever changes them.

**Per.** Two dictionary probes plus two `swift_dynamicCast`s per environment assignment. The 2026-09-06 menu counts put that at 46 writes/frame producing 45 `StateStorage` + 45 `RenderCache` reads — 13% of all 687 environment reads on that frame — and the write count scales with the tree: `grep -c 'environment\.[a-z]* = '` over `Sources/TUIkit` and `Sources/TUIkitView` finds ~130 in-place assignment sites,

**Change.** Split `environment` into a plain stored `private var _environment` plus a computed façade, so the mirrors are set at construction and carried by every structural copy rather than recomputed. Keep a `set` that calls `mirrorServices()` for the (rare, root-only) wholesale replacement, and add the cheap route the tree actually uses — a `package mutating func mutateEnvironment(_ body: (inout EnvironmentValues) -> Void)` (and a `withEnvironmentPreservingServices(_:)` for `EnvironmentModifier`/`TransformEnvironmentModifier`/`_StyleEnvironmentView`/`TintModifier`/`Theme`) that yields `_environment` in

**Measure.** `Tools/Profiling/ab_bench.py OLD NEW --scenarios menus dashboard kitchensink framedcolumns tables deep`. Confirm the mechanism with a throwaway key histogram in `EnvironmentValues.subscript.getter`: `StateStorage` and `RenderCache` reads/frame on `menus` should go from ~45 each to ~1 each, and total env reads/frame from ~687 to ~600. Take counts an

**Careful.** **Scope it to the two existing mirrors. Do not bundle candidate 2's padding, and do not mirror `volatileReadTracker` at all** — `ValueMemo.swift:119,188` and `_ListCore.swift:285` install a subtree-scoped tracker mid-walk, so its "written once" premise is false and the cheap route applied there would break the memo's volatility gate. 1. **The façade must keep in-place mutation, or the change is a net loss.** Today `context.environment.foo = y` is an in-place `modify` (SE-0268: a `didSet` not referencing `oldValue` gets one), so there is no dictionary copy. A plain `get`/`set` computed property replaces that with get-copy-mutate-set, i.e. a COW deep copy of ~16 `[ObjectIdentifier: Any]` entri

### `Sources/TUIkitView/Rendering/ChildInfo.swift:542` — caches-and-memos

Take VolatileReadTracker off the `[ObjectIdentifier: Any]` environment dictionary and hang it on RenderCache, which RenderContext already mirrors as a stored field.

**Per.** One environment-dictionary probe + `swift_dynamicCast` to `VolatileReadTracker?` per MEASURED CHILD. Measured counts from the record: 71 reads/frame on the Mode A `menu` tree (3rd-hottest key, ahead of StateStorage 45 and RenderCache 45, out of 687 env reads/frame); ~14,409/frame on `fanout` at scale 1 (§3's measures/frame table). Plus ~30 `recordRenderSideEffect()` sites, one per modifier per vis

**Change.** Add `var volatileReadTracker: VolatileReadTracker?` to `RenderCache`; clear/install it in `beginRenderPass()`. `RenderLoop.swift:441` sets it on the cache instead of (or as well as) the environment. Hot readers become `cache.volatileReadTracker`: `ChildInfo.swift:542`, `ValueMemo.swift:115` and `:184` (which then no longer need `context.withEnvironment(environment.setting(\.volatileReadTracker, to:))` at all — one fewer EnvironmentValues COW copy per memo miss). The ~30 `context.environment.volatileReadTracker?.recordRenderSideEffect()` sites become `context.renderCache?.volatileReadTracker?..

**Measure.** `Tools/Profiling/ab_bench.py`, paired CPU, all scenarios (it is a whole-pipeline change, so no scenario may be assumed). Expect movement on the measure-heavy shapes where `measureChild` count is highest — `fanout`, `deep`, `modifiers`, `textwall`, `anyview` — and on `menus` via the Mode A tree. Confirm mechanism with `analyze_timeprofile.py --calle

**Careful.** Build ONLY the narrow version. Change `ChildInfo.swift:542` and nothing else on the read side: add `var volatileReadTracker: VolatileReadTracker?` to `RenderCache`, and make the gate `if let cache = context.renderCache, let tracker = cache.volatileReadTracker`. Leave `EnvironmentValues.volatileReadTracker` in place as the source of truth, leave all ~30 `recordRenderSideEffect()` sites alone, leave `GradientGraphics.swift:107` / `ButtonStyle.swift:839` / `ServiceEnvironment.swift:196` alone (they would swap one dictionary probe for another and gain nothing), and leave `RenderLoop.swift:583`'s `usesPulse` read alone. That keeps the diff to about five lines and removes the last env-dictionary a

### `Sources/TUIkitView/Rendering/RenderCache.swift:915` — caches-and-memos

Two of the three prune loops mutate a dictionary while iterating its own `.keys`, which COW-copies the whole table; the third loop in the same two functions already does it right.

**Per.** One full duplication of the table — allocation plus N key/value copies, with a retain/release on every `ViewIdentity` key and every `Any` snapshot — per call that removes at least one entry. `sizeEntries` was 724 entries on the live dashboard (§47's prune line), and `clearAffected(by:)` runs once per queued `@State` identity per frame plus once per environment change noticed mid-render.

**Change.** Mirror the `entries` spelling: `let staleSizeKeys = sizeEntries.keys.filter { !isLive($0.identity) }` then remove; likewise in `clearAffected`; and for `appliedEnvironment`, build the stale-slot array first (`appliedEnvironment.filter { $0.value.lastSeenFrame < frameCounter }.map(\.key)`, or a reused scratch array) before removing.

**Measure.** The bench barely exercises this (`Stress --bench`'s own prune line reads `dropped: 0` in the steady state), so measure live: `Tools/Profiling/idle_cpu.py` under autopilot on `dashboard` and `kitchensink`, plus a PTY interaction that actually fires `clearAffected` every frame — a slider drag or a list scroll on the Example — with `analyze_timeprofil

**Careful.** 1. **Do not use the analyst's `appliedEnvironment` spelling.** `appliedEnvironment.filter { $0.value.lastSeenFrame < frameCounter }.map(\.key)` calls `Dictionary.filter`, which returns a **Dictionary** — it builds and rehashes a whole new table, reintroducing the copy it is meant to remove and adding a rehash. Use `appliedEnvironment.compactMap { $0.value.lastSeenFrame < frameCounter ? $0.key : nil }` (an Array), or a plain `var stale: [EnvironmentSlot] = []` loop. `entries.keys.filter`/`sizeEntries.keys.filter` are fine — `Keys` is a Collection, so `filter` there returns `[Key]`. 2. **The temporary must die before the removals.** The win exists only because the `Keys` view is released at th

### `Sources/TUIkitView/Rendering/RenderCacheKeys.swift:21` — caches-and-memos

`RenderCache.SizeKey` still carries a whole `ViewIdentity` chain in the key — the exact cost the per-pass measure key was converted away from, and never converted here.

**Per.** Two `ViewIdentity` retain/release pairs per probe (key construction, then the copy into the dictionary probe) plus an `IdentityNode.structurallyEqual` chain walk on every EQUAL key — the `===` shortcut misses, because the two chains were built by separate walks, so a hit walks all ~8–12 nodes comparing cachedHash, depth and step. Probed once per `_MemoizedRow`/`EquatableView` measure that got past

**Change.** Replace `identity: ViewIdentity` with `identityHash: Int` in `SizeKey`, folded exactly as `MeasureKey.identityHash` is. `sizeEntries` is cross-frame and both prunes ask `isLive(key.identity)` / `affects(key.identity)`, so move the identity into `SizeEntry` (RenderCache.swift:195) and make `SizeEntry` a `final class` — the same conversion §36 made to `CacheEntry`, so the prune's per-entry copy is one class reference rather than a `ViewIdentity` plus an `Any`. Call sites: `ValueMemo.swift:171`, `_ListCore.swift:257`. `ChildViewsKey` is the easier twin — its table is per-pass scratch, so nothing 

**Measure.** `ab_bench.py` paired CPU on all scenarios, and specifically `fanout`, `textwall`, `churn` (highest `_MemoizedRow` measure traffic) and `megalist`/`table` (which exercise the `_ListCore` hug memo). Watch the prune side too: `Stress --bench`'s prune line and the live `dashboard`, since the prune loop's per-entry cost changes shape. Run `TUIKIT_VERIFY

**Careful.** **Do NOT fold `measureGeneration` in, despite the proposal saying "folded exactly as `MeasureKey.identityHash` is".** `measureIdentityHash` (`Sources/TUIkitView/Rendering/ChildInfo.swift:607`) xors `context.measureGeneration` into the hash. `SizeKey` ignores that field today. Folding it in is a real, non-collision behaviour change to what menu rows measure to — `MenuPopover.swift:196/265/331` bump the generation precisely to invalidate measurements, and `menus` sends all 108 of its row measures/frame through this memo. Set `identityHash = identity.structuralHash` and nothing else. That has the bonus of making the computed hash **bit-identical to today's** (it is already the first and only id

### `Sources/TUIkit/Views/Table.swift:3437` — lists-tables-scrolling

`_TableCore.alignText` allocates 3 strings and scans the cell's width twice, per cell, per line, per frame — it is what §32's row rewrite left behind.

**Per.** Per CELL per drawn line per frame. `tables-scroll` = 8 tables x 25 rows x 5 columns = 1,000 calls/frame (the ScrollView gives unbounded height, so every table draws every row). `table` = ~34 visible rows x 8 columns = ~272. `table-multiline` = ~17 rows x up to 3 lines x 4 columns = ~200. Call sites: 1715 (renderRow), 3201 (renderMultiLineRow, once per cell per LINE), 3015 (header, negligible).

**Change.** Two independent halves, committable separately. (1) Kill the duplicate scan: add an internal width-returning form of truncation — `func truncatedToWidth(_:mode:) -> (text: String, visibleWidth: Int)` in Sources/TUIkit/Extensions/String+Truncation.swift, which returns `(self, visible)` on the existing early-out at line 60 and `(result, result.strippedLength)` otherwise. `alignText` uses the returned width as `visibleLength`. Exactly one scan in both branches (today: two in the fitting branch, two in the truncating branch). (2) Kill the allocations: give `alignText` an append-into-buffer form, `

**Measure.** `ab_bench.py /tmp/old /tmp/new --scenarios tables-scroll,table,tables-vstack,table-multiline,megalist --reps 20`, then the full sweep before committing. `tables-scroll` is the one to watch — it is 98% render-dominated and has the most cells. Also worth a `--cold` run, though nothing here is a cache. Confirm attribution the way §40.1 says to: build 

**Careful.** 1. Do NOT add a same-signature overload. Five of the sixteen `truncatedToWidth` call sites in Sources/ spell it `truncatedToWidth(w, mode: m)` into a type-inferred `let`; a second method differing only in return type makes those ambiguous. Give the measured form a distinct name in the house style already set by §40 — e.g. `truncatedToWidth(_:mode:) -> (text: String, visibleWidth: Int)` renamed to something like `truncatingToWidth(_:mode:)`, or better, a private impl with the tuple and keep the existing spelling as a wrapper returning `.text`, so there is still one rule. 2. The returned width MUST be a scan of the result in every truncating branch. Do NOT derive it analytically from `keep` / 

### `Sources/TUIkit/Focus/ItemListHandler+FrameInputs.swift:78` — lists-tables-scrolling

Every `List` and `Table` rebuilds the whole row-shortcut chord table from scratch on every pass — a fresh Dictionary, 11 `Set` literals and ~50 hashes, to produce a value that is identical for every list on the page and never changes.

**Per.** Per List/Table per PASS, not per frame. `_ListCore.resolvePopulatedHandler` (_ListCore.swift:991), `_TableCore.resolveHandler` (Table.swift:1849) and `_TableCore.buildMultiLineContent` (Table.swift:1206) all route through `syncFrameInputs`. `resolveHandler` runs in the MEASURE pass too (from `analyticSingleLineSize`, Table.swift:578, whenever `data.count > rowArea`), so `tables-vstack` — 8 tables,

**Change.** Memoise it on the handler, the way `extentMeanCache` already is (ItemListHandler.swift:124). Add `private var shortcutsKey: (RowShortcuts, CommandKeyBinding)?` beside `shortcuts`, and in `syncFrameInputs` replace line 78 with a guarded rebuild: if the pair equals the stored key, keep `shortcuts`; otherwise rebuild and store. No global mutable state, no actor-isolation question, no change to `RowShortcuts` or its public API — and it follows the file's own stated design ("the chord -> action map ... built once per render rather than scanned per keystroke"; this makes "once per render" mean once 

**Measure.** `ab_bench.py --scenarios tables-vstack,tables-scroll,table,table-multiline,megalist,preferences --reps 20`. `tables-vstack` is the sensitive one (8 tables x measure+render). Cheap sanity check on the mechanism before benching: it is a per-handler cache, so `--cold` (which resets the state store, and therefore the handlers) should show LESS improvem

**Careful.** 1. **The Optional-tuple comparison does not compile.** Tuples do not conform to `Equatable`, so `shortcutsKey == (env.rowShortcuts, env.commandKey)` is rejected for an `Optional` LHS. Either unwrap first (`if let key = shortcutsKey, key == (a, b)` — the free tuple `==` applies to the concrete tuple) or, cleaner, declare a tiny `private struct ShortcutsKey: Equatable { let shortcuts: RowShortcuts; let commandKey: CommandKeyBinding }`. 2. **Start the key `nil`; do not seed it.** `shortcuts` already defaults to `RowShortcutLookup.default` (ItemListHandler.swift:124). Seeding the key with `(.default, .control)` to claim a frame-1 hit couples two independently-declared defaults (`RowShortcutsKey.

### `Sources/TUIkit/Views/Table.swift:1148` — lists-tables-scrolling

A multi-line `Table` builds every visible cell's value string TWICE per frame — once to learn the row's height, once to draw it — and the wrap memo hides only half of what that costs.

**Per.** Per visible cell per frame. `table-multiline` at 120x40: ~17 visible rows x 4 columns = ~68 duplicated `column.value(for: item)` invocations plus ~68 duplicated `FitKey` constructions and SipHash-over-the-whole-string probes, every frame. The `Details` closure is `Self.details(row.h)` — seven `Synth` calls and an interpolation producing a ~120-character string.

**Change.** Widen the per-render memo in `buildMultiLineContent` from height to layout: `var layoutCache: [Int: (cells: [[String]], height: Int)]`, filled by one function that calls `cellLayout(for: data[index], columnWidths:)` and returns both. `heightOf(_:)` becomes `layout(_:).height`; `composeMultiLineRows`/`renderMultiLineRow` take the cells from the same cache instead of calling `cellLayout` again (pass the accessor down, as `heightOf` is already passed to `syncIndicatorChrome` and `multiLineScrollbarCells`). `rowHeight(of:columnWidths:)` then has only one caller left — `multiLineOverflows` (1487), 

**Measure.** `ab_bench.py --scenarios table-multiline --reps 30` warm, then `--cold`. Watch `table` and `tables-scroll` for a regression (they never reach this path, so they must read indistinguishable — if they move, it is inlining, per §40.1). An Instruments run via `record.sh` should show `partial apply for thunk (@in_guaranteed TableColumn)` and `TextWrappi

**Careful.** 1. Do NOT route the escaping closure at line 1209 (`handler.syncFrameInputs(rowHeight: { rowHeight(of: data[$0], columnWidths: columnWidths) })`) through the new cache. It is stored on the `ItemListHandler` and called between renders on key events; capturing the cache variable (Swift captures `var` by reference) would retain every cached row's `[[String]]` on the handler until the next frame replaces the closure. Leave it on `rowHeight`. 2. `rowHeight` keeps TWO callers, not one as the proposal states: `multiLineOverflows` (1488) computes its own widths at `innerWidth - 1`, and `analyticMultiLineSize`'s non-overflowing branch (678) computes its own widths too. Neither may read this cache -- 

### `Sources/TUIkitImage/ASCIIConverter+Recolouring.swift:103` — image-per-pixel

`recoloured` runs a full Otsu histogram pass over every pixel and then throws the answer away for every mode except `.mono`.

**Per.** One pass per pixel of the resampled picture — 816,000 in the harness's `--path pixel`, ~1,050,000 for a realistic full-screen placement. Per conversion, and a conversion happens on every `TerminalImageStore` miss: first paint, resize, zoom, and every tick of a settings drag.

**Change.** Move the call below the truecolor guard and gate it on the mode: `let monoThreshold = colorMode == .mono ? Self.monoInkThreshold(for: scaled) : Self.midLuminance`. `self.colorMode` is knowable up front — `derived(from:depth:)` (ASCIIConverter.swift:263) only rewrites `.palette`, so it can neither produce nor consume `.mono`. Do the same on the glyph path at `ASCIIConverter.swift:604`, where the consumers are braille (always), `.blocks(.fine)` mono and `.blocks(.solid)` mono; the character and shape renderers never receive it. The glyph grid is small (12,000 px for `.blocks(.fine)` at 120×50) s

**Measure.** `ImageHarness --path pixel --mode truecolor --iterations 20` and `--mode ansi256`, base and new binaries alternated three times (the README's rule — `ab_bench.py`'s paired statistics do not apply to this harness). ns/pixel should drop: truecolor 8.2 → roughly 6.3–7.0, ansi256 10.5 → roughly 9.0–9.5. `--mode mono` must be unchanged, and `--path glyp

**Careful.** - **Pixel path only.** Move `Self.monoInkThreshold(for: scaled)` from `+Recolouring.swift:103` to below the `guard colorMode != .trueColor` at :105, and gate it: `let monoThreshold = colorMode == .mono ? Self.monoInkThreshold(for: scaled) : Self.midLuminance`. Leave `ASCIIConverter.swift:604` alone (see below). - **Keep it above the dither and above `quantise`.** It may sit either side of the `let colorMode = colorMode.derived(from: scaled, depth: .truecolor)` shadow at :119 — `derived` cannot change mono-ness — but it must stay before `applyFloydSteinbergDithering` / `scaled.quantise(…)`. Do not let it drift below them: `scaled` is mutated in place there, and measuring after the dither is m

### `Sources/TUIkitImage/ASCIIConverter+RowBuilder.swift:21` — image-per-pixel

The glyph path resolves its colour mode — and takes an `NSLock` — once per CELL, the cost `PixelQuantiser` was built to remove from the pixel path.

**Per.** `cellColor(for:mode:)` is called once per cell from five renderers and TWICE per cell from `convertHalfBlocksColor` (ASCIIConverter+HalfBlocks.swift:108–109), the default charset — 12,000 calls for a 120×50 grid. On the pixel path the same lock is taken per table-distrusted pixel, which for `.adaptive(64)` is a large fraction of a megapixel.

**Change.** Two parts, two commits. (1) A per-conversion resolver in the shape of `PixelQuantiser`: plain stored properties (a payload-free kind, the resolved `ASCIIPalette`, its `SearchIndex?`, and `colors`), built once in `convert` and passed to the renderers in place of `mode`; `cellColor` becomes a method on it that matches on nothing with a payload and calls the index directly. The index is resolved once — `let index = (palette.mapping == .nearestColor && palette.entries.count > ASCIIPalette.indexedEntryThreshold) ? palette.searchIndex : nil` — which is exactly the condition at ASCIIPalette.swift:327

**Measure.** `ImageHarness --path glyph --mode ansi256 --iterations 30` (the headline: 112 ns/cell) plus `--mode shades256` (252) and `--mode optimal64` (360); and `--path pixel --mode optimal64` (34.3 ns/pixel) for the fallback half. `--mode truecolor` should be flat — it binds no palette — which is a useful null within the same run.

**Careful.** 1. BUILD THE RESOLVER AFTER LINE 598 of ASCIIConverter.swift — `effectiveMode = effectiveMode.derived(from: scaled, depth: depth).effective(for: depth)`. An adaptive palette's colours are chosen there, and again fitted to the depth; a resolver built from `colorMode` or from the pre-derivation `effectiveMode` silently paints an adaptive image in the wrong colours, and NO test catches it (every image test uses a fixed palette). Same for the dither call two lines below, which builds its own PixelQuantiser from the same value. 2. ONE IMPLEMENTATION, NOT TWO. Do not transcribe nearestIndex's dispatch into the resolver. Put the resolved pieces in one small type (payload-free kind, the resolved ASC

### `Sources/TUIkitImage/RGBAImage.swift:408` — image-per-pixel

`sharpened` sweeps three megabyte-scale arrays COLUMN-major, and pays nine protocol-witness `Double(UInt8)` conversions plus a wasted 24 MB zero-fill per picture.

**Per.** Per pixel of the resampled picture (a megapixel on the graphics path), ×3 arrays. It is the most expensive single stage in the pipeline when enabled: 516 ms per megapixel in debug against `scaledBilinear`'s 248 and the Otsu pass's 81 (commit 5e2dfc87's table).

**Change.** (1) Turn the vertical pass row-major: keep one running-sum triple per COLUMN in a `width`-sized scratch array, prime it with `for y in 0...spanY { for x in 0..<width { … } }`, then walk `y` outer / `x` inner. (2) `Double(Int(byte))` at all four sites, and hoist the loops onto `withUnsafeBufferPointer` / `withUnsafeMutableBufferPointer` for `pixels`, `rowBlur` and `result` — the treatment `mapPixels`, `scaledBilinear` and `Histogram.init` already have. (3) Build `rowBlur` with `[Double](unsafeUninitializedCapacity:)`. A follow-on worth its own commit: the vertical pass only ever needs rows `y−s

**Measure.** Needs one harness flag: an `--edge-contrast <amount>` argument on `ImageHarness` that passes it to the `ASCIIConverter` (three lines; the harness currently constructs the converter with only `colorMode:` and `dithering:`, so this stage is completely unmeasured today). Then `--path pixel --mode truecolor --edge-contrast 0.6` isolates it almost clean

**Careful.** **Split into separate commits and measure each, because I expect two of the three to measure as nothing in release.** Commit A: traversal reorder + unsafe buffers (the one likely to pay). Commit B: `Double(Int(byte))` at the four sites — justify it as finishing the documented module-wide sweep, not as a measured win, so a neutral A/B does not get it reverted. Commit C: `unsafeUninitializedCapacity`. Optional D: the rolling window. Per one-change-per-commit, do not batch A with B. **The proposal contains one outright bug.** It says prime with `for y in 0...spanY`. The current code is `for y in 0...min(height - 1, spanY)` (line 409) and the clamp is **live on the real glyph path**: shape-aware

### `Sources/TUIkitImage/RGBAImage.swift:234` — image-per-pixel

`scaledBilinear` recomputes its per-column geometry for every row — ten operations per pixel whose answer depends only on `x`.

**Per.** Per output pixel, on EVERY conversion on both paths — 816,000 for the harness's pixel path, and it is ~75% of the truecolor pixel path (248 ms of 330 debug per megapixel).

**Change.** Before the row loop, build a `targetWidth`-entry table of `(x0: Int, x1: Int, xFrac: Double, oneMinusX: Double)` using the same expressions in the same order, and read it through an unsafe buffer inside the inner loop. The four weights, the premultiply, the divide and the rounding are untouched.

**Measure.** `ImageHarness --path pixel --mode truecolor --iterations 20`, which after candidate 1 is very nearly a pure `scaledBilinear` benchmark. Also `--path glyph --mode truecolor` (93 ns/cell), where the resample is a smaller share.

**Careful.** - Transcribe, do not re-derive. `xFrac` must be `sourceX - Double(x0)` using the CLAMPED x0, and both clamps must stay `> sourceWidth - 1` in the same order. Computing xFrac from an unclamped `Int(sourceX)` is the one way to change output, and it would only show on the shapes where clamping bites. - One table entry, one load: a single array of a 4-field struct (`x0`, `x1`, `xFrac`, `oneMinusX`), not four parallel arrays — at -Onone each extra `UnsafeBufferPointer` subscript is another non-inlined call, and four of them can eat the win the hoist buys. - Build the table (and take its `withUnsafeBufferPointer`) OUTSIDE `pixels.withUnsafeBufferPointer` / `[RGBA](unsafeUninitializedCapacity:)`, n

### `Sources/TUIkit/App/RenderLoop.swift:1126` — idle-and-wakes

RenderLoop.keepAnimating asks two whole-store scans per frame whether anything is animating — answer it in O(1) when nothing is.

**Per.** Two full scans per frame: `AnimationStore.hasLiveAnimations` walks every entry of `records` (one per animatable layout node — hundreds), and `DepartureStore.hasDepartures` walks every entry of `entries` (one per currently-present `.transition` view). On the overwhelming majority of frames both answers are `false`, and the walk is pure overhead.

**Change.** In `AnimationStore`, keep `private var runningCount = 0` — the number of records whose `animation != nil`. Maintain it in the one place that writes whole records, `store(_:for:isMeasuring:)`: use `records.updateValue(stamped, forKey: key)`, and adjust by `(stamped.animation != nil ? 1 : 0) - (previous?.animation != nil ? 1 : 0)`. Decrement for each removed record in `endRenderPass`, `removeDescendants(of:)`, and zero it in `removeAll()`. Then make `hasLiveAnimations(at:)` start with `guard runningCount > 0 else { return false }` and otherwise run the existing scan untouched. Do the same in `De

**Measure.** **Not measurable with the bench as committed** — `Sources/Stress/Headless.swift:205-224` runs `stateStorage.beginRenderPass/endRenderPass` and `renderCache.beginRenderPass/removeInactive` per frame but never asks the run loop's animation question, so `--bench` cannot see this. That is itself a bench-fidelity gap of the kind §43.1 fixed. The honest 

**Careful.** Scope: **AnimationStore only. Do not do the DepartureStore half** — `entries` is one per present `.transition` view (usually zero), `beginRenderPass` already walks it unconditionally, and `hasDepartures` has no test coverage. It would add the only unaudited count for no measurable gain. Then: 1. The proposal's premise "`store` is the one place that writes whole records" is **wrong**. `value(for:target:animation:nowNanos:isMeasuring:)` also writes a whole record at AnimationStore.swift:172-175 (`records[key] = record`, the re-declaration pass stamp). It is animation-neutral, so the count stays sound — but leave it alone deliberately and say so in a comment, or a later reader will "fix" it int

### `Sources/TUIkit/Rendering/OpacityBlend.swift:416` — allocation-and-arc

A blend cell converts a Color to SGR state by spelling it as five Strings and parsing them back — per cell of every translucent overlay.

**Per.** Per covered CELL of a faded region, 1–4 times: `settingBackground(field)` at :87, `settingForeground/Background` at :115–116, `settingBackground(surface)` at :133, plus :261 and :316 inside `blend`, and :393–394 per reversed cell in `cells(in:through:)`. On the `translucent` scenario's faded panel at 120×40 that is thousands of calls per frame; each one builds a `[String]` of up to 5 elements, int

**Change.** Add `SGRState.setForeground(_ color: Color?, depth:)` / `setBackground(_ color: Color?, depth:)` that map straight from `color.downsampled(to: depth).value` to the private `Colour` enum — `.standard(a) → .named(a.foregroundCode)`, `.bright(a) → .named(a.brightForegroundCode)`, `.palette256(i) → .indexed(Int(i))`, `.rgb(r,g,b) → .rgb(Int(r), Int(g), Int(b))`, `.semantic → fatalError` (unchanged) — and treat `depth == .noColor` as "do nothing", which is what today's empty-array guard at SGRState.swift:181 already means. Point `OpacityBlend.settingForeground`/`settingBackground` at the new overlo

**Measure.** `Tools/Profiling/ab_bench.py`, cpu-per-frame, 120×40, ≥8 reps, on `translucent` (baseline ≈11,350 µs/frame per §51) and `animating`; `dashboard`/`kitchensink` as null arms. Run the null test (clean binary against itself) on `translucent` at the same rep count first — §41.1's rule. Then live: `idle_cpu.py <binary> 2 6` with `TUIKIT_STRESS_AUTOPILOT=

**Careful.** 1. ORDER THE NIL CHECK BEFORE THE DEPTH CHECK. Today `settingForeground(nil)` passes `nil` parameters and clears the colour (SGR 39) at EVERY depth, including `.noColor`; only a non-nil colour at `.noColor` is the "do nothing" case (SGRState.swift:170-190). A new overload that opens with `guard depth != .noColor else { return }` silently stops clearing on nil at `.noColor`. `SGRStateColourSetterTests.noColorLeavesTheStateAlone` only iterates `colours.compactMap { $0 }`, so it will NOT catch this. This is the same shape as the bug that doc comment was written for (a faded bold heading losing its emphasis on a monochrome terminal). 2. USE THE SLOT-CORRECT CODE. `.standard` -> `foregroundCode` 

### `Sources/TUIkit/Modifiers/BackgroundModifier.swift:102` — allocation-and-arc

A ramp background rebuilds the same SGR escape once per run — which on a truecolor ramp is once per cell — where the foreground twin already memoises it per ramp entry.

**Per.** Per ramp RUN per row per frame, and §54's own words: "for a smooth truecolor ramp that is one run per column — 120 of them on a 120-cell row". At 120×40 that is ~4,800 calls per frame, each rebuilding a `[String]` of 5 elements, a `joined(separator:)`, and two `+` concatenations of a ~20-byte (heap, past the 15-byte small-string limit) escape.

**Change.** Two independent pieces. (a) Have `RampSampler` expose the runs' ramp ENTRY alongside the colour (`runs(row:cells:)` at PaintRenderer.swift already computes `current` — return it), and keep a lazily-filled `[String?]` escape table of `sampler.ramp.count` slots for the view, exactly like `band`'s `sequences`, so `backgroundEscape()` runs at most once per distinct ramp colour instead of once per run. (b) Split `result += ANSIRenderer.applyPersistentBackground(slice, color:)` into `result += escape; result += ANSIRenderer.restating(escape, afterResetsIn: slice)`, dropping the intermediate concaten

**Measure.** `ab_bench.py`, cpu-per-frame, 120×40, ≥8 reps: `gradients` is the claim (baseline ≈20,280 µs after §54), with `dashboard` (≈85), `kitchensink` (≈590) and `churn` as null arms — §54's own first cut regressed `kitchensink` +1.7% by adding small per-row arrays, so watch the low-run-count scenarios. Confirm `Stress --bench` checksums unchanged. Then `i

**Careful.** Land (b) and (a) as separate commits, and treat the `reserveCapacity` as a third, independently-measured piece — it is the one most likely to backfire. (b) first, alone: hoist `let escape = ANSIRenderer.backgroundCode(for: colour)` and emit `result += escape; result += ANSIRenderer.restating(escape, afterResetsIn: slice)`. This is byte-identical by construction and drops one heap string per run. If (a) later measures as nothing, (b) may still stand on its own. (a), the escape table: - Change `RampSampler.runs(row:cells:)` to yield `(columns: Range<Int>, entry: Int)` and drop the `colour` member entirely — `current` is already in hand at PaintRenderer.swift:503-509, and the caller can do `sam

### `Sources/TUIkitCore/Extensions/SGRState.swift:218` — allocation-and-arc

`SGRState.apply` allocates a non-POD `[Parameter]` array per escape sequence, on five per-row-per-frame parsers.

**Per.** Per SGR escape. Callers: `collapsingAdjacentSGR` (String+SGRCollapsing.swift:170 — every escape of every rebuilt row, and the doc's own measurement is 2,565 escapes in one 120×40 repaint frame), `ANSIRowCells(decomposing:)` (String+CellSpanDiff.swift:263, per escape of every changed row, both sides of the diff), `OpacityBlend.cells` (:348, per escape of 2–3 rows per blended row), and String+ANSISp

**Change.** Represent a parameter as a POD: `.number(Int)` unchanged, and the non-numeric case as a UTF-8 offset range into the sequence rather than a `String` (materialised only in the rare `passthrough.append` branch, which is the sole consumer). Then hold the codes in an `InlineArray<8, Parameter>` plus a count — CLAUDE.md endorses `InlineArray` — with the existing heap array kept as the overflow arm beyond 8 so an arbitrarily long list still parses. `apply(_ codes:)`, `extendedColourSpan` and `applyExtendedColour` become generic over an index-addressable view of the codes (`applyExtendedColour`'s `cod

**Measure.** `ab_bench.py` on `translucent` (the per-cell parser) and `churn`; `Tools/Profiling/emit_bench.py` for the output half, which is where `collapsingAdjacentSGR` and the cell-span diff actually run and which `--bench` never exercises (README, and the `ab_bench misses emission` memory). Live: `idle_cpu.py` on `dashboard` with a ≥12 s emission window — §

**Careful.** STAGE IT. Measure step 1 alone first; if it lands the win, stop. Step 1 (zero behavioural risk, two lines): `codes.reserveCapacity(8)` at the top of `apply(_ sequence: String)`. This alone collapses 3-4 mallocs per escape to 1. Note the perf-dead-ends warning about `reserveCapacity` being *worse* than `+`-chaining does NOT apply — that entry is about String small-string optimisation; Array has no inline storage, so fewer allocations is unambiguous here. If this measures at or near the full estimate, ship it and skip step 2 entirely. Step 2 (only if step 1 leaves something on the table): - DO NOT use `InlineArray`. It is macOS-26-gated and fails to LINK against this package's `.macOS(.v14)` f

### `Sources/TUIkitView/Rendering/ChildInfo.swift:888` — first-frame-and-startup

The child-provider conformance probe is still a dynamic cast that boxes: `content as? ChildViewProvider`, once per container per pass plus once per tuple element per pass.

**Per.** `resolveChildViews` is called from every stack's `sizeThatFits` AND `renderToBuffer` (VStack.swift:95, 295, 453; HStack.swift:256, 300, 379, 509; ZStack, Layout, StackLayoutPlacing, _ToggleCore, Menu — 33 call sites), and the function's own comment records "five resolutions of the same content value in one frame … 26% of a `fanout` frame". Inside it the cast SUCCEEDS for `TupleView` content, which

**Change.** Add `static var _isChildViewProvider: Bool { get }` plus `static func _childViews(_ view: Self, context: RenderContext) -> [ChildView]?` to `View` (default `false` / `nil`), and give them `true` / `view.childViews(context:)` from a constrained extension `extension View where Self: ChildViewProvider` — the identical mechanism `_renderSelf` uses in `Renderable.swift:259` and `_isAnimatable` uses in `AnimatableResolution.swift:39`. `resolveChildViews` then reads the witness and calls through concrete `Self`, so nothing is boxed and nothing is dynamically cast. Do the same for `ChildInfoProvider` 

**Measure.** `ab_bench.py old new --quick` first — `fanout` and `deep` are where the record puts this path (`fanout` because of the child count, `deep` because it resolves the same content once per enclosing level), with `anyview` and `framedcolumns` as the cross-check; then `--cold` on the same set, since a cold pass resolves every container while a warm one s

**Careful.** Split it into two commits and measure them separately — they have very different risk and very different expected sizes. COMMIT 1 (near-zero risk, do this first): add only `static var _isChildViewProvider: Bool` (+ `_isChildInfoProvider`, `_isLazyChildViewProvider`) to `View`, default `false`, `true` from `extension View where Self: ChildViewProvider` etc. Use it as a GATE and keep the existing cast behind it, exactly as `_isSpacer` documents ("When the witness is `true`, the rare spacer is cast to `SpacerProtocol`"). Apply it at TupleViews.swift:132 and :87 (the per-element probes, which FAIL for almost every child) and at ChildViewCollection.swift:139 (`LazyChildViewProvider`, sole conform


### Rejected, with the reason — so they are not proposed again

- **`Sources/TUIkitCore/Extensions/String+TerminalWidth.swift:1304`** — *already-tried*: ## 1. Has it been tried? Yes — this exact idea, on this exact function. `/Users/robot/.claude/projects/-Users-robot-Documents-TUIkit/memory/perf-dead-ends.md`, item 3 under "Do not retry these": > **Call frequency decides, not code shape.** The `ansiSegments` 
- **`Sources/TUIkitCore/Extensions/String+CellSpanDiff.swift:228`** — *already-tried*: Two of the three edits are idioms this project has already built, measured and reverted, and the third rests on a premise the code contradicts. (c) reserveCapacity on the span builder — ALREADY TRIED, as an idiom, and it regressed. `perf-dead-ends.md` (2026-08
- **`Sources/TUIkit/Views/HStack.swift:122`** — *not-hot*: The claimed multiplier is not there: the existing `measureChild` memo already collapses every measure-walk repeat of `resolvedLayout`, and the one call it cannot collapse — the render walk's — is unreachable with the key the candidate proposes. **1. Was it tri
- **`Sources/TUIkitView/Core/PrimitiveTypes+View.swift:49`** — *too-risky*: Screened on all four questions. It fails only the last one, and it fails it clearly. **1. Tried? No.** `git log --oneline -600 -S` and the memory notes show nothing that collapses these pairs. `f7942168` is the nearest relative and is a different change: it ad
- **`Sources/TUIkitView/Rendering/ChildInfo.swift:579`** — *too-risky*: **1. Tried before? No.** `git log --oneline -900`, `git log -S'if context.isMeasuring, tracker.cacheUnsafeCount'` and the Documentation/ records show no `isMeasuring` store gate. The three reverted gates (hit-rate, subtree-cost, `View._memoizesOwnSize`) are di
- **`Sources/TUIkit/Views/Table.swift:686`** — *not-hot*: **1. Tried?** No. `git log --oneline -600`, `git log -S"analyticMultiLineSize"` and the perf ledger turn up only the two commits the analyst already names: df46e252 (created the decline, deliberately) and 062058ed (fixed a measure-side-effect caused by it). No
- **`Sources/TUIkitView/Animation/AnimationStore.swift:410`** — *too-risky*: The multiplier is real (one tuple copy per record per frame, records ≈ one per rendered `.padding`/`.frame`/`.offset`/`.opacity` node) but the per-entry cost is far smaller than the write-up assumes, and the risk is larger. 1. HAS IT BEEN TRIED? Not this exact
- **`Sources/TUIkit/App/RenderLoop.swift:643`** — *not-hot*: 1. HAS IT BEEN TRIED? No. `git log -S"cellPixelAspect"` / `-S"cellPixelSize"` over Sources gives only b19c202c, bff71c86 and d7223187 (all additive), and 176cfc0d/e6c2e814 ("Refactor: Cache FrameBuffer.width, eliminate redundant regex and ioctl calls") folded 
- **`Sources/TUIkitView/Animation/AnimationStore.swift:323`** — *not-hot*: The trigger cannot fire on any measurable surface, and the premise that it "fires every frame on the animating pages" is inverted for the main case. 1. HAS IT BEEN TRIED? No. `git log -S"servedAnyByRuns"` returns only da01c684, and its message shows the flag w
- **`Sources/TUIkit/Rendering/FrameDiffWriter.swift:808`** — *not-hot*: The mechanism is real, but the multiplier is off by two to three orders of magnitude, and the memory it cites says so. 1. HAS IT BEEN TRIED? No. `git log --oneline -600` has no touch to `cellCache(for:)`/`setCellCache` (`git log -- Sources/TUIkit/Rendering/Fra
- **`Sources/TUIkitCore/Extensions/String+CellSpanDiff.swift:303`** — *too-risky*: 1. HAS IT BEEN TRIED? No. `git log --all --oneline | rg -i 'unsafe|bounds'` finds nothing in the render/diff pipeline, and `perf-dead-ends` (the project's revert ledger) has no entry for it. The analyst's history reading of the five §ANSIRowCells commits is ac
- **`Sources/TUIkitCore/Rendering/FrameBuffer.swift:883`** — *not-hot*: The change itself is sound and probably behaviour-preserving, but the multiplier is wrong in both places the analyst claimed it, and no benchmark scenario reaches the code at all — so a measured A/B run would return noise. **1. Has it been tried? No, but the c
- **`Sources/TUIkitCore/Rendering/FrameBuffer+Punching.swift:17`** — *not-hot*: The dedup is behaviour-safe and trivially correct (footprintBands reads only `overlay` and `position`; nothing about `self`), and nothing in `git log --oneline -600` shows it was tried — the only punching commits are the mechanism's introduction, the partial-c
- **`Sources/TUIkitCore/Rendering/OverlayLayer.swift:339`** — *not-hot*: 1) Tried? No. `git log --oneline -600` for shortfall/strippedLength/ansiAwareSlice/cutting turns up only f99d3d02 (animated runs) and edbc362b (the column-0 straddle fix); nothing in Documentation/ records this as attempted-and-reverted. The analyst's history 
- **`Sources/TUIkit/State/AppStorage.swift:192`** — *not-hot*: Q1 — tried? No. `git log --oneline -600` filtered for decoder/encoder/storage/json shows only correctness commits (ce799467 Sendable, a19d6b20 and 7165a2da deadlocks, 7e8874ab backend test, 067d255b failure message). `JSONDecoder`/`AppStorage`/`UserDefaults` a
- **`Sources/Example/Components/RecentValues.swift:24`** — *not-hot*: **Q1 — tried?** No. `git log --oneline -600` has no perf commit touching `RecentValues`, `AppStorage` storage reads, or JSON decoding; the only nearby commits are correctness/Sendable ones (`ce799467`, `7e8874ab`, `a19d6b20`). Nothing in Documentation/ covers 
- **`Sources/TUIkit/Localization/LocalizationService.swift:170`** — *not-hot*: Q1 (tried?): No. §33 of Documentation/Performance-profile-2026-08.md names LocalizationService.string(for:) as an open target; §35 shipped only the scan half of substituting (switch classifiers, commit 114f7fa9) and §33's append half was reverted for position 
- **`Sources/TUIkit/Views/LazyGrids.swift:137`** — *not-hot*: Two independent reasons, either of which sinks it. (1) The redundant work the candidate targets is ALREADY absorbed by a cache the analyst did not notice — the per-pass measure memo in `measureChild`. `LayoutSubview.sizeThatFits(_:)` (Sources/TUIkit/Views/Layo
- **`Tools/Profiling/emit_bench.py:54`** — *not-hot*: The candidate's factual premise is wrong, and the gap it wants to close does not exist. **1. §54 is NOT an emission-path change.** This is the load-bearing error. `String.ansiAwareSlicedRuns(runCount:width:receive:)` has exactly one production caller in the wh