//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoizedRow.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Type-erased Equatable

/// A type-erased `Equatable` value, so a value-memo can key on a `ForEach`
/// element whose static type is not statically known to conform to `Equatable`.
///
/// `ForEach<Data, ID, Content>` does not constrain `Data.Element: Equatable`, so
/// auto-wiring the row memo recovers the conformance at runtime
/// (`element as? any Equatable`) and wraps it here. Comparing two boxes is an
/// `Element == Element` only when the dynamic types match; a type mismatch
/// compares unequal (so a heterogeneous collection simply never hits).
public struct AnyEquatableBox: Equatable {
    @usableFromInline let value: any Equatable

    public init<E: Equatable>(_ value: E) {
        self.value = value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Open `lhs`'s existential to its concrete type, then compare against
        // `rhs` cast to that same type. This is exactly the old stored `isEqual`
        // closure — `(rhs as? typeof(lhs)) == lhs` — but without allocating a
        // heap closure per box: a `ForEach`/`List` row builds one box per
        // element every frame, so that per-row closure allocation was pure churn
        // on the hottest general path. A dynamic-type mismatch (a heterogeneous
        // collection) casts to nil and compares unequal, so a mixed collection
        // still never produces a false cache hit.
        func equal<L: Equatable>(_ lhsValue: L) -> Bool {
            (rhs.value as? L) == lhsValue
        }
        return equal(lhs.value)
    }
}

// MARK: - Memoized Row

/// Memoizes a row's render (and measure) by the value of its *data element*,
/// rather than by the view value (`EquatableView`) — because a `ForEach` row is
/// `content(element)`, an arbitrary non-`Equatable` view, but is a pure function
/// of its `Equatable` element. `ForEach.extractListRows` wraps rows in this
/// automatically when the element is `Equatable`.
///
/// A row is the natural unit for a list: `List` renders every row to a buffer
/// each frame (then windows to the viewport), so unchanged rows re-render
/// needlessly. Keying the existing `RenderCache` on the element collapses that —
/// one `Element ==` skips the whole row subtree.
///
/// ## Correctness
///
/// Reuses `RenderCache` and its lifecycle. `@State` / `@Observable` changes
/// already invalidate the cache (`StateBox.didSet` → `clearAffected`, keyed on
/// the changed identity's ancestors — which includes the row), so a stateful
/// row is re-rendered when its state changes; no special handling needed.
///
/// The one thing the cache deliberately does **not** invalidate is the
/// per-frame pulse tick, so this declines to cache a row that would freeze:
///   - an **interactive** subtree (a focused, pulsing control) — detected by
///     hit-test regions / overlays in the row's rendered buffer; or
///   - a subtree that reads a **per-frame-volatile** environment value
///     (`pulsePhase`) — detected via a ``VolatileReadTracker``.
///
/// **Known hole — captured data.** The memo assumes a row is a pure function
/// of its element. A row whose content *captures* mutable data from outside
/// its own subtree (e.g. `ForEach(0..<2) { _ in row drawn from some outer
/// state }`) can serve a stale buffer when that data changes: the element key
/// is unchanged, so nothing but `clearAffected` can save it.
///
/// **Which writes save it, and which do not** — measured 2026-08-24, because
/// the boundary decides whether a given `ForEach` is a bug or merely ugly.
/// `clearAffected(by:)` drops the writer's identity, its ANCESTORS and its
/// DESCENDANTS. So:
///
/// - **A write from an ancestor reaches the row.** `@State` in an enclosing
///   view — the overwhelmingly common case — clears the row and it rebuilds.
///   This is why the pattern survives in so much code without being noticed.
/// - **A write from a COUSIN does not.** State owned by a sibling subtree is
///   neither, so the clear matches nothing and the row keeps its buffer for as
///   long as its element is unchanged.
///
/// The second is not hypothetical. `ColorPickerPanel`'s preview block was
/// `ForEach(0..<5)` reading a colour from outside, and the writes that moved
/// that colour came from the panel's OWN sliders and tabs — `_TabViewCore`,
/// `_EditableValueField`, siblings of the block. Measured on the live app:
/// four slider drags, six `clearAffected` calls, `0 of 5` entries dropped
/// every time, and the swatch held the colour the dialog opened with while the
/// read-out beside it — the same value, not memoized — followed every drag.
///
/// Undetectable here (closures are opaque). Framework views must not build
/// display-only rows from captured mutable data under an `Equatable`-element
/// `ForEach` — iterate the data itself (so it IS the element), or drop the
/// `ForEach`. The gradient editor's frozen preview strip was this exact shape.
///
/// For `List` the selection highlight is applied *outside* the cached row
/// buffer, so selection/scroll never invalidate it — only the row's own content
/// matters.
///
/// It is `Renderable` (and so adds no child identity), so the inner content
/// keeps whatever identity it would have had unwrapped: the memo is
/// identity-transparent to `@State` / focus.
public struct _MemoizedRow<Element: Equatable, Source, Content: View>: View, Renderable, Layoutable {
    public let element: Element
    /// The value the row is built FROM, and the builder that builds it.
    ///
    /// Deliberately not a built `Content`. The memo's whole premise is that
    /// most rows hit — 94% of them in the `fanout` stress scenario — and on a
    /// hit the built row view is never looked at: the cached buffer (or cached
    /// size) is returned and the view is discarded. Building it eagerly, once
    /// per row per pass, was `ForEach.makeChild`'s 21% of that scenario's
    /// frame, nearly all of it thrown away.
    ///
    /// A `(Source) -> Content` rather than a captured `() -> Content` so
    /// deferral costs no allocation: `build` is the enclosing `ForEach`'s own
    /// content closure, which already exists and is shared by every row, so
    /// storing it is a retain. A per-row capturing closure would trade the row
    /// view's allocations for a closure box's, one per row per pass.
    private let source: Source
    private let build: (Source) -> Content

    /// The row view. **Builds it** — call once, and only where the memo has
    /// already missed.
    private var content: Content { build(source) }

    /// Memoizes `build(source)` under the key `element`.
    public init(element: Element, source: Source, build: @escaping (Source) -> Content) {
        self.element = element
        self.source = source
        self.build = build
    }

    /// Memoizes an already-built row.
    ///
    /// For callers that must construct the view anyway — `List`, which reads
    /// the row's `.badge(_:)` off the unwrapped view before rendering it —
    /// and for tests. The identity builder captures nothing, so it is a static
    /// thunk, not an allocation.
    public init(element: Element, content: Content) where Source == Content {
        self.init(element: element, source: content, build: { $0 })
    }

    public var body: Never {
        fatalError("_MemoizedRow renders via Renderable")
    }

    /// Memoized by the row's DATA ELEMENT, through the shared value memo — see
    /// `renderValueMemoized(key:viewType:context:verifies:render:)`.
    ///
    /// The soundness argument is this type's own, and it is the weaker of the
    /// two the shared memo serves. `EquatableView` keys on the whole view value,
    /// so a hit means the very thing that would have been rendered compares
    /// equal. Here the key is the element and the claim is that the row is a pure
    /// function of it — true for a row built from its element, and NOT true for
    /// one that captures mutable data from outside its own subtree, which is the
    /// known hole documented on the type above.
    ///
    /// `verifies: false` — this half does not check a served buffer against a
    /// fresh render yet. It should: every buffer the `Stress` harness serves is
    /// one of these (no scenario uses `.equatable()`), so the CI step that exists
    /// to catch a memo serving a stale picture has never checked a single serve.
    /// Arming it changes what happens under `TUIKIT_VERIFY_RENDER_MEMO`, where
    /// suites that count renders on memoized rows expect exactly zero, so it is
    /// its own commit.
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderValueMemoized(
            key: element, viewType: Content.self, context: context, verifies: false
        ) { TUIkitView.renderToBuffer(content, context: $0) }
    }

    /// The size twin, same shared implementation.
    ///
    /// `content` is a computed property that BUILDS the row, so it must be
    /// touched only inside the closure — which the memo calls only on a miss.
    /// That is the whole reason the row view is not a stored property: 94% of
    /// rows hit in the `fanout` stress scenario, and building the view eagerly
    /// once per row per pass was `ForEach.makeChild`'s 21% of that frame, nearly
    /// all of it thrown away.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureValueMemoized(key: element, proposal: proposal, context: context) {
            measureChild(content, proposal: proposal, context: $0)
        }
    }
}
