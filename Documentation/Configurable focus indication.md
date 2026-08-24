# Making focus indication configurable

**Status: research. Nothing implemented, nothing decided.**

The question, as asked: focus is shown inconsistently across the TUI — a bullet
here, a row background there — so what if *what* focus looks like were
configurable, through a standard enum and an environment cascade, with extra
modes such as recolouring the foreground?

What follows is what the code actually does today (measured, not remembered),
where the inconsistency really is, what the enum would have to answer, and two
findings that decide most of it.

## What is drawn today

There is already one rule, and it is nearly universal:

> **Focus is a pulsing accent applied to whichever cells the control owns.**

`SelectionIndicatorStyle` (`.none` / `.blink` / `.pulse`, plus a speed) already
cascades through the environment and every affordance below resolves through
`SelectionEmphasis`, so *how* focus animates is configurable already. What
differs between controls is only *which cells* the accent lands on — and that is
decided by what each control has spare:

| Control | Cells the accent lands on |
|---|---|
| `Button` | the caps `▐ … ▌`, plus bold |
| `RadioButtonGroup` | the `●` bullet of the focused item |
| `Slider`, `Stepper` | the `◀` `▶` arrows |
| `SwatchGrid`, `Color256Grid` | a marker drawn over the focused swatch |
| `ScrollView`, `List`/`Table` indicators | the scrollbar thumb / the "▲ N more" line |
| `NavigationSplitView` | the divider |
| `TextField`, `TextEditor` | the text cursor (its own clock) |
| Menu items | the row background, plus bold |
| **`Table` row** | a `●` in the 2-cell indicator gutter **and** the row background |
| **`List` row** | the row background **only** |

So the inconsistency is not scattered: it is one row of that table. `List`
reserves a one-cell gutter for every row (`renderPlainLine` prepends a space) and
never draws in it, while `Table` puts a bullet in its own. Same state, same
palette, same pulse — one shows a bullet and the other does not. That is almost
certainly what prompted the question, and it is a two-line fix independent of
everything below.

The other apparent variety — caps, arrows, bullets — is not arbitrariness. It is
one idea meeting different geometry: a control marks the cell it has, and a
`List` row has none, because the row *is* content all the way across. Which is
exactly why it uses a background.

## Finding 1: a colour-based affordance can always be overpainted

Measured. A `List` whose rows contain `Text(item).background(.rgb(200, 0, 0))`,
focused, renders its cursor row as:

```
48;2;53;132;53  " "        ← the row's focus background
48;2;200;0;0    "a"        ← the CONTENT's background wins its own cells
0                          ← the content's reset…
48;2;53;132;53  " plain…"  ← …after which the row background is re-asserted
```

`withPersistentBackground` prefixes the row's background code and re-inserts it
after every inner `reset`, so the row colour is a **floor**: it fills the cells
the content did not paint, and loses every cell the content did. A row whose
content paints itself edge to edge therefore shows **no focus highlight at all**.

The same mechanism applies to a foreground mode, and worse: `.foregroundStyle`
on row content is far more common than `.background`, so a `.foreground` focus
mode would be invisible on most styled rows rather than a few. It is not that
foreground would interact *badly* with custom text styling — it is that custom
text styling silently wins, exactly as it already does for backgrounds, and the
user is left with no cue.

**A marker in a gutter is the only mode that cannot be overpainted**, because it
occupies a cell the content does not own. If the goal is "focus is always
visible whatever the app draws", that is the only mode that can promise it, and
it costs a column.

## Finding 2: the enum's hard part is the fallback, not the cases

The cases are easy to name:

```swift
public enum FocusIndication: Sendable, Equatable {
    case automatic    // the control's own answer — today's behaviour
    case marker       // a glyph in a gutter cell the content does not own
    case background   // the focused cells take the accent fill
    case foreground   // the focused text takes the accent
    case bold         // weight alone
    case none         // nothing; the app indicates focus itself
}

extension View {
    public func focusIndication(_ indication: FocusIndication) -> some View
}
```

…and the cascade is the same shape as `selectionIndicatorStyle`, which already
works and is the precedent to copy. But every control then has to answer what it
does when the requested mode is not one it can draw:

- `.marker` on a `Slider` — its arrows *are* markers; does the mode mean "and
  also a gutter bullet", or is it already satisfied?
- `.background` on a `Button` — fill the whole button? That is a different
  control, visually, and one nobody asked for.
- `.marker` on a `List` — free, it has the gutter; on a `Table` — already there.
- `.foreground` on anything whose affordance is a single glyph is
  indistinguishable from `.marker`.
- `.none` everywhere is coherent and is the one mode with no fallback question.

So the enum cannot be a promise; it has to be a **preference with a documented
resolution per control**, which is a lot of surface for a question most apps
never ask. Two ways to cut it down, in increasing order of how much I would
actually recommend them:

1. **Ship `.automatic` / `.marker` / `.none` only.** Three cases, each with an
   honest meaning everywhere: "as the control sees fit", "in a gutter cell,
   always visible", "nothing". `.background` and `.foreground` are then not
   modes but *what `.automatic` already resolves to* — which is true today.
2. **Ship nothing, and make `List` draw the bullet `Table` already does.** The
   inconsistency goes away, `SelectionIndicatorStyle` continues to answer the
   "how loud" question, and no new public surface is added for a preference
   nobody has asked for twice.

## What I would do

Fix the actual inconsistency first — `List`'s empty gutter — and see whether the
question survives it. It is a small change, it is measurable, and it costs
nothing to reverse.

If configurability is still wanted after that, ship option 1. `.marker` is the
mode with a property worth having (it cannot be overpainted, per Finding 1), and
it is the one an app with heavily styled rows genuinely needs. `.background`
and `.foreground` as *requestable* modes would each need a per-control fallback
table, would be silently defeated by ordinary content styling, and would let an
app ask for something the framework then quietly does not do — which is the
failure mode this codebase spends most of its rules avoiding.

A note on scope if it is built: `FocusIndication` answers *what*, and
`SelectionIndicatorStyle` answers *how it animates*. They should stay separate
and compose — `.focusIndication(.marker).selectionIndicatorStyle(.none)` is a
perfectly sensible pair, and folding them into one type would make half its
combinations unspellable.
