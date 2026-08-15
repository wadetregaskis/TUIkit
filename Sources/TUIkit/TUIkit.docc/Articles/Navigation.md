# Navigation

Move between screens with a push/pop stack, or side by side with columns.

## Overview

TUIkit has two navigation containers, and they answer different questions.
``NavigationStack`` is for **going somewhere and coming back** — a list of
recipes, then one recipe, then one ingredient — with a back bar at the top and
the whole terminal given over to whatever is on top. ``NavigationSplitView`` is
for **seeing the choice and the consequence at once** — a sidebar beside its
detail, which is what a wide terminal has room for and a phone does not.

Both are SwiftUI's, spelled the same way.

## A stack of screens

The shortest thing that works: a stack, links that push values, and a
`navigationDestination` saying what each kind of value looks like.

```swift
struct RecipeBrowser: View {
    var body: some View {
        NavigationStack {
            List(recipes) { recipe in
                NavigationLink(recipe.name, value: recipe)
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeView(recipe: recipe)
                    .navigationTitle(recipe.name)
            }
        }
    }
}
```

A ``NavigationLink`` is a `Button` underneath, so it is a Tab stop, Return and
Space activate it, a click works, and `.buttonStyle(_:)` restyles it. A link
whose value is `nil` is disabled.

When the screen is one specific thing with no data to route on, hand the link
the view instead:

```swift
NavigationLink("Settings") { SettingsView() }
```

### Going back

Four ways, all of which end up in the same place:

- the **‹ Back** button in the bar — focusable, clickable;
- <kbd>Esc</kbd>, which the bar claims for the status line while a screen is
  pushed, *after* the focused control has had its chance at the key (a list
  clearing its selection still wins);
- `@Environment(\.dismiss)` from anywhere inside the screen, which pops rather
  than quitting while it is inside a stack;
- removing from the path yourself, if you bound one.

``View/navigationBarBackButtonHidden(_:)`` takes away the first of those —
and, on a wide terminal, the crumb trail with it, since every crumb pops too.
<kbd>Esc</kbd> and `dismiss()` keep working: SwiftUI hides the button without
disabling the swipe-back gesture, and Esc is this framework's counterpart to
that gesture rather than to the button. A screen that must not be left at all
wants this *and* something that consumes Esc.

```swift
.navigationDestination(for: Step.self) { step in
    Wizard(step)
        .navigationBarBackButtonHidden(step.isCommitting)
}
```

### Holding the path yourself

Bind a path when something other than a link needs to change it — a deep link,
or a "back to the top" button several screens down.

```swift
@State private var path = NavigationPath()

NavigationStack(path: $path) { … }

// Return to the root from any depth:
path.removeLast(path.count)
```

``NavigationPath`` is type-erased, so different screens can push different
types. When every screen is driven by the same type, bind a plain array
instead — `NavigationStack(path: $recipes)` — and the path is just your data.

> Note: A typed path binding can only hold values of its own element type. That
  makes `NavigationLink(value:)` the one to use with it: the view-destination
  form pushes an internal token, which only the default stack and a
  `NavigationPath` can carry.

## What the terminal changes

- **The bar is exactly two rows** — the title row and the rule under it —
  whatever the title says. Chrome whose height depended on its content could not
  be laid out in one pass, so a title too long for the space is truncated rather
  than wrapped.
- **The root keeps rendering while a screen is pushed.** Off-screen, and
  isolated from focus and key events exactly as a modal's backdrop is. That is
  what keeps the root's `@State` — a scroll position, a selection, a half-filled
  form — alive to come back to, and what keeps its `navigationDestination`
  closures current rather than frozen at the frame that pushed.
- **A destination modifier has to have rendered** for its type to be known. In
  practice this is automatic, because the root renders every frame; declaring
  destinations on the root (as above, and as SwiftUI's own documentation
  recommends) keeps every type reachable. A value with no destination shows a
  blank screen that still has its back button, rather than being silently
  dropped.
- **`NavigationPath` has no `CodableRepresentation`.** Serialising one means
  recording each element's type name and looking it back up at runtime, which is
  not available on every platform TUIkit targets. Persist your own array of
  values and rebuild the path with `NavigationPath(_:)`.

## Columns instead

``NavigationSplitView`` puts two or three columns side by side, each its own
focus section, so <kbd>Tab</kbd> moves between them and the arrows move within
one. Column widths follow the ``NavigationSplitViewStyle``, and the dividers
between them can be dragged — or reached with <kbd>Tab</kbd> and resized with
the arrow keys.

```swift
NavigationSplitView {
    List(categories, selection: $categoryID) { … }
} detail: {
    DetailView(id: categoryID)
}
```

## Topics

### Stack navigation

- ``NavigationStack``
- ``NavigationLink``
- ``NavigationPath``

### Column navigation

- ``NavigationSplitView``
- ``NavigationSplitViewStyle``
- ``NavigationSplitViewVisibility``
