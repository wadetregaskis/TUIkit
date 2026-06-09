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
    @usableFromInline let value: Any
    @usableFromInline let isEqual: (Any) -> Bool

    public init<E: Equatable>(_ value: E) {
        self.value = value
        self.isEqual = { ($0 as? E) == value }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isEqual(rhs.value)
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
        if buffer.hitTestRegions.isEmpty && buffer.overlays.isEmpty && !readVolatile {
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
