//  🖥️ TUIKit — Terminal UI Kit for Swift
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

// MARK: - Erasure

/// The existential the erased layout is called through. `Cache` is `Any` here
/// and cast back at each entry point — the cast cannot fail, because the only
/// thing that ever produced the value is this same box.
@MainActor
private protocol AnyLayoutBox {
    func makeCache(subviews: LayoutSubviews) -> Any
    func updateCache(_ cache: inout Any, subviews: LayoutSubviews)
    func sizeThatFits(
        proposal: ProposedSize, subviews: LayoutSubviews, cache: inout Any) -> ViewSize
    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: LayoutSubviews, cache: inout Any)
}

private struct ConcreteBox<L: Layout>: AnyLayoutBox {
    let layout: L

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
