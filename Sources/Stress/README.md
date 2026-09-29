# Stress

A performance **stress harness shaped like an app**. Its primary purpose is to
be a reproducible instrument for profiling and optimising the TUIkit render
pipeline; it is *secondarily* a showcase of deliberately absurd TUIs.

Unlike `Example` (built for humans, to demonstrate features), every
scenario here is built to **push a specific part of the pipeline to its limit**:
deep recursion, wide fan-out, very large data sets, heavy modifier chains,
type-erasure, all-invalidating churn, and so on.

## Why it stays small on disk

There is no bundled data. Every data set is synthesised at launch from a seed
(`Synth.swift`, SplitMix64). The same `(scenario, scale, seed)` always produces
byte-identical content, so:

- a "1,000,000-row" list costs **O(1) memory and zero disk** — rows are hashed
  from their index on demand (`mix(seed, index)`), never stored;
- two profiling runs render exactly the same tree, so before/after comparisons
  are meaningful.

## Running it

```sh
# Interactive (needs a terminal): a menu of scenarios.
swift run Stress

# Headless smoke test: render every scenario once, non-zero exit on empty.
swift run Stress --selfcheck

# Headless benchmark of one scenario (no PTY — see "Profiling" below).
swift run -c release Stress -- --bench --scenario fanout --iterations 2000 --cold
```

### Configuration (environment variable | CLI flag)

| Env | Flag | Meaning |
|---|---|---|
| `TUIKIT_STRESS_SCENARIO` | `--scenario <id>` | boot directly into a scenario |
| `TUIKIT_STRESS_VARIANT` | `--variant <id>` | pick a variant of a matrix scenario (see below) |
| `TUIKIT_STRESS_SCALE` | `--scale <n>` | size multiplier (1 is already heavy; 10/100 are pathological) |
| `TUIKIT_STRESS_SEED` | `--seed <n>` | synthetic-data seed |
| `TUIKIT_STRESS_AUTOPILOT` | `--autopilot` | self-drive continuous re-renders |

`--variants` lists every matrix scenario's variants, grouped by the axis each
one varies. `--bench` also takes `--iterations N`, `--cols C`, `--rows R`, and `--cold`
(fresh state + cache each frame → worst-case measure+render, vs the default
cache-warm steady state). What `--cold` does NOT make afresh is the value hash's
plan table: a plan is a fact about a type, not a memo, so the bench keeps one
table and hands it to every cache it makes, as an app's `TUIContext` keeps one
for its own — a cold frame misses every memo, and is not also the first sight
of every type, which an app pays once.

Interactive keys: `↑/↓` select · `enter` open · `esc` back/quit · `+/−` change
scale live · `a` toggle autopilot.

## Scenarios

| id | Stresses |
|---|---|
| `megalist` | `List`/`ForEach` windowing, row-id resolution, lazy row content, per-row memo |
| `scrollfollow` | bottom-anchored `ScrollView` over variable-height rows with one appended per tick — windowed band render, anchor advance, tail estimate, O(window) at any N |
| `scrolleager` | the eager twin of `scrollfollow`: a vertical `ScrollView` over an eager `VStack` of rows whose text changes every tick — every walk of the content (the enclosing stack's ideal-size ask, scrollbar reservation, the natural-extent ladder, the render) touches every row, so an added walk shows at full size |
| `table` | `Table` column-width computation, row windowing, per-cell value closures |
| `table-multiline` | multi-line cell wrapping, lazy row sizing (visible window + bottom suffix only), variable-height windowing |
| `truncate` | ANSI-aware clipping, all three truncation modes, per-cell measure/pad |
| `table-churn` | per-row re-render of *unchanged* rows — the data is replaced every frame but ~2% of rows differ |
| `table-churn-wrapped` | the same, 250 rows wrapped: below the extent estimator's row limit, where every row is measured |
| `table-tail` | a window over a growing sequence — rows keep their content and change position |
| `table-api` | **a matrix**: one `Table` built every way the API allows, one variant per point (see below) |
| `app-shapes` | **a matrix**: whole applications — file browser, log viewer, process monitor, mail client, settings form, code editor (settled and tailing), chat, a sidebar source list (tagged and untagged) |
| `tables-scroll` | **multiple** `Table`s in a `ScrollView` — N per-table column-width computations, ScrollView windowing over the combined buffer |
| `tables-vstack` | **multiple** `Table`s in a `VStack` (no scroll) — N per-table column-width computations, VStack measure/layout over many table children |
| `deep` | structural `ViewIdentity` chain depth, measure recursion, context propagation |
| `fanout` | non-lazy container measure over **all** children (O(n) layout) |
| `modifiers` | `ModifiedView`/environment-modifier layering, per-node measure overhead |
| `preferences` | preference side-effect declaration, value-memo defeat, per-row re-measure |
| `customlayout` | `Layout` protocol call pattern, repeated subview measurement, `AnyLayout` erasure |
| `textwall` | text width measurement, word wrapping, glyph throughput |
| `anyview` | type-erasure fallback (render-to-measure), lost concrete dispatch |
| `dashboard` | `Panel`/`Card` container measure + flexible-width row sharing (also the showy demo) |
| `framedcolumns` | non-infinity `.frame` measure, frames-in-stacks-in-frames cascade, uncacheable interactive rows |
| `churn` | full re-render per frame, cache invalidation, measure with no memo hits |
| `animating` | animation store lookups, uncacheable subtrees, colour resolution per frame |
| `translucent` | cell decomposition of both sides, per-cell region lookup, SGR re-emission |
| `gradients` | ramp quantisation, per-cell geometry, origin propagation, re-ink on move, SGR runs |
| `alpharamp` | per-cell alpha compositing over a patterned ground, blend arithmetic |
| `menus` | `ButtonStyle` body measure, menu hug-width pass, shortcut hint column, per-row `@Environment` resolution |
| `keyrows` | per-row registrations (`onKeyPress`, `.statusBarItems`) under the row memo, per-frame key and status-bar registries, a `.refreshable` panel |
| `kitchensink` | split-view + list windowing + container grid simultaneously |

## Matrix scenarios and variants

Some questions are not about *a* shape but about a *space of* shapes: how a
`Table` behaves across every way an app can build one. There are dozens of those
points, they differ by a line each, and none of them wants a title a translator
will ever read — so they are **variants** of one registered scenario rather than
scenarios of their own.

```sh
swift run Stress -- --variants                                  # list them
swift run Stress -- --bench --scenario table-api --variant width-fit
```

`--selfcheck` renders every variant of every matrix scenario, not just the one a
config selects, so the whole space is smoke-tested (and, with
`TUIKIT_VERIFY_RENDER_MEMO=1`, memo-verified) on every run.

`app-shapes` is the other kind of matrix: not one API's space but whole
applications, because the costs worth finding live in the COMBINATIONS. A file
browser is a split view over a sortable table of formatter-built cells; a
process monitor re-sorts four hundred rows whose every number moved; a chat is
bottom-anchored bubbles of wildly unequal height. Nothing assembled from single
-purpose fixtures puts those together, and each of them has already priced
something the parts could not — `chat` against `chat-eager` is 1.4 ms against
189 ms for the same application, the only difference being `LazyVStack` where an
app would write `VStack`.

Several variants come in pairs for exactly that reason, and the pair is the
measurement: `chat`/`chat-eager` prices laziness, and `code-editor`/
`code-editor-tailing` prices a SETTLED document against a growing one. The
second of each pair exists because every memo keyed on the rows' data — the row
memo, a `Table`'s `.fit` column, a windowed stack's width over all rows — serves
100% on the settled shape and 0% on the growing one, and a matrix that only ever
measured the settled shape would report the memo's best day as its only day.
`sidebar`/`sidebar-untagged` is a pair along a third axis: one hand-written
"All projects" row above 300 looped ones, which makes the `List` walk its
flattened children eagerly and recover each looped row's selection value from
the `ForEach` that made it. The tagged variant names every row with the app's
own enum, read off the BUILT row; the untagged one answers by each project's
`id`, a key-path read — so the difference between them is the price of a tag.
It is paid for the rows the frame draws and the handler asks about, as a
windowed loop pays it: the values are asked for, not resolved up front, and
the split view's hug measure asks for none (`ListRowSelectionValueCostTests`
counts both).

Three variants are there to price what TUIkit OBSERVES. `outline` is forty
sections of rows in one lazy stack, each row reading an `@Observable` counter
of its own in its body, and `scrollfollow-observable` is `scrollfollow` with
every row reading one of 64 notes. Both are DRIVEN (`DrivenScenario`): a model
the view reads is written between frames — one counter, one note a frame — as
an app's model is, because what a write invalidates is part of what a frame
costs and a tick the view derives its content from invalidates nothing.
`--bench` and `--selfcheck` make the write before each frame (outside the
timed region; its invalidations are paid in the frame); the interactive shell
shows the view at rest. `timeline-rows` is a two-axis lazy stack of 400 rows
each holding a `TimelineView(.animation)`, the shape a live timeline beside a
kept width is priced on.

`table-api` is the first: 43 variants over seven axes — how a column gets its
value (key path, closure, sort-by-one-display-another, non-`Equatable` rows,
class rows), the four width modes, what a cell holds (interpolated integers,
Foundation formatters, SGR, CJK/emoji, over-long text), truncation mode, line
limits and alignment and column spacing, the selection and sort bindings, the
update pattern, and the size/chrome/surroundings. A variant is a struct literal
in `TableAPI*Variants.swift`; adding one costs no registry entry and no
translations.

## Sessions: a UI in use, over time

A scenario is a UI at rest, drawn again and again. A **session** is a UI in
use: an interaction script played against a page step after step — keys typed
into it, rows inserted and moved under it, the terminal resized around it. The
bugs of a UI in use are the ones that need a write, a scroll or a moved row
between two frames, and a screen drawn at rest never has one.

```sh
swift run Stress -- --sessions                                   # list them
swift run -c release Stress -- --session editor --steps 3000 --verify --resize-every 97
swift run -c release Stress -- --bench --scenario session/editor --iterations 2000
```

A session drives the REAL render loop headless (`HeadlessApp`): keys go through
the app's five-layer input chain to the focused control, and a frame is the
loop's own — header, status bar and diff writer included — at an instant the
runner supplies, so two runs of one script draw the same pictures. A hover or a
click arrives at the instant of the frame before it, so a double click's window
and a tooltip's delay count on that clock too, not the machine's. The wheel's
edge grace still reads the machine's clock, and the `notes` session's wheel can
reach it at the top of its list. Its report
prices each KIND of step separately (mean, p50, p95, max, bytes emitted), since
a keystroke and a page-down are different frames, and counts what the render
cache did over the steps: memoized rows composed and served, value-memo hits,
misses and stores, subtree clears and the cached entries they walked. Those
are counts of work, not of time, and the same script does the same work, so
two builds' counts can be compared on a busy machine where their timings
cannot. (Value-memo hits are the exception: they vary by a few in a thousand
between two runs of one build.) The real loop matters: its
first frame runs a measuring walk to size the app header before it draws, which
no direct render does, and that walk was why every app opened a
`defaultScrollAnchor(.bottom)` view at its top — found by the `chat` session,
invisible to every test that rendered the view directly.

`--verify` is the oracle, and it needs no expected pictures: a second instance
plays the same script with its render cache emptied before every frame, and
every frame must match. A cache is right exactly when a frame drawn through it
is the frame drawn without it, so any difference is a memo, a kept width or an
invalidation serving something stale — the class of bug that static renders
cannot see. `--selfcheck` plays every session a short way this way, the
terminal resized under it, so CI does too.

The oracle was checked the way a test is: with the kept all-rows width's
challenge disabled (the fix of `65d3015f`), `--session editor --steps 1500
--verify` reports 75 of 1,500 frames different from the twin's, the first at
step 1,106 — the stale width scrolls the rows to a different slice. Note
where: a hundred and fifty steps would not have reached it. The selfcheck is a
smoke test; a change to a memo or a kept value deserves a few thousand
verified steps of the sessions it touches.

The oracle has a blind spot: it cannot see a mistake that both instances
make. A scroll view opening at the wrong end is drawn the same with a render
cache and without one, and `log` opened at its top on every run, verified
clean. So each session can also say what its page must SHOW
(`StressSession.check(_:after:)`), judged from the model the session drives
rather than from another rendering. `chat` and `log` check that, while the
conversation or log is being followed, its newest message or line is on the
screen; `editor` that the caret's line is on the screen once the caret has
moved; and every session with a count or a status line that it says what the
model says. The checks run on every frame of a `--session` run and of the
selfcheck, outside the timed region, and are off for `--bench`. Their first
runs found three bugs that had passed thousands of verified steps: a
bottom-anchored lazy stack of unequal rows opened on blank lines, a log lost
its end on a burst of wrapping lines, and a view following its end let go of
it when the terminal shrank.

Some of what a frame must show is in how it is PAINTED, not in its text: which
row of an open menu is highlighted, whether a label keeps its contrast. A
session says that in `check(styled:after:)`, which is handed the frame as the
diff writer built it; `ScreenCells` takes it apart into cells, each with the
ink and field the SGR in force there paints (reverse video swapped out), and
records the richest colour spelling the frame used. The `menus` session reads
its highlight that way — the row it walked to painted apart from the others —
and its first run found a check of its own that matched "Reopen #5" on the row
"Reopen #52", which is why its rows are found by whole labels.

A check that finds a bug before the fix lands tags its problem with a known
issue's name, `"[name] …"`, and the session lists the name in `knownIssues`
with what it is. The runner reports those frames apart, as
`known issue [name] on N frames`, and fails nothing on them, so a session can
land ahead of the fix of what it found — a test's `withKnownIssue`, for a
session. The fix takes the entry out.

Under `TUIKIT_VERIFY_RENDER_MEMO=1` a session run also reports what the
render-memo verifier found — every served buffer re-rendered and compared, and
the registrations it replays with the ones a fresh render makes — and fails on
any, naming the steps. The twin compares whole frames; the verifier compares
each serve, including those no frame shows (a navigation stack's covered root,
the focus-reach probe's rows). `TUIKIT_VERIFY_MEASURE_MEMO=1` does the same for
sizes — every size served by either measure memo, the per-pass one and the
cross-frame one, re-measured and compared — and a run fails on any of those
too.

`--bench --scenario session/<id>` plays one step per iteration and prints the
lines `ab_bench.py` reads, so a session is A/B'd exactly as a scenario is.

Writing one, `--trace` prints each step as it is played — its action, keys and
mouse events (button, phase and cell), what its frame cost and how many bytes
it wrote — `--show` the last frame with its styling stripped, which is how you
find out that the keys you meant for the list went into the search field that
held the focus, and `--show-steps A-B` the frame after each step from A to B,
which is how you find out why a check failed at step 150. When a frame
differs from the twin's only in how it is painted, the report names the first
cell that differs and both paints. The trace is also
where a cost that follows no action shows itself: every `chat` frame cost 6 ms,
quiet ones included, until the conversation passed 256 messages and the stack
took its windowed path — the rows out of sight had been losing their measure
memos at the end of every frame.

| id | Exercises |
|---|---|
| `editor` | an index-keyed code editor in a two-axis scroll view: a row's width moving under an unchanged collection, the kept all-rows width, `scrollTo` following the caret, per-keystroke frames |
| `inbox` | a searchable, selectable `List` of items that arrive, leave, move and change underneath: keyed rows around the selection, the row memo, `List` windowing, a search narrowing and restoring the collection, search suggestions that come and go as the query is typed, focus between a field and a list |
| `log` | a numbered log viewer following its end while lines arrive in bursts, and a reader paging back: a bottom-anchored lazy stack growing under the viewport, wrapped lines of unequal height, `scrollPosition(id:)` reporting the top line |
| `settings` | a settings `Form` worked through with the keyboard while accounts sync in and out: focus traversal, toggles, a picker, a stepper, a disclosure group opening and closing, every row re-shown when the units change |
| `chat` | a conversation of bubbles arriving at the end, earlier ones edited, the person typing and sending: a bottom-anchored lazy stack of unequal heights under the 256-row window threshold, a row's HEIGHT changing under an unchanged collection, full-width alignment frames, a text field typed into and submitted |
| `notes` | notes opened, written in and closed, a sheet to write one, an alert to delete one, two tabs: navigation push and pop by keyboard and by path, a covered root drawn every frame, a `TextEditor` typed into, a sheet and an alert over the page, a tab switched with a mouse click found on the screen, the wheel over a list, rows changing underneath |
| `playlist` | a playlist rearranged with the keys and the mouse, tracks deleted, added and renamed: `onMove` by the Control/Option chords, by move mode (pick up with Ctrl-R, carry, place or cancel) and by a mouse drag with live feedback, `onDelete`; its check reads the order off the screen and requires a run of the model's |
| `jobs` | a queue of jobs whose spinners turn while their rows stay unchanged: memoized `List` rows holding spinners at six speeds, their frames moving under an unchanged value for many frames — the shape in which a cache serving a row as stored would draw an old frame, which the cache-cleared twin sees at once; progress writes, jobs finishing, failing, retried and arriving; walking and paging |
| `processes` | a sortable, filterable process `Table` whose numbers move on every step: `.fit` columns and the row memo under continuous churn, re-sorting, a filter narrowing the rows, rows appended and removed, selection moved with the keys |
| `residual` | rows that draw what is not their element, three ways on one page: index-keyed lines read from `document.lines[i]`, retyped in place, inserted above and removed; a row computing `selection == item.id` in the `ForEach` closure; a parent `@State` driving `.disabled`, `.bold` and `.help` into rows. Above them a band of the shapes the reviews of Option C named: rows holding a `Binding` (with a hand-written `==` that leaves it out), an existential, a token memo inside an `HStack`; rows reading an object the page injects and swaps; `Button`s that are whole rows; a `List` whose selection is bound through `@Bindable` and whose rows carry the page's badge; a two-axis stack whose widest row, far off the window, reads a counter of its own; rows whose `ViewThatFits` measures, without drawing, a candidate that reads a counter; and tasks under a custom `Equatable` `ButtonStyle` whose `makeBody` reads a model. Each is right today only because the write that changes it clears everything below the page, so this is the oracle for any change to what survives an ancestor's write (Option C). The rows say they are `Equatable`, which is what C asks of a row before it re-checks it rather than drawing it again. Checked against a throwaway C-shaped memo, 400 steps a shape (see the commit that added the band): re-checking the rebuilt value and the environment, refusing rows that hold a `Binding` or an existential and token memos, and observing measured and style bodies, it matches the twin on every shape while serving 56.8 rows a step, where today's page serves 10.0 over 400 steps (3,992 rows), or 9.8 with a resize every 97 (3,923); each part of that switched off fails the shape it guards |
| `residual-opaque` | the same page with rows that are not `Equatable`: what C must refuse and draw again as today. Under the throwaway C-shaped memo it matches the twin and serves what today serves, and under each part of it switched off but one: with a token memo's `==` leaked it fails 355 frames of 400, as `residual` does, because a token memo inside a row is served by its token whether or not the row around it is re-checked. So C must keep token memos dropped below a parent's write, not only refuse them as rows |
| `inbox-tinted` | `inbox`'s script and data under a `.tint` that flips every 23 steps: an environment write above every row, which C compares and draws the rows again for |
| `inbox-pushed` | the inbox pushed onto a `NavigationStack`: every row drawn under the pushed screen's dismiss action. It does not type into the search field (the pushed screen's crumb bar joins the Tab cycle); its search steps are quiet, as many as `inbox`'s and making the same draws, so every other step is `inbox`'s |
| `inbox-sheet` | the inbox presented in a sheet: every row drawn under the sheet's dismiss action |
| `inbox-observable` | the inbox with its selection bound through `@Bindable`, as an app binds an `@Observable`'s property |
| `log-observable` | `log` with `.scrollPosition(id:)` bound through `@Bindable` |
| `log-captures` | `log` whose rows carry a tap handler capturing the parent's growing list through `self`: today one copy of the list is alive at a time; a memo that serves rows keeps each drawn row's handler, and the list it captured when drawn |
| `image-rows` | a `List` of rows each holding a decoded 64×32 picture (8 KB of pixels) that arrive, leave and are replaced: the resident size of what a memo keeps of a row's VALUE |
| `accumulate` | a clock moving every step over four readers of an `@Observable` property nothing writes until the end — a drawn body, a body only measured (`ViewThatFits`' unchosen candidate), a custom `ButtonStyle`'s `makeBody` and a `@Bindable`-bound `Toggle`. Every body evaluated under observation arms a registration on what it read, freed when that is written, when the model it read is deinitialized, or when the observation lease it was armed under retires — once nothing the render cache keeps depends on it — so what is alive stays flat however long the run; under `TUIKIT_OBSERVATION_RETIREMENT=never`, the cache as it was before leases, a reader drawn every frame of a property nobody writes adds one a frame for as long as the model lives. Reports resident size every 9,000 steps (a quarter of an hour at 10 Hz) and, at the end, how long the first write took: every registration still armed runs inside it. Play it without `--verify` for its numbers — the twin's registrations are in the same process |
| `menus` | a document manager run from its menus: pop-up `Menu`s in the four corners (File top-left, View top-right, Export bottom-left, Help bottom-right), a `Picker(.menu)` status filter, a `.contextMenu` on every document, an inline `Menu` beside the list and a `TextField` whose `.textInputSuggestions` offer tags. Each is opened by the keyboard (Return, Shift+F10 on a document, Down in the field), by a click that leaves it up, and by a press dragged onto a row; walked with the arrows and End, chosen from with Return or a click, dismissed with Escape or a click elsewhere — while documents arrive, leave, are renamed and promoted under an open menu, the File menu's own recent items change while it is up, and the terminal is made short and narrow around it (six sizes, 36 to 120 wide, 12 to 40 tall). The page's `@FocusState` is on its status line, so the checks can say, from the model and the session's own moves: the open menu's box is whole inside the content and draws every row or a way to reach the rest; the row the session walked to is the one painted apart (read from the styled frame), or none after a pointer opened a pop-up menu; every command chosen ran exactly once, and was the one chosen (`MenuDesk.last`, not only a count, which a click that runs the row beside it would pass), and the filter holds the option chosen; no label of a closed menu is left on the screen; and the focus is back where it was once the frame after a close has settled — TUIkit hands it back at the end of the pass that closes the menu, so the page reads it one frame late. Type-select is not played: TUIkit's menus have none. Its first runs found that a click under an app header landed that many rows lower in `HeadlessApp` and opened a menu as the keyboard does; that the first line of a wrapped menu item answered no click; that Tab left the focus on a document the list did not scroll into view, a context menu's focus stop publishing no id for the scroll view to find; and that an open menu whose anchor scrolls out of its scroll view went from the screen but stayed open, holding the keyboard and coming back with its row. Now an eager stack's menu stays on the screen, pinned at the edge, and a lazy stack's closes with its undrawn row and hands the focus back — which the session expects when the row's number is gone from the list, and holds the menu to never coming back |
| `themes` | a task list beside a form, a table, a tinted band and a translucent line, used — rows walked and selected, the form tabbed through, typed into, toggled and saved — while its look changes: the app's palette cycled with `t` through all seventeen TUIkit ships (Green … Solid Colors, and the one that follows the terminal), light and dark among them; the form put on a palette of the session's own (`HarbourPalette`, light, on its own page); the table in any shipped palette; the colour depth pinned to truecolour, 256 and 16 colours (`StressSession.colorDepth`, around the whole step); a tint flipped over a band of controls; quiet steps while the focused rows breathe. Its checks read the painted frame (`ThemesChecks.swift`): no colour spelled for another depth (24 bits at 256 colours, an index TUIkit computed at truecolour); the page in the app's palette's background; no role colour of a palette the look has just left that no blend of the roles in use could make (truecolour only: the cube lands blends on other palettes' entries); the list showing its cursor exactly while it holds the focus; and a table of `ContrastPromise`s, the floors TUIkit promises today — the cursor row on the accent's breath and on the wash's at `rowBreathPeakContrastFloor`, a selected row on its tint 3.0 and a plain one 4.5 (the audit's pairs, shipped palettes only), an enabled button's label at `labelContrastFloor` and a disabled one's at `disabledLabelContrastFloor` through the cube — each at the depths it is promised at. A row's kind is read from the fill it is drawn on, not from a cursor the session walks. Add a promise to the table to hold every frame to it. It found that `.palette(_:)` turned the value memos off below it for good whenever the palette was not `Equatable` — a custom one as the Theming guide writes it, or the Terminal palette once the environment has grounded it: 300 steps with the whole page under `.palette(_:)` of the palette it already had gave 668 value-memo hits and 1,780 rows served, against 1,891 and 2,700 without, until the modifier compared a palette as `ComparablePalette` does (today's script: 1,939 and 2,782, with the wrap or without). Every check was perturbed and bites. Its first runs found no fault in TUIkit's colours; they found that a row an input handler draws is spelled at whatever depth the handler runs at, so a session pinning its depth must pin the input too, and that `.palette(_:)` on a subtree changes what it draws with and not what is behind it — as a colour scheme does in SwiftUI — so a subtree in a light palette over a dark page must paint its own |

Adding one: a `StressSession` — a page built once over a model the session
owns, a `step(_:)` that makes that step's data changes on the model and
returns the input to deliver, and, wherever the page shows something the model
decides, a `check(_:after:)` that says what must be on the screen — plus a
`SessionDescriptor` in `Sessions.all`. Give the rows something the check can
find: a message number, a line number. Make a row view `Equatable`, every
field compared, unless the session is about rows that are not: that is what
Option C asks of a row before it re-checks it after a write above it, rather
than drawing it again, so a session of rows that are not `Equatable` would
tell a change to C nothing. The rows of `editor`, `inbox`, `log`, `chat`,
`notes`, `playlist` and `residual` say they are; `residual-opaque`'s do not,
on purpose. Nothing reads the conformance today: a `ForEach` row is
memoized by its element, not by its view. A session that clicks or wheels over
something where it is DRAWN says `looksBeforeEachStep` and is shown the screen
before each step (`look(at:)`), so both instances of a verified run aim at the
same cell.
Choices come from a `SessionRandom` seeded from the config, so the twin makes
the same ones.

A session whose cost is what builds up over a long run says
`checkpointEvery`, and the runner prints the process's resident size and
footprint at every multiple of it. `finish()` is what the session does once its
last step is played — `accumulate` writes its property for the first time and
times the write — and the runner then draws one more frame on both instances
and compares it like any other.

`--census` counts the observation registrations the warm instance arms, the
ones that fire, the ones cancelled and the ones dropped, by kind of reader
(`ObservationCensus`: a body drawn or measured, a style's body, a control's
`Binding`). A registration lives until a property it read is written, when it
fires; until the observation lease it was armed under retires, when it is
cancelled (`ObservationLeases`); or until every object it read from is
deinitialized, when it is dropped without running anything. One armed and
none of those is alive, holding its closure and what that captured; one armed
before the cache knew its view type reads is `unleased`, and no lease can
cancel it. The report gives each kind's registrations armed over the steps
and per step, fired, cancelled, dropped, and alive at the end (and after the
finish), then one line of per-step counts — registrations armed, fired and
cancelled; the leases' computations opened, leases made, kept results used
and scopes that read a sentinel; and the view types known to read — and each
checkpoint adds what is alive. `--bench --scenario <id> --census` prints the
same line per frame for a scenario. `TUIKIT_OBSERVATION_RETIREMENT` picks the
rule a process's caches cancel by — `leases`, the default; `never`, the cache
before leases, for a baseline in the same build; or the naive `perReader` and
`perReaderAndPrune`, which the tests keep as negative controls.
`accumulate --steps 36000 --census` is the long run that prices a change to
what TUIkit observes.

## Profiling

The `--bench` mode is a counted `renderToBuffer` loop with **no PTY and no
debugger attach**, so — like `Tools/Profiling/RenderHarness` — it can be
profiled by having Instruments *launch* it (works in sandboxes/CI/VMs where
`--attach` is denied):

Each iteration runs the live loop's per-pass lifecycle around the render —
`StateStorage`/`RenderCache.beginRenderPass()` before, `endRenderPass()` /
`removeInactive()` after — and the identity tree is rooted at a type, as
`RenderLoop` roots an app. Both matter: without the lifecycle the cache was
never pruned and the per-pass measure memo never emptied, so an off-screen
row's size was a hit here and a miss in the app, and a memo that grew by
every miss forever put dictionary resizes into profiles of code that has
none; with a raw-string root, every identity's ancestor test rendered path
strings, and the end-of-pass prune was 88–95% of a frame that the app does
not pay. `cpu-per-frame` numbers from before 2026-09-05 were taken without
either and are not comparable.

`--bench` also reports **`rss-peak`, `rss-mean` and `rss-sampled-peak`** —
`ru_maxrss` for the high-water mark, plus the resident size sampled every 64th
frame so a peak reached once is distinguishable from one held all run. Sampling
sits outside the timed region, so the CPU and wall figures still measure exactly
the render. This exists because a render cache buys CPU by keeping buffers, and
until it did, nothing priced that side of the trade: `ab_bench.py` now prints
the peak beside the timing verdict.

And one line of **counts**, per frame over the timed loop: the per-pass measure
memo's lookups, hits, misses and stores, and the child-views memo's lookups and
hits (`memos/frame:`). The totals line above it includes the warm-up; this one
does not, and it sums every frame of a `--cold` run where the totals see only
the last frame's cache. They are deterministic — the same build and scenario
give the same numbers on any machine, loaded or not — so a change to how the
memos key a view is judged on them first: it must serve as often or more before
its cost is worth timing on a quiet box. (`churn` is the exception: its hits
move by about ±1.5% from run to run, the extra ones all on a `Text` rebuilt
within a pass whose string buffer the allocator happened to hand back at the
old address — the memos key a value by its bytes, an address among them.)
`unkeyed` counts the measures and resolutions whose view the value hash
cannot read (a payload enum that has not opted in, say, or a value nested too deep for the stack to hash — which
cuts no tree short, so the stack guard's count of descents stopped leaves
it out): measured or resolved every time, neither looked up nor kept. Build with `-Xswiftc -DTUIKIT_VALUE_HASH_CENSUS` (a scratch path of its
own saves rebuilding the ordinary one) and `--bench` also prints the value
hash's census: lookups by the shape of the plan that answered them — dense,
runs, steps, bypass — and the types behind all but the first. A lookup that
bypasses through a step names what stopped it inside: an optional's payload
or an existential's content that bypasses, by its own type, or a value too
deep for the stack. A last list names the existentials opened by a cast —
a static type the table has no opener for, whose payload is found by boxing it
in an `Any` — which is what a `ValueHashOpener` would make cheap. In a
`--cold` run the census covers every frame, since the table outlives the
caches.

```sh
swift build -c release --product Stress -Xswiftc -g
BIN="$(swift build -c release --product Stress --show-bin-path)/Stress"
xcrun xctrace record --template 'Time Profiler' --output stress.trace \
    --launch -- "$BIN" --bench --scenario megalist --iterations 5000 --cold
python3 Tools/Profiling/analyze_timeprofile.py stress.trace
```

Always profile a **release** build; debug Swift is an order of magnitude slower
and the relative hot-spots shift.

### How this relates to the other harnesses

- **`Tools/Profiling/RenderHarness`** — tiny, AnyView-free trees for *micro*
  profiling a single shape with maximum signal. Add a tree there when you want
  to isolate one view's dispatch.
- **`Benchmarks/TUIkitBenchmarks`** (ordo-one) — statistical benchmarks with
  warmup/baselines for regression tracking.
- **`Stress`** (this) — large, realistic, *app-shaped* worst cases for
  finding where the pipeline falls over at scale. Start here to discover a
  bottleneck; reproduce it minimally in `RenderHarness`; lock it in
  `TUIkitBenchmarks`.

## Adding a scenario

1. Add `Sources/Stress/Scenarios/Foo.swift` with a `FooScenario.descriptor`
   (`Scenario` value) and a private `View`.
2. Append `FooScenario.descriptor` to `Scenarios.all` in `Scenario.swift`.
3. Prefer **on-demand** synthesis (`mix(seed, index)` per visible row) over a
   pre-materialised array, so memory stays O(visible). If you must materialise
   (e.g. `Table`), build it once in the view's `init`, not in `body`.

Adding a **variant** to an existing matrix scenario is smaller: append a
`variant(_:axis:_:_:)` literal to the relevant group in that scenario's
`*Variants.swift`. It is listed, benchable and self-checked from there, with no
registry entry and no strings to translate.
