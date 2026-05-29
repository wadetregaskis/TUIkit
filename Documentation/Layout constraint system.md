# Plan: a more powerful width/height constraint system

This document is a design discussion, not yet a specification. It catalogues what TUIkit's layout pipeline can express today, lists the constraint shapes that are currently awkward or impossible to express, and proposes a direction. The intent is to lock in a direction with the user before any of it is implemented.

## What TUIkit can express today

Layout runs in two passes. Views conform to `Layoutable` and implement `sizeThatFits(proposal:context:)`, which returns a `ViewSize`:

```swift
public struct ViewSize {
    public var width: Int
    public var height: Int
    public var isWidthFlexible: Bool
    public var isHeightFlexible: Bool
}
```

Built-in conveniences pin specific shapes:

- `ViewSize.fixed(w, h)` — both axes fixed.
- `ViewSize.flexible(minWidth:minHeight:)` — both axes flexible from a minimum.
- `ViewSize.flexibleWidth(minWidth:height:)`, `ViewSize.flexibleHeight(width:minHeight:)` — one axis flexible, the other fixed.

The proposal carries `proposal.width` and `proposal.height` as `Int?` ("nil = use ideal"). Parents propose sizes; children return what they want. The compositor reconciles them.

`FrameModifier` exposes the user-facing surface:

- `.frame(width:, height:)` — fixed dimensions.
- `.frame(minWidth:, idealWidth:, maxWidth:, minHeight:, idealHeight:, maxHeight:, alignment:)` — the flexible-frame form.
- `FrameDimension` is `.fixed(Int)` or `.infinity`.

`VStack` / `HStack` distribute space between children using the `isWidthFlexible` / `isHeightFlexible` flags. `Spacer` is flexible-in-its-stack-axis. `LazyHStack` / `LazyVStack` do the same for streamed content. `NavigationSplitView` divides horizontal space between named columns using `.navigationSplitViewColumnWidth(...)`.

`Box` / `ContainerView` / `PaddingModifier` / `BorderModifier` shrink the available proposal for their child by the chrome they add and re-emit the child's reported size adjusted upward by the chrome.

## What is awkward or impossible today

These are the cases that come up in real layouts and that the current API either can't express cleanly or can't express at all.

**1. Per-axis fixed-or-flexible distinction at the call site.**
The flexible form of `.frame(...)` takes `min`/`ideal`/`max` per axis, but the user has to remember which combination yields which behaviour (e.g. "if I pass `maxWidth: .infinity` does that override `idealWidth`?"). There's no labelled enum that says "this axis is fixed at N", "this axis is fixed but with a minimum", "this axis fills available space within a range" — the user has to encode the intent through the combinations.

**2. Aspect-ratio constraints.**
There is no `.aspectRatio(_:contentMode:)`. Views with intrinsic aspect ratios (Image is the obvious one, but also a square Canvas, a 16:9 video placeholder, etc.) currently have to either pick a fixed size or accept whatever the parent proposes and live with distortion. SwiftUI's `aspectRatio` modifier deserves a parallel.

**3. Relative-to-parent fractions.**
"Take 30% of the available width." There is no way to express this without computing it explicitly outside the layout. SwiftUI has `.containerRelativeFrame(...)`. A TUI variant — `.frame(width: .fraction(0.30))` or `.relativeFrame(width: 0.30)` — would clean up split views, dashboards, header strips, etc.

**4. Weighted distribution within a stack.**
`VStack`/`HStack` give equal extra space to every flexible child. There is no way to say "this child gets twice the extra width as that one." CSS `flex-grow: N`, Android weights, Tk's `pack -weight`, SwiftUI's `Grid` with `gridCellColumns(_:)` — these are all the same general idea. For tables, dashboards, and any layout with multiple flexible columns, the equal-weight default is wrong almost as often as it's right.

**5. Min/max applied externally.**
Today min/max lives on the flexible-frame form. There's no way to wrap an arbitrary view with "...but also no taller than 10 lines" without introducing a frame modifier that might otherwise change its sizing in subtle ways. A composable `.constraint(maxHeight: 10)` that doesn't touch the underlying flexibility behaviour would be useful.

**6. Symmetric vs asymmetric flexibility.**
The current `isWidthFlexible: Bool` flag is binary — a view either takes extra space or it doesn't. There's no way to say "I'd like extra space if there is any, but only up to 2× my ideal size." For a button that should grow with extra room but not become absurdly wide on a wide terminal, this is exactly what's needed.

**7. Cross-axis dependency.**
Some content's height depends on its width — wrapping text being the canonical example. SwiftUI's layout pass handles this transparently because each view sees a `ProposedSize` and can reply with a derived `ViewSize`. TUIkit's `ProposedSize` does support this, but the public-facing `.frame(...)` surface doesn't make it discoverable how to thread an intrinsic relationship through. A "give me what fits in width W" idiom is needed for text-heavy layouts.

**8. Alignment under shrink.**
When content is larger than the proposal, alignment of the truncated view matters (leading vs trailing vs center clipping). `_HStackCore` / `_VStackCore` handle this internally but there's no exposed `.layoutPriority(_:)` for the case where two siblings can't both fit. SwiftUI's `.layoutPriority(_:)` is a small but well-targeted concept.

## Proposed direction

In ranking these by impact, the ones I'd build first are the ones that show up in the most layouts and don't add new conceptual machinery. They are:

1. **Aspect-ratio modifier**. Low scope (~50 lines), instantly useful for Image-heavy layouts, has a known shape from SwiftUI.

2. **Fractional / relative frames** — `.frame(width: .fraction(0.3), height: .fraction(0.5))`. Adds a `FrameSize` enum (`.fixed(Int) | .fraction(Double) | .infinity`) and threads it through `FrameModifier`. Layouts that currently hard-code 30 cells or 40 cells become resolution-independent.

3. **`.layoutPriority(_:)`** — a small `Double` priority threaded through the environment and inspected by stacks when there isn't enough room to satisfy every child's ideal size. Already a known SwiftUI surface, ~20 lines per stack.

4. **Weighted distribution in stacks** — `.frame(width: .weighted(2))` on stack children. The stack collects weights from flexible children, divides remaining space by weight sum, and gives each child its share. The shape is more invasive than the others (it needs reasoning in `_HStackCore` / `_VStackCore` about what "weighted" means for non-flexible children), and `Grid` would benefit too.

5. **External min/max wrapper** — `.constraint(minWidth:, idealWidth:, maxWidth:, ...)` that doesn't override the view's flexibility, just constrains the proposal it sees. Tiny shim; useful for cases where the user wants a quick cap without restructuring.

The remaining items (cross-axis dependency exposed publicly, asymmetric flexibility) feel like they want their own design pass after watching how the above five compose. I'd hold them.

## Open questions

- **Naming.** SwiftUI has `containerRelativeFrame`, `aspectRatio`, `layoutPriority`; do we match exactly, or do we lean on terms that read better in a TUI context (e.g. `cell` instead of `point`)? My instinct is match SwiftUI exactly — the rule from .claude/CLAUDE.md is to mirror SwiftUI parameter names and order, and that's served us well so far.
- **Should `FrameDimension` (current) and `FrameSize` (proposed) coexist or unify?** The current enum is `.fixed(Int) | .infinity`. Adding `.fraction(Double)` would naturally extend it to a single new enum that covers both fixed and proportional. I'd unify under one name and migrate `FrameDimension` → `FrameSize`.
- **Weighted distribution interaction with `Spacer`**. `Spacer` is the canonical flexible-with-no-content child. If a sibling has `.frame(width: .weighted(2))`, what does `Spacer` get — weight 1, infinite weight, or "fill what's left after the weights are satisfied"? Worth nailing down before implementing.
- **Layout debugging**. The current pipeline is opaque to a user trying to understand why a layout came out the wrong size. Worth thinking about whether to add a `.debugLayout()` modifier that prints `(proposed, returned)` per view in a render-time annotation.

## Suggested follow-up tasks

If the direction here is approved, I'd file:

1. Add `AspectRatioModifier` and `.aspectRatio(_:contentMode:)`.
2. Introduce `FrameSize`, deprecate `FrameDimension`, add `.fraction` and `.fixed` variants, thread through `.frame(...)`.
3. Add `.layoutPriority(_:)` and have `_VStackCore` / `_HStackCore` consult it on shrink.
4. Add `.weighted` to `FrameSize` and update stack distribution to honour it.
5. Add `.constraint(...)` as a low-disruption external min/max wrapper.
6. (Stretch) `.debugLayout()` modifier for diagnostics.

Each is independent — they can land in any order. (1) and (3) are the smallest; (4) is the most invasive.
