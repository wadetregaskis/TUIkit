# Layout System

Understand the two-pass layout used by stacks and other layout containers.

## Overview

TUIkit uses a two-pass layout system inspired by SwiftUI's layout protocol. Layout containers like ``VStack`` and ``HStack`` first **measure** each child, then **render** them with allocated sizes. This approach enables features like flexible spacers, proportional sizing, and proper alignment.

## The Two Passes

### Pass 1: Measure

The parent proposes a size to each child via ``ProposedSize``. Each child responds with a ``ViewSize`` that describes how much space it needs and whether it can flex.

```
Parent (VStack)
  ├─ propose(width: 40, height: nil) → Text    → ViewSize(10, 1, flexible: false)
  ├─ propose(width: 40, height: nil) → Spacer  → ViewSize(0, 0, flexible: true)
  └─ propose(width: 40, height: nil) → Button  → ViewSize(12, 1, flexible: false)
```

### Pass 2: Render

After measuring all children, the parent distributes the remaining space among flexible children and renders each child with its final allocated size.

```
Parent allocates:
  Text   → render(width: 40, height: 1)   // Gets full width, fixed height
  Spacer → render(width: 40, height: 8)   // Gets remaining vertical space
  Button → render(width: 40, height: 1)   // Gets full width, fixed height
```

## ProposedSize

``ProposedSize`` represents the space a parent offers to a child. Either dimension can be `nil`, meaning "use your ideal size."

```swift
public struct ProposedSize {
    public var width: Int?
    public var height: Int?
}
```

| Value | Meaning |
|-------|---------|
| `nil` | Use ideal size (no constraint) |
| `0` | Minimum size |
| `> 0` | Available space in characters/lines |

## ViewSize

``ViewSize`` is the child's response: how much space it needs and whether it can expand.

```swift
public struct ViewSize {
    public var width: Int
    public var height: Int
    public var isWidthFlexible: Bool
    public var isHeightFlexible: Bool
}
```

Factory methods make common patterns concise:

```swift
ViewSize.fixed(20, 1)                    // Fixed 20x1, won't expand
ViewSize.flexible(minWidth: 0, minHeight: 0)  // Expands in both directions
ViewSize.flexibleWidth(minWidth: 5, height: 1) // Expands horizontally only
```

## The Layoutable Protocol

Views that participate in two-pass layout conform to `Layoutable` (which extends `Renderable`):

```swift
protocol Layoutable: Renderable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize
}
```

A default implementation renders the view and measures the resulting buffer. Custom implementations can calculate size without rendering for better performance.

## ChildView

Layout containers wrap their children in `ChildView`, which provides a uniform interface for measuring and rendering:

```swift
struct ChildView {
    func measure(proposal: ProposedSize, context: RenderContext) -> ViewSize
    func render(width: Int, height: Int, context: RenderContext) -> FrameBuffer
}
```

`ChildView` automatically detects spacers and propagates child identity for correct state management.

## How Stacks Lay Out Children

``VStack`` and ``HStack`` follow this algorithm:

1. **Measure** all children with `.unspecified` to learn their natural sizes
2. **Sum** the fixed sizes along the stack axis
3. **Distribute** remaining space among flexible children (spacers, flexible text fields, etc.)
4. **Re-measure** each child along the *cross axis* at its allocated size,
   so the row / column is tall (or wide) enough for any wrapping a narrow
   allocated width forces. Without this step a long `Text` inside an
   `HStack` would silently lose its wrapped lines when the stack squeezed
   it under its natural width.
5. **Render** each child with its allocated size
6. **Compose** the rendered buffers with the specified spacing and alignment

Flexible children share remaining space equally. If multiple spacers exist, they each get an equal portion of the leftover space.

## Alignment Guides

Step 6 above aligns each child on one *guide*: `.leading` sits at a view's
leading edge, `.center` at its middle, and the container lines those positions
up. ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)`` moves a
child's guide, so it can hang off the alignment line instead of sitting on it:

```swift
VStack(alignment: .leading) {
    Text("•").alignmentGuide(.leading) { d in d[.trailing] }
    Text("bullet hangs left of this")
}
```

Two consequences worth knowing before you reach for it:

- **The container can grow past its largest child.** The bullet's guide is now
  its *trailing* edge, so every sibling shifts right to meet it and the column
  ends up wider than the widest line in it. Both passes account for this — the
  measure reports the grown extent, or the parent would reserve too little.
- **Apply it as the outermost modifier** on the child, exactly as with
  ``View/zIndex(_:)``. A modifier applied *after* it (`.padding()`, a `.frame`)
  wraps the guide where the container cannot see it, and the guide has no
  effect. TUIkit's buffers carry no guide metadata for such a wrapper to
  translate, so the alternative would be a guide reported from the wrong
  coordinate space — silently wrong instead of visibly absent.

Guides are read by ``VStack``, ``HStack``, ``ZStack`` and their lazy twins, and
by the single-child regions `.frame(alignment:)`, `.overlay(alignment:)` and
`.background(alignment:)`. In a **lazy** stack the run is the realized rows,
which is the same limit SwiftUI has: prefer guides on content whose realized set
is stable.

Custom guides come from ``AlignmentID``, whose `defaultValue(in:)` receives the
view's ``ViewDimensions``. Note that a guide's value is `Double` even though
every size and position here is a whole cell — see ``AlignmentID`` for why that
is what preserves TUIkit's long-standing centring rather than shifting it.

## Reading the Space You Were Given

``GeometryReader`` hands its content the size the container was actually
offered, so a view can branch on it:

```swift
GeometryReader { proxy in
    if proxy.size.width >= 60 { HStack { Sidebar(); Detail() } } else { Detail() }
}
```

As in SwiftUI it **fills** the space proposed to it rather than hugging its
content — that is what makes the reported size meaningful — so bound it with a
`.frame(...)` when you want it smaller. Its content is not measured during
Pass 1: measuring would mean building it, which needs a proxy, which needs the
size Pass 1 is computing.

## Which Views Are Layoutable?

| View | Layoutable? | Flexibility |
|------|------------|-------------|
| ``Text`` | Yes | Fixed (wraps at proposed width) |
| ``Spacer`` | Yes | Flexible in stack direction |
| ``Button`` | Yes | Width-flexible |
| ``TextField`` | Yes | Width-flexible |
| ``SecureField`` | Yes | Width-flexible |
| ``Slider`` | Yes | Width-flexible |
| ``Divider`` | Yes | Width-flexible |
| ``ProgressView`` | Yes | Width-flexible |
| ``Image`` | Yes | Fixed (aspect-fits the proposed/viewport box) |

Views that are not `Layoutable` use the default implementation which renders first, then reports the buffer size as fixed.

## See Also

- ``ProposedSize``
- ``ViewSize``
- ``GeometryReader``
- ``AlignmentID``
- ``ViewDimensions``
- ``VStack``
- ``HStack``
- ``Spacer``
- <doc:RenderCycle>
