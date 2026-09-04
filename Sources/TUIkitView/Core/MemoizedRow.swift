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

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let cache = context.renderCache else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        let identity = context.identity
        cache.markActive(identity)
        if let cached = cache.lookup(
            identity: identity, view: element,
            contextWidth: context.availableWidth, contextHeight: context.availableHeight,
            gradientFrame: context.gradientFrame)
        {
            // Keep the cached subtree's state alive for GC — the WHOLE
            // subtree, not just this identity: nothing below is visited on a
            // hit, and a `@State` deeper than a direct child would otherwise
            // be pruned this pass and reset on the next real render (see
            // `EquatableView.markSubtreeActive`, the same rule).
            context.stateStorage?.markActive(identity)
            context.stateStorage?.retainSubtree(identity)
            // The same declaration to the render cache, for the same reason
            // one layer over. `markActive(identity)` above covers THIS row
            // only; a nested `_MemoizedRow` or `.equatable()` below it — the
            // ordinary nested-`ForEach` shape, since `ForEach` wraps every
            // Equatable element row in one of these — is never visited on a
            // hit, so `removeInactive()` collected its entry while it was
            // still live, and `sizeThatFits` deliberately marks nothing, so
            // the measure walk could not rescue it either. The steady state
            // was one entry where there should have been two, and the first
            // frame the OUTER element changed, every inner row re-rendered
            // from scratch though none of them had.
            cache.retainSubtree(identity)
            return cached
        }
        // Render the content under a volatile-read tracker (reusing an
        // ancestor row's, so nesting bubbles up). @State / @Observable changes
        // already invalidate the cache (StateBox.didSet → clearAffected), so
        // stateful rows stay correct. The two things the cache does NOT catch:
        //   • interactive content — a focused, pulsing control would freeze;
        //     it shows up as hit-test regions / overlays in the row's buffer.
        //   • a non-interactive view whose output is time-varying — it reads a
        //     per-frame-volatile value (e.g. pulsePhase) or requests a scheduled
        //     animation (e.g. Spinner) — caught by the tracker delta.
        // Only memoize a row that exhibits neither.
        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        let renderContext =
            existingTracker == nil
            ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
            : context
        let unsafeBefore = tracker.cacheUnsafeCount
        // Snapshot the cache's invalidation generation too: a `clearAffected`
        // DURING this render — an environment or colour-environment change, a
        // `ScrollViewReader` publish; those are its synchronous callers —
        // fires before we store, and storing afterwards would resurrect the
        // pre-clear buffer and serve it until the element value next changes.
        // NOT a @State write: since 44660d87 those are queued
        // (`pendingInvalidations`) and drained at the next `beginRenderPass`,
        // so this counter does not move for them and the store goes ahead —
        // which is right, because the drain clears the entry before it can
        // be served.
        let clearsBefore = cache.stats.subtreeClears

        let buffer = TUIkitView.renderToBuffer(content, context: renderContext)

        let readVolatile = tracker.cacheUnsafeCount > unsafeBefore
        let invalidatedDuringRender = cache.stats.subtreeClears > clearsBefore
        // Never store a buffer produced during a measure pass. Two reasons, both
        // load-bearing:
        //   • It is INCOMPLETE. Interactive controls suppress their hit-test
        //     regions while `isMeasuring` (regions are meaningless without final
        //     positions), so a measure-pass buffer of, say, a Button has none. If
        //     the render pass then served that cached buffer, the control would
        //     render with no clickable region and no focus rect — e.g. a
        //     ScrollView could no longer locate a focused control to scroll it
        //     into view.
        //   • It CLOBBERS. A non-Layoutable ancestor (List, ScrollView) renders
        //     its children once per measure and again per render — at different
        //     available sizes. With a single entry per identity, the measure
        //     store overwrites the render store every frame, so the render lookup
        //     always misses on a different size and the row re-renders every
        //     frame (0% hit rate on exactly the rows the memo exists for). Only
        //     the render pass populates the cache, so its entry survives to the
        //     next frame.
        // The measure pass still benefits — it reads sizes through the size memo
        // (`sizeThatFits`), which is keyed by proposal and so does not clobber.
        if RenderCache.isStorable(
            buffer: buffer, context: context,
            readVolatile: readVolatile, invalidatedDuringRender: invalidatedDuringRender)
        {
            cache.store(
                identity: identity, view: element, buffer: buffer,
                contextWidth: context.availableWidth, contextHeight: context.availableHeight,
                gradientFrame: context.gradientFrame)
        }
        return buffer
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let cache = context.renderCache else {
            return measureChild(content, proposal: proposal, context: context)
        }
        // Deliberately NO markActive here: marking EVERY measured identity
        // is O(total rows) per frame on a giant eager tree (fanout at scale
        // 100 measures ~200k memoized rows — the Set inserts and identity
        // hashing alone regressed it 13%). A measure-only row whose entries
        // must survive the pass is the WINDOWED band's concern, and the
        // band paths mark the specific rows they measure (pitch and the
        // width samples) — bounded by the window, not the tree.
        let key = RenderCache.SizeKey(
            identity: context.identity,
            proposalWidth: proposal.width, proposalHeight: proposal.height,
            availableWidth: context.availableWidth, availableHeight: context.availableHeight,
            hasExplicitWidth: context.hasExplicitWidth, hasExplicitHeight: context.hasExplicitHeight)
        if let cached = cache.lookupSize(key: key, view: element) {
            return cached
        }
        // Measure under the volatile tracker, as the render path above does:
        // a subtree that declares a render side effect (`.onRenderPass`
        // instrumentation) or reads a per-frame-volatile value must not have
        // its measurement memoised away — a served size would silently hide
        // real layout participation, breaking the OnRenderPassModifier
        // contract ("observation must not be memoised away"). Store-gating
        // suffices: such a subtree never stores, so it never hits either.
        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        let measureContext =
            existingTracker == nil
            ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
            : context
        let unsafeBefore = tracker.cacheUnsafeCount
        let size = measureChild(content, proposal: proposal, context: measureContext)
        // The uncomparable-environment clause its two siblings carry — the
        // render-store's `isStorable` and `EquatableView.sizeThatFits` both
        // refuse when a non-Equatable environment value is in force, because
        // the `element` key cannot see it, so a change to that value could
        // never invalidate a stored size. This half was missed when the
        // buffer half was unified: a Form row under an injected uncomparable
        // value measured once and served that size forever.
        if tracker.cacheUnsafeCount == unsafeBefore,
            !context.environment.hasUncomparableEnvironmentValue
        {
            cache.storeSize(key: key, view: element, size: size)
        }
        return size
    }
}
