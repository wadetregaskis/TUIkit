//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Layout.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Layout

/// A type that arranges a collection of subviews itself.
///
/// Conform to `Layout` when neither a stack nor a frame expresses the
/// arrangement you want, then call the layout like a function:
///
/// ```swift
/// struct Diagonal: Layout {
///     func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
///         let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
///         return ViewSize(
///             width: sizes.reduce(0) { $0 + $1.width },
///             height: sizes.reduce(0) { $0 + $1.height })
///     }
///
///     func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
///         var x = bounds.x, y = bounds.y
///         for subview in subviews {
///             subview.place(at: (x: x, y: y), proposal: .unspecified)
///             let size = subview.sizeThatFits(.unspecified)
///             x += size.width
///             y += size.height
///         }
///     }
/// }
///
/// Diagonal {
///     Text("one")
///     Text("two")
///     Text("three")
/// }
/// ```
///
/// ## Geometry is whole cells
///
/// ``sizeThatFits(proposal:subviews:cache:)`` answers in ``ViewSize`` and
/// ``placeSubviews(in:proposal:subviews:cache:)`` receives a ``CellRect`` —
/// integers, not `CGSize` and `CGRect`. A terminal has no half-column, and the
/// reasoning is recorded on ``AlignmentID``. Two consequences worth knowing:
///
/// - **Divide last.** `let each = total / count` then `i * each` silently drops
///   up to `count - 1` cells; `i * total / count` drops none and stays within a
///   cell of even. Floating point hid this by rounding at placement.
/// - **A fractional intermediate is fine — just floor it once, at the end.**
///   A radial layout computing with `cos`/`sin` is perfectly reasonable; the
///   cell boundary is where the rounding belongs, and
///   ``LayoutSubview/place(at:anchor:proposal:)`` does it for you.
///
/// ## What SwiftUI has here that this does not
///
/// - **`ViewSpacing` / `spacing(subviews:cache:)`.** SwiftUI derives preferred
///   spacing from a view's type and font. A terminal has no such notion —
///   spacing between cells is whatever the container decides — so the honest
///   answer would be a constant zero, and an API that always says zero is one
///   that invites a question it cannot answer.
/// - **`LayoutProperties`.** Nothing in TUIkit consumes `stackOrientation`.
/// - **`explicitAlignment(of:in:…)`.** A layout cannot yet publish a guide to
///   *its* parent. Omitting it keeps conformances source-compatible (an extra
///   method on your type is simply an extra method) and leaves the door open;
///   declaring it and ignoring it would be the silently-inert trap.
/// - **`Animatable`.** There is no tween space in a terminal — see the
///   compatibility notes on animation.
@MainActor
public protocol Layout {
    /// Per-layout scratch space, if the layout wants any. Defaults to `Void`.
    associatedtype Cache = Void

    /// The collection of views this layout arranges.
    typealias Subviews = LayoutSubviews

    /// Creates the cache. Called once per layout pass.
    func makeCache(subviews: Subviews) -> Cache

    /// Updates the cache when the subviews may have changed.
    func updateCache(_ cache: inout Cache, subviews: Subviews)

    /// The size this layout needs for `proposal`.
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Cache) -> ViewSize

    /// Positions each subview within `bounds`.
    ///
    /// Call one of the `place` methods on every subview: one that is never
    /// placed is not drawn. Placement order is draw order, so a layout may
    /// deliberately overlap its subviews.
    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout Cache)
}

extension Layout {
    /// Default: the cache is not updated between passes — see
    /// ``Layout/makeCache(subviews:)``.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {}
}

extension Layout where Cache == Void {
    /// Default for a layout that wants no cache.
    public func makeCache(subviews: Subviews) -> Cache { () }
}

extension Layout {
    /// Arranges `content` with this layout.
    ///
    /// Lets a layout be written where a container goes: `Diagonal { … }`.
    ///
    /// - Parameter content: The views to arrange.
    /// - Returns: A view that arranges them.
    public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        _LayoutCore(layout: self, content: content())
    }
}

// MARK: - Core

/// Drives a ``Layout``: resolves the children, asks the layout for a size and
/// for placements, then composites each placed subview into the result.
///
/// - Important: Framework infrastructure. Created by ``Layout/callAsFunction(_:)``.
public struct _LayoutCore<L: Layout, Content: View>: View, Renderable, Layoutable {
    let layout: L
    let content: Content

    public var body: Never {
        fatalError("_LayoutCore renders via Renderable")
    }

    /// The subview proxies and the sink their placements land in.
    private func resolve(context: RenderContext) -> (LayoutSubviews, LayoutPlacements) {
        let placements = LayoutPlacements()
        let children = resolveChildViews(from: content, context: context)
        return (
            LayoutSubviews(children: children, context: context, placements: placements),
            placements
        )
    }

    /// The cache lives for ONE pass rather than across them.
    ///
    /// `makeCache` therefore runs per pass and `updateCache` immediately after,
    /// so a conforming layout sees the sequence it expects and behaves
    /// identically — it just does not get the cross-pass saving SwiftUI's
    /// persistent layout graph provides. Persisting it would mean writing to
    /// `StateStorage` from inside a render, which is the measure-side-effect
    /// bug class: the write invalidates the render cache and the frame that
    /// wrote it schedules another.
    private func freshCache(_ subviews: LayoutSubviews) -> L.Cache {
        var cache = layout.makeCache(subviews: subviews)
        layout.updateCache(&cache, subviews: subviews)
        return cache
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let (subviews, _) = resolve(context: context)
        var cache = freshCache(subviews)
        return layout.sizeThatFits(
            proposal: grounded(proposal, in: context), subviews: subviews, cache: &cache)
    }

    /// Fills in an unconstrained proposal from what is actually on screen.
    ///
    /// ``renderToBuffer(context:)`` builds its proposal from
    /// `context.availableWidth`/`Height` and ignores the one it was measured
    /// with, so a `nil` here means the measure and the render answer different
    /// questions. For most layouts that is harmless — a stack's height does not
    /// depend on its width. For one whose SHAPE depends on the extent it is
    /// given, it is a real divergence: a reflowing grid asked "how tall are you
    /// at no particular width" has no honest answer, and whichever it invents
    /// is the number a parent stack then budgets rows for.
    ///
    /// Grounding both passes in the same numbers makes measure/render parity
    /// structural here, the way `Text.displayString` does for text.
    private func grounded(_ proposal: ProposedSize, in context: RenderContext) -> ProposedSize {
        ProposedSize(
            width: proposal.width ?? max(0, context.availableWidth),
            height: proposal.height ?? max(0, context.availableHeight))
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let (subviews, placements) = resolve(context: context)
        guard !subviews.isEmpty else { return FrameBuffer() }

        var cache = freshCache(subviews)
        let proposal = ProposedSize(
            width: max(0, context.availableWidth), height: max(0, context.availableHeight))
        let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)

        let bounds = CellRect(
            x: 0, y: 0, width: max(0, size.width), height: max(0, size.height))
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)

        // A blank canvas at the size the layout reported, so an arrangement
        // that leaves gaps keeps them — and so the measure it just gave its
        // parent is the size it actually occupies.
        var result = FrameBuffer(emptyWithWidth: bounds.width, height: bounds.height)
        for entry in placements.entries {
            let child = subviews[entry.index].child
            let childSize = child.measure(proposal: entry.proposal, context: context)
            let rendered = child.render(
                width: entry.proposal.width ?? childSize.width,
                height: entry.proposal.height ?? childSize.height,
                context: context)
            // In place: `composited` rebuilds every line of the canvas per
            // call, so folding n children through it is n × canvas even though
            // each child covers a couple of rows.
            result.composite(with: rendered, at: (x: entry.x, y: entry.y))
        }
        return result
    }
}
