//  🖥️ TUIKit — Terminal UI Kit for Swift
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
/// For `List` the selection highlight is applied *outside* the cached row
/// buffer, so selection/scroll never invalidate it — only the row's own content
/// matters.
///
/// It is `Renderable` (and so adds no child identity), so the inner content
/// keeps whatever identity it would have had unwrapped: the memo is
/// identity-transparent to `@State` / focus.
public struct _MemoizedRow<Element: Equatable, Content: View>: View, Renderable, Layoutable {
    public let element: Element
    public let content: Content

    public init(element: Element, content: Content) {
        self.element = element
        self.content = content
    }

    public var body: Never {
        fatalError("_MemoizedRow renders via Renderable")
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let cache = context.environment.renderCache else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        let identity = context.identity
        cache.markActive(identity)
        if let cached = cache.lookup(
            identity: identity, view: element,
            contextWidth: context.availableWidth, contextHeight: context.availableHeight)
        {
            // Keep the cached subtree's state identities alive for GC.
            context.environment.stateStorage?.markActive(identity)
            return cached
        }
        // Render the content under a volatile-read tracker (reusing an
        // ancestor row's, so nesting bubbles up). @State / @Observable changes
        // already invalidate the cache (StateBox.didSet → clearAffected), so
        // stateful rows stay correct. The two things the cache does NOT catch:
        //   • interactive content — a focused, pulsing control would freeze;
        //     it shows up as hit-test regions / overlays in the row's buffer.
        //   • a non-interactive view that reads a per-frame-volatile value
        //     (e.g. pulsePhase) directly — caught by the tracker delta.
        // Only memoize a row that exhibits neither.
        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        let renderContext =
            existingTracker == nil
            ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
            : context
        let readsBefore = tracker.reads

        let buffer = TUIkitView.renderToBuffer(content, context: renderContext)

        let readVolatile = tracker.reads > readsBefore
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
        if !context.isMeasuring && buffer.hitTestRegions.isEmpty && buffer.overlays.isEmpty && !readVolatile {
            cache.store(
                identity: identity, view: element, buffer: buffer,
                contextWidth: context.availableWidth, contextHeight: context.availableHeight)
        }
        return buffer
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let cache = context.environment.renderCache else {
            return measureChild(content, proposal: proposal, context: context)
        }
        let key = RenderCache.SizeKey(
            identity: context.identity,
            proposalWidth: proposal.width, proposalHeight: proposal.height,
            availableWidth: context.availableWidth, availableHeight: context.availableHeight,
            hasExplicitWidth: context.hasExplicitWidth, hasExplicitHeight: context.hasExplicitHeight)
        if let cached = cache.lookupSize(key: key, view: element) {
            return cached
        }
        let size = measureChild(content, proposal: proposal, context: context)
        cache.storeSize(key: key, view: element, size: size)
        return size
    }
}
