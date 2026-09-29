//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyLayout.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Any Layout

/// A type-erased ``Layout``.
///
/// Lets one view switch between arrangements without the branches having
/// different types — which matters here for the reason it matters in SwiftUI:
/// the two branches keep **one** identity, so the subviews keep their `@State`
/// and focus across the switch instead of being torn down and rebuilt.
///
/// ```swift
/// let layout = isWide ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
/// layout {
///     Text("one")
///     Text("two")
/// }
/// ```
///
/// ``VStackLayout``, ``HStackLayout`` and ``ZStackLayout`` are the stacks'
/// arrangements as values, which is what this is usually erasing.
public struct AnyLayout: Layout {
    /// The erased cache of whichever layout this wraps.
    public struct Cache {
        var base: Any
    }

    private let box: any AnyLayoutBox

    /// Wraps `layout`.
    public init<L: Layout>(_ layout: L) {
        self.box = ConcreteBox(layout: layout)
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(base: box.makeCache(subviews: subviews))
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        box.updateCache(&cache.base, subviews: subviews)
    }

    public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout Cache
    ) -> ViewSize {
        box.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache.base)
    }

    public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout Cache
    ) {
        box.placeSubviews(
            in: bounds, proposal: proposal, subviews: subviews, cache: &cache.base)
    }
}

extension AnyLayout: AxisPublishingLayout {
    /// Forwarded from whatever was erased: `AnyLayout(HStackLayout())` has to
    /// publish `.horizontal` to its subviews, or a ``Divider`` inside it draws
    /// the rule for whatever stack the `AnyLayout` itself happens to sit in —
    /// or, standing alone, the width-flexible horizontal one that eats the row.
    var containerAxis: Axis? { box.containerAxis }
}

// MARK: - Erasure

extension AnyLayout {
    /// The value hash's opener for the erased box (see `ValueHashOpener`):
    /// declared here because the box's protocol is private to this file, and
    /// `nonisolated` because the value hash runs off the main actor, which a
    /// layout's members are otherwise isolated to.
    nonisolated static var valueHashOpener: ValueHashOpener {
        .init((any AnyLayoutBox).self) { pointer, hash, plans in
            func open<Box: AnyLayoutBox>(_ box: Box) -> Bool { mixOpened(box, into: &hash, plans: plans) }
            return open(pointer.assumingMemoryBound(to: (any AnyLayoutBox).self).pointee)
        }
    }
}

/// The existential the erased layout is called through. `Cache` is `Any` here
/// and cast back at each entry point — the cast cannot fail, because the only
/// thing that ever produced the value is this same box.
@MainActor
private protocol AnyLayoutBox {
    /// The erased layout's axis, if it has one — see `AxisPublishingLayout`.
    var containerAxis: Axis? { get }
    func makeCache(subviews: LayoutSubviews) -> Any
    func updateCache(_ cache: inout Any, subviews: LayoutSubviews)
    func sizeThatFits(
        proposal: ProposedSize, subviews: LayoutSubviews, cache: inout Any) -> ViewSize
    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: LayoutSubviews, cache: inout Any)
}

private struct ConcreteBox<L: Layout>: AnyLayoutBox {
    let layout: L

    /// `nil` unless the wrapped layout opts in. A nested `AnyLayout` answers
    /// through its own conformance below, so the forwarding recurses.
    var containerAxis: Axis? { (layout as? any AxisPublishingLayout)?.containerAxis }

    func makeCache(subviews: LayoutSubviews) -> Any {
        layout.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout Any, subviews: LayoutSubviews) {
        guard var typed = cache as? L.Cache else { return }
        layout.updateCache(&typed, subviews: subviews)
        cache = typed
    }

    func sizeThatFits(
        proposal: ProposedSize, subviews: LayoutSubviews, cache: inout Any
    ) -> ViewSize {
        guard var typed = cache as? L.Cache else { return ViewSize.fixed(0, 0) }
        let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &typed)
        cache = typed
        return size
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: LayoutSubviews, cache: inout Any
    ) {
        guard var typed = cache as? L.Cache else { return }
        layout.placeSubviews(
            in: bounds, proposal: proposal, subviews: subviews, cache: &typed)
        cache = typed
    }
}
