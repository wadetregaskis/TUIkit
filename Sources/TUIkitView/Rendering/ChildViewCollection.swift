//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ChildViewCollection.swift
//
//  Stage 4 of "Locating things without drawing them" (§10, the foundation
//  blocker): `ChildViewProvider.childViews` returns an eager array — for a
//  huge `ForEach` that builds every row view and allocates every id string
//  before any layout question is even asked. This collection is the lazy
//  alternative: O(1) count, per-ordinal construction on demand, and stable
//  keys answerable WITHOUT building the row — à la SwiftUI's LayoutSubviews,
//  minus the eager identity pass SwiftUI itself pays (design doc §4, the
//  identity tax).
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Child View Collection

/// A random-access view of a provider's children, built on demand.
///
/// Two backings:
/// - **Lazy** (`init(count:key:build:)`): children are constructed per
///   subscript; `key(at:)` answers from the provider's data without invoking
///   the row builder. Repeated subscripts rebuild — construction is cheap
///   next to measure/render, and the row memo already deduplicates the
///   expensive part for `Equatable` elements.
/// - **Eager** (`init(eager:)`): wraps an existing `[ChildView]`, so every
///   provider that hasn't opted into laziness participates unchanged.
@MainActor
public struct ChildViewCollection {
    /// The number of children. O(1) for both backings.
    public let count: Int

    /// Whether there are no children.
    public var isEmpty: Bool { count < 1 }

    /// Whether EVERY child is identified by a stable key (a homogeneous
    /// keyed provider — `ForEach`). When `true`, a positional-index routing
    /// query can answer `nil` without building a single child: keyed
    /// children never match an index step.
    public let isUniformlyKeyed: Bool

    private let build: (Int) -> ChildView
    private let keyAt: ((Int) -> String)?
    private let eagerChildren: [ChildView]?

    /// A lazy collection: `build` constructs the child at an ordinal;
    /// `key` returns its stable identity key without building it.
    public init(count: Int, key: ((Int) -> String)?, build: @escaping (Int) -> ChildView) {
        self.count = count
        self.isUniformlyKeyed = key != nil
        self.build = build
        self.keyAt = key
        self.eagerChildren = nil
    }

    /// An eager collection wrapping already-built children.
    public init(eager children: [ChildView]) {
        self.count = children.count
        self.isUniformlyKeyed = false
        self.build = { children[$0] }
        self.keyAt = nil
        self.eagerChildren = children
    }

    /// The child at `ordinal`, built on demand for lazy backings.
    public subscript(ordinal: Int) -> ChildView {
        build(ordinal)
    }

    /// The stable identity key of the child at `ordinal`, or `nil` for
    /// positionally-identified children. Never builds a row for a lazy
    /// backing; reads the already-built child for an eager one.
    public func key(at ordinal: Int) -> String? {
        if let keyAt { return keyAt(ordinal) }
        return build(ordinal).identityChildKey
    }

    /// The first ordinal whose stable key matches, or `nil`.
    ///
    /// Linear over keys — Ω(n) worst case, the honestly-unavoidable
    /// id→ordinal cost of deferred identity (design doc §12) — but it
    /// touches only keys, never building a row when the provider supplies
    /// them.
    public func firstOrdinal(forKey key: String) -> Int? {
        for ordinal in 0..<count where self.key(at: ordinal) == key {
            return ordinal
        }
        return nil
    }

    /// The wrapped eager array when this collection has one, else builds
    /// every child — the bridge for call sites not yet converted to
    /// per-ordinal access. Named to make the cost visible at the call site.
    public func buildingAll() -> [ChildView] {
        if let eagerChildren { return eagerChildren }
        return (0..<count).map(build)
    }
}

// MARK: - Lazy Child View Provider

/// A `ChildViewProvider` that can enumerate its children without building
/// them all. `ForEach` is the conformer that matters: its count and keys
/// come straight from the data collection.
@MainActor
public protocol LazyChildViewProvider {
    /// The provider's children as an on-demand collection.
    ///
    /// - Parameter context: The rendering context (for child identity).
    func childViewCollection(context: RenderContext) -> ChildViewCollection
}

/// Resolves content into a child collection: lazily when the content can
/// (`LazyChildViewProvider`), else by wrapping the eager resolution — so
/// callers get one shape and providers opt into laziness independently.
@MainActor
public func resolveChildViewCollection<V: View>(
    from content: V, context: RenderContext
) -> ChildViewCollection {
    if let lazyProvider = content as? LazyChildViewProvider {
        return lazyProvider.childViewCollection(context: context)
    }
    return ChildViewCollection(eager: resolveChildViews(from: content, context: context))
}
