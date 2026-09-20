//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnGeometryChangeModifier.swift
//
//  Reports something derived from a view's own geometry, whenever it changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Calls `action` with a value derived from this view's geometry, whenever
    /// that value changes.
    ///
    /// The difference from ``GeometryReader`` is which view's geometry you get,
    /// and it is the whole point. A reader is GREEDY — it fills what it was
    /// offered, because it has to know its size before it can build the content
    /// that would otherwise determine it — so wrapping something in one to
    /// measure it changes the layout you were trying to measure. This measures
    /// the view as it actually laid out and leaves it exactly where it was.
    ///
    /// ```swift
    /// Text(article.body)
    ///     .onGeometryChange(for: Int.self) { $0.size.height } { rows in
    ///         visibleRows = rows
    ///     }
    /// ```
    ///
    /// The action fires on the first render as well as on changes — a report
    /// that only ever arrived on the second size would leave an app that never
    /// resizes knowing nothing. It runs on the render pass only, so a measure
    /// (of which there are several per frame) cannot fire it.
    ///
    /// What a terminal `GeometryProxy` can answer is `size` and a `.local`
    /// frame; `.global` is exact only where the renderer knows where the view
    /// sits (see ``GeometryProxy/hasGlobalPosition``). `transform` runs against
    /// that, so a value derived from a `.global` frame inherits the same
    /// caveat.
    ///
    /// - Parameters:
    ///   - type: The type of the derived value, stated so the closure's return
    ///     type is unambiguous — SwiftUI's spelling.
    ///   - transform: Derives the value from the view's geometry.
    ///   - action: Receives the new value.
    /// - Returns: A view that reports its geometry.
    public func onGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> some View {
        OnGeometryChangeModifier(content: self, transform: transform) { _, new in action(new) }
    }

    /// Calls `action` with the old and the new value whenever a value derived
    /// from this view's geometry changes.
    ///
    /// The two-argument form of ``onGeometryChange(for:of:action:)``. On the
    /// first render the old and new values are the same, as `onChange`'s
    /// `initial` does.
    ///
    /// - Parameters:
    ///   - type: The type of the derived value.
    ///   - transform: Derives the value from the view's geometry.
    ///   - action: Receives the previous and the new value.
    /// - Returns: A view that reports its geometry.
    public func onGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        OnGeometryChangeModifier(content: self, transform: transform, action: action)
    }
}

// MARK: - Modifier

/// Renders `content` unchanged and reports a value derived from the size it
/// came out at.
struct OnGeometryChangeModifier<Content: View, T: Equatable>: View {
    let content: Content
    let transform: (GeometryProxy) -> T
    let action: (T, T) -> Void

    var body: Never {
        fatalError("OnGeometryChangeModifier renders via Renderable")
    }
}

extension OnGeometryChangeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure pass must not fire the action — there are several per frame
        // and they are asking a question, not laying anything out. Same rule
        // (and the same reason) as `OnChangeModifier`.
        guard !context.isMeasuring, let storage = context.stateStorage else {
            return TUIkit.renderToBuffer(content, context: context)
        }

        // Declared as a render side effect for the reason `onChange` declares
        // one: the comparison is per-frame work a cached buffer cannot
        // reproduce, so a value-memoized subtree containing this would compare
        // once and then never notice another change.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // Allocated, not fixed: the tracked-value dictionary is shared with
        // onChange and onPreferenceChange at this same identity, and they claim
        // indices from the per-identity counter. A fixed 0 here landed on the
        // first sibling's slot; the per-frame overwrite read back as "no
        // previous value" on their side, so a real change fired nothing.
        //
        // Claimed BEFORE the content renders, not after: an index claimed after
        // is the count of claimants the CONTENT contributed at this same
        // identity, and an `if` without `else` (or an `AnyView`) changes that
        // between frames — both render at the parent identity. The observer
        // then moved onto a vanished sibling's slot and read its value as its
        // own previous geometry. Claiming first makes the index depend only on
        // the chain above, which is body order and the same every frame.
        let key = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: storage.nextOnChangeIndex(for: context.identity))

        let buffer = TUIkit.renderToBuffer(content, context: context)
        // The view's OWN size — what its content actually came out at, not what
        // was offered. That is the whole difference from `GeometryReader`.
        let value = transform(GeometryProxy(width: buffer.width, height: buffer.height))
        let previous: T? = storage.trackedValue(for: key)
        storage.setTrackedValue(value, for: key)
        // Manual tracked values are pruned unless the identity is marked — see
        // the same call in `OnChangeModifier`.
        storage.markActive(context.identity)

        if let previous {
            if previous != value { action(previous, value) }
        } else {
            action(value, value)
        }
        return buffer
    }
}

extension OnGeometryChangeModifier: Layoutable {
    /// Measures as its content: reporting is the whole of this modifier's
    /// effect, and it contributes no geometry.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension OnGeometryChangeModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}
