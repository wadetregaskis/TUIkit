# List and Table Components

Build scrollable, navigable data collections with keyboard support.

## Overview

TUIkit provides two components for displaying collections of data:

- **List**: A vertical collection of arbitrary view content with selection support
- **Table**: A columnar data display with headers and configurable column widths

Both components share the same keyboard navigation and selection infrastructure, providing a consistent user experience.

## List

`List` displays a vertical collection of items inside a bordered container. It supports:
- Optional title in the border
- Optional footer section
- Single or multi-selection
- Keyboard navigation
- Automatic scrolling with viewport management

### Basic Usage

```swift
struct ContentView: View {
    @State var selectedID: String?
    
    let items = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]
    
    var body: some View {
        List("Fruits", selection: $selectedID) {
            ForEach(items, id: \.self) { item in
                Text(item)
            }
        }
    }
}
```

### With Footer

Add action buttons or status text in a footer section:

```swift
List("Tasks", selection: $selectedTask) {
    ForEach(tasks) { task in
        Text(task.title)
    }
} footer: {
    ButtonRow {
        Button("Add") { addTask() }
        Button("Remove") { removeTask() }
    }
}
```

### Multi-Selection

Use a `Set` binding for multi-selection mode:

```swift
@State var selectedIDs: Set<String> = []

List("Files", selection: $selectedIDs) {
    ForEach(files) { file in
        HStack {
            Text(file.icon)
            Text(file.name)
        }
    }
}
```

### Visual States

A row says two things at once, and they are separate questions. The
**background** says where the cursor is; the **mark** in the row's leading
gutter says what is selected. `List` and `Table` answer both identically —
they reserve a gutter of the same purpose, and since 2026-08-24 both draw in
it.

| State | Background | Gutter |
|-------|------------|--------|
| Focused + Selected | Pulsing accent | `●` in the accent |
| Focused only (the cursor row) | Pulsing focus wash | blank |
| Selected, not the cursor row | Subtle accent, still | `●`, dimmed |
| Neither | Default | blank |

So a control with no selection draws no mark on any row: being under the
cursor is not being chosen. The subtle accent is what says "selected" where the
mark is hidden (`.rowSelectionIndicator(.hidden)`) — a `Table` drew no fill
there until 2026-09-29, so its selected rows away from the cursor showed nothing. `.unfocusedSelectionVisibility(.hidden)`
collapses the third row of that table into the fourth — background and mark
together — for a transient list where an ambient highlight is more noise
than signal.

The cursor row of a control that has the keys breathes, selected or
not: motion is what says where the keys go, on a list as on every other
focused control. Selected, it breathes the accent; not selected, the neutral
focus wash (``Palette/focusWashPulse()``). At truecolour and 256 colours the
fills are chosen together, so each state stays distinguishable from the
others: each breath's dim end sits a little above what it extends — the page,
or the selected-row tint — and a selected cursor row peaks brighter than
either an unselected one or a selected row. The shipped palettes' fills were
chosen at coding time; every other palette's — a custom one, the terminal's
own colours, a `.tint` subtree — come from a rule that places them the same
way. A `focusBackground` a palette states is drawn as stated: at truecolour
the unselected cursor row breathes up from it to twice its distance from the
page, and on 256 colours its entries are kept wherever the selected rows
still stand apart from it. On 16 colours the fills are slots of the table the
terminal reports, and where sixteen are too few to keep the states apart, one end
of a cursor row's breath is reverse video: the whole row the text's colour, and
everything on it the page's. The ● is
what tells the two apart: most palettes' wash shares the accent's hue. A control drawn with `.rowSelectionIndicator(.hidden)` has no ●,
and its cursor row breathes all the same, selected or not: the focus indicator
always visibly breathes. A control that does not have the keys draws no
breath: unfocused, it has no cursor row; focused in a window that has lost the
terminal's focus, its cursor row holds still — the subtle accent on a selected
row, the plain wash on one that is not (see <doc:FocusSystem>).

A control that can never draw a mark does not keep the cells for one.
`Table(_:columns:)` (no selection binding) and `.rowSelectionIndicator(.hidden)`
both give the two cells back, so their rows and header start one cell inside
the border like any other bordered content. Only the structural conditions
count: which row is selected, and whether an unfocused selection is shown,
change while the app runs, and a column that appeared when you clicked would
shift every value in the table sideways. `List` reserves nothing to give
back — it draws its mark in the single pad cell its rows already had.

How the pulse animates is a separate setting again:
`.selectionIndicatorStyle(.none | .blink | .pulse)`, and its speed is
`.indicatorAnimationSpeed(_:for: .focusEmphasis)`. Both govern the emphasis, not
which cells carry it.

## Table

`Table` displays tabular data with column headers, alignment, and configurable widths.

### Basic Usage

```swift
struct FileInfo: Identifiable {
    let id: String
    let name: String
    let size: String
    let modified: String
}

struct ContentView: View {
    @State var selectedFile: String?
    let files: [FileInfo] = [...]
    
    var body: some View {
        Table(files, selection: $selectedFile) {
            TableColumn("Name", value: \.name)
            TableColumn("Size", value: \.size)
                .width(.fixed(10))
                .alignment(.trailing)
            TableColumn("Modified", value: \.modified)
        }
    }
}
```

### Column Configuration

Columns support four width modes:

```swift
TableColumn("Name", value: \.name)
    .width(.flexible)        // Shares remaining space (default)

TableColumn("Size", value: \.size)
    .width(.fixed(12))       // Exactly 12 characters

TableColumn("Progress", value: \.progress)
    .width(.ratio(0.3))      // 30% of available width

TableColumn("Title", value: \.title)
    .width(.fit)             // Sizes to the widest header/cell (O(rows))
```

`.fit` scans every value in the column (not just the visible rows) so the
width stays stable while scrolling; prefer `.fixed` or `.flexible` for very
large tables where a per-frame content scan is undesirable.

### Column Alignment

Align column content to leading, center, or trailing:

```swift
TableColumn("Amount", value: \.amount)
    .alignment(.trailing)    // Right-align numbers
```

### Multi-Line Cells and Truncation

By default each cell occupies a single line (the classic table look). Raise a
column's line limit with `.lineLimit(_:)` to let wide values — or values
containing explicit line breaks — wrap onto further lines; the row grows to its
tallest cell, and content beyond the limit is folded into the last line and
truncated with an ellipsis:

```swift
TableColumn("Notes", value: \.notes)
    .lineLimit(3)            // Wrap up to 3 lines per cell
```

Cells are always clipped to the column width so the table stays aligned.
`.truncationMode(_:)` chooses *which* part of an over-long value survives —
for example `.head` keeps the end of a long file path:

```swift
TableColumn("Path", value: \.path)
    .truncationMode(.head)   // Keep the end, drop the start
```

### Scroll Granularity

When rows span multiple lines, ``ScrollGranularity`` controls how finely the
content scrolls. The default is `.line`: tall rows scroll into view gradually
and may rest partially clipped at the top edge. Opt into `.row` for the classic
TUI behaviour, where a scroll step lands with the top row fully visible:

```swift
List("Notes", selection: $selected) { ... }
    .scrollGranularity(.row)
```

Granularity sizes a *step*; it is not a promise about the bottom edge. Under
both modes the row that straddles it is drawn as far as it fits, so the
viewport is always exactly filled and a fixed-height list never looks as though
it truncated its own visible area.

Multi-line rows also have a *height*, and a scrollbar metered in lines needs
the total. Measuring every row to find it means wrapping the text of rows
nobody can see, on every frame — so by default they are sampled instead
(``ScrollExtentPrecision/approximate``). The visible rows are always exact,
and both ends of the travel are pinned: an unscrolled view puts the thumb at
the top of its track, and the furthest scroll puts it flush at the bottom.
Only the middle can drift, and only when rows differ wildly in height. Where
a proportionally exact thumb matters more than the cost, opt in:

```swift
Table(logEntries) { ... }
    .scrollExtentPrecision(.exact)
```

Single-line rows are unaffected — there a line *is* a row, so the extent is
already exact at no cost.

## Keyboard Navigation

Both List and Table support the same keyboard shortcuts:

| Key | Action |
|-----|--------|
| Up | Move focus up (wraps to end) |
| Down | Move focus down (wraps to start) |
| Home | Jump to first item |
| End | Jump to last item |
| Page Up | Move up by viewport height |
| Page Down | Move down by viewport height |
| Space | Toggle selection |
| Enter | Activate the row (primary action) when one is set, otherwise toggle selection |

Hold Shift with Up/Down to move the cursor by several rows at once (clamping at
the ends rather than wrapping). The step count is the `.shiftStepMultiplier(_:)`
environment value (default 5).

With a `Set` selection binding, the macOS multi-selection keyboard model is
also available: **Shift+Up/Down** extends an anchored selection span
(clamping at the ends, like macOS), <kbd>Ctrl</kbd>+<kbd>V</kbd> toggles a sticky extend mode in
which plain Up/Down keep extending (Shift then reapplies the accelerated
step), **Ctrl+A** selects all, and **Escape** acts one stage per press —
exit extend mode, then clear the selection — falling through to page
navigation when there is neither to do.

## Scroll Indicators

When content extends beyond the viewport, scroll indicators appear at the
top and bottom, reporting the number of rows hidden in each direction:

```
┌─ My List ────────────────────┐
│        ▲ 4 more above        │
│ Item 5                       │
│ Item 6                       │
│ Item 7                       │
│        ▼ 12 more below       │
└──────────────────────────────┘
```

Instead of the text indicators, List and Table can draw an interactive
scrollbar (hidden by default). When the bar is visible it replaces the
"N more" lines — the bar marks the off-screen rows itself, so the rows
fill the full content area with no reserved indicator line. Opt in and
customize it with the shared scrollbar modifiers, which also apply to
ScrollView:

```swift
List("Items", selection: $selected) { ... }
    .scrollIndicators(.visible)      // .automatic / .visible / .hidden / .never
    .scrollbarArrows(.single)        // .none / .single / .double
```

The scrollbar supports a proportional thumb, drag, click-to-page or
click-to-jump, end-arrow stepping, and auto-repeat while a button is held.

## Sections

Use ``Section`` to group list items with headers and optional footers:

```swift
List("Settings", selection: $selected) {
    Section("General") {
        ForEach(generalItems) { item in
            Text(item.name)
        }
    }
    Section("Advanced") {
        ForEach(advancedItems) { item in
            Text(item.name)
        }
    }
}
```

Section headers are rendered with secondary foreground color and bold styling above the group.

## Badges

Add badges to list rows using the `.badge(_:)` modifier:

```swift
List("Inbox", selection: $selected) {
    ForEach(mailboxes) { mailbox in
        Text(mailbox.name)
            .badge(mailbox.unreadCount)
    }
}
```

Badges appear right-aligned in the row and support both integer and string values.

## List Modifiers

Lists support several TUI-specific modifiers:

```swift
List("Items", selection: $selected) {
    ForEach(items) { item in
        Text(item.name)
    }
}
.focusID("my-list")                    // Explicit focus identifier
.listEmptyPlaceholder("Nothing here")  // Custom empty state text
.listFooterSeparator(false)            // Hide footer separator
.disabled(isLoading)                   // Disable interaction
```

| Modifier | Description |
|----------|-------------|
| `.focusID(_:)` | Sets a stable, explicit focus identifier |
| `.listEmptyPlaceholder(_:)` | Text shown when the list has no items (default: "No items") |
| `.listFooterSeparator(_:)` | Controls the separator line before the footer |
| `.disabled(_:)` | Prevents keyboard interaction |

## Environment Propagation

Modifiers applied to List or Table propagate to their content:

```swift
List("Items", selection: $selected) {
    ForEach(items) { item in
        Text(item.name)  // Inherits red foreground
    }
}
.foregroundStyle(.red)
```

## See Also

- ``List``
- ``Table``
- ``TableColumn``
- ``ColumnWidth``
- ``TruncationMode``
- ``Section``
- ``ForEach``
- ``SelectionMode``
- <doc:FocusSystem>

## Reordering from the Keyboard

A list or table that takes `onMove` can be reordered without a mouse.
<kbd>Ctrl</kbd>+<kbd>R</kbd> picks the focused row up; from there the movement
keys — arrows, <kbd>Home</kbd>/<kbd>End</kbd>, <kbd>Page Up</kbd>/<kbd>Down</kbd>
— move its landing slot, <kbd>Return</kbd> places it and <kbd>Escape</kbd> puts
it back. Nothing else changes meaning, and a key the mode does not claim keeps
its own.

That is a mode rather than the modifier+arrow chord every editor uses, because
Apple Terminal strips modifiers from <kbd>↑</kbd>/<kbd>↓</kbd> entirely — a
`⌥↑` binding is not merely unbound there, it is undeliverable. The mode needs no
modifiers at all, so it works in every terminal, and a long move costs three
keys rather than two hundred: pick up, <kbd>End</kbd>, <kbd>Return</kbd>.

What the move *shows* is ``RowReorderFeedback``, as with a drag — except that
``RowReorderFeedback/cursor`` has no cursor to ride, so a keyboard move shows
``RowReorderFeedback/dimmed`` instead: the same faint copy of the row in the slot
it would land in, rather than an empty gap and a row that is nowhere.

There are accelerators for the common cases, too, with no mode to enter or
leave: <kbd>Ctrl</kbd>/<kbd>Option</kbd>+<kbd>↑</kbd>/<kbd>↓</kbd> move the
focused row one place, <kbd>Option</kbd>+<kbd>Home</kbd>/<kbd>End</kbd> send it
to an end, <kbd>Option</kbd>+<kbd>PageUp</kbd>/<kbd>PageDown</kbd> move it a
screenful, and holding <kbd>Shift</kbd> with any of them applies the
`shiftStepMultiplier` coarse step.

Two chords for the nudge because neither works everywhere. macOS binds
<kbd>Ctrl</kbd>+<kbd>↑</kbd>/<kbd>↓</kbd> to Mission Control system-wide, so on
a stock Mac they never reach the terminal at all — but they are the natural
binding on Linux, where nothing intercepts them. <kbd>Option</kbd> is what macOS
leaves alone; Apple Terminal needs "Use Option as Meta key", and even then
strips modifiers from <kbd>↑</kbd>/<kbd>↓</kbd> specifically, which is why
``RowAction/pickUpRow`` — which needs no modifier at all — remains the route
that always works.

While a row is being dragged with the MOUSE, the movement keys scroll the
viewport instead of moving the cursor — that is how you reach a destination
that is off screen without letting go. They leave the cursor and the selection
where they are, because the next pointer movement would snap the cursor back to
the row under the pointer anyway.

Holding <kbd>Shift</kbd> with any of the movement keys moves the row by the
`shiftStepMultiplier` coarse step, the same as it does for the cursor.

A move started from the keyboard always previews with a slot — the row shown
faint where it would land — whatever ``RowReorderFeedback`` the view asked for.
A mouse drag needs no indication that it is happening; the pointer is one.
<kbd>Ctrl</kbd>+<kbd>R</kbd> puts the control into a state that is otherwise
invisible, and `.live` — which only shuffles the data — would show nothing at
all.

Every chord here is rebindable — see ``RowShortcuts``.

## Sorting from the Keyboard

A ``Table`` with a `sortOrder` binding sorts from the keyboard as well as from a
header click: <kbd>Ctrl</kbd>+<kbd>S</kbd> sorts by the next sortable column,
wrapping round to the first, and <kbd>Ctrl</kbd>+<kbd>D</kbd> reverses the
current direction. Both run the same rule a click runs — the same
`KeyPathComparator` promotion, with the sort it displaced kept behind it as the
tie-break — so the two routes cannot drift apart.

Control letters rather than one chord with Shift on it, because
<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> is the same byte as
<kbd>Ctrl</kbd>+<kbd>S</kbd> in any terminal without `modifyOtherKeys`: a shifted
variant is not merely unbound there, it is undeliverable. Both are rebindable —
see ``RowAction/sortNextColumn`` and ``RowAction/reverseSortOrder``.

## Reordering Several Rows

Grab any row of a multi-selection and the whole selection comes — macOS's rule,
and what makes a multi-row drag discoverable at all. Grabbing an UNSELECTED row
takes only that row, which is how you move one row out of a selection without
clearing it first.

They travel as a block and land as one: a disjoint selection arrives contiguous,
in its original relative order, through a single `onMove`. So the preview shows
one slot however many rows are in hand — a gap per row would promise something
the drop does not do — and that slot is as tall as the block, holding a faint
copy of every row under ``RowReorderFeedback/dimmed`` and making room for all of
them under ``RowReorderFeedback/cursor``, which floats the whole block on the
pointer. Grab it by its third row and it hangs from its third row.

Under ``RowReorderFeedback/live`` a block shuffles as the pointer crosses slots,
exactly as one row does — it lands after the row it is dragged onto going down,
before it going up. A KEYBOARD move of several rows previews with a slot instead,
whatever the view asked for: it has a cancel, and while one `onMove` can gather a
scattered selection into a block, nothing can scatter it back, so there would be
nothing to cancel to.
