//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EquatableView.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - EquatableView

/// A wrapper that enables subtree memoization for views conforming to `Equatable`.
///
/// When TUIKit renders an `EquatableView`, it compares the current content with
/// the previously cached value. If the content is unchanged **and** the available
/// size hasn't changed, the cached ``FrameBuffer`` is returned immediately —
/// skipping the entire subtree rendering.
///
/// ## Usage
///
/// Apply `.equatable()` to any `Equatable` view:
///
/// ```swift
/// struct ScoreDisplay: View, Equatable {
///     let name: String
///     let score: Int
///
///     var body: some View {
///         VStack {
///             Text(name)
///             Text("Score: \(score)")
///         }
///     }
/// }
///
/// // In a parent view:
/// ScoreDisplay(name: "Player 1", score: 42).equatable()
/// ```
///
/// When `name` and `score` are unchanged between frames, the `VStack` and both
/// `Text` views are never re-rendered — the cached buffer is returned directly.
///
/// ## When to Use
///
/// - **Large static subtrees** — views with many children that rarely change
/// - **Expensive rendering** — views whose `body` or `renderToBuffer` is costly
/// - **Animation siblings** — static views next to animated ones
///
/// ## When NOT to Use
///
/// - Views that read `@State` directly (state lives in a reference-type box,
///   so the view struct compares as equal even when state changed)
/// - Views that change every frame (the cache overhead adds no value)
/// - Views that depend on environment values that change frequently
/// - Views containing interactive elements (Button, Toggle, Slider, …) or
///   animating ones (Spinner, an indeterminate ProgressView): these are
///   detected — hit-test regions/overlays in the buffer, volatile reads, and
///   animation requests all decline the cache — so the wrapper is *safe*, it
///   just buys nothing there.
///
/// ## Cache Invalidation
///
/// The render cache is selectively cleared when `@State` values change:
/// only cache entries in the ancestor/descendant path of the changed state
/// are invalidated. Sibling subtrees retain their cached buffers.
/// Pulse animation changes do **not** invalidate the cache, which is why
/// subtrees containing focused interactive views should not be wrapped.
///
/// - SeeAlso: ``View/equatable()``
public struct EquatableView<Content: View & Equatable>: View {
    /// The wrapped view content.
    let content: Content

    /// Creates an equatable view wrapping the given content.
    ///
    /// - Parameter content: The equatable view to memoize.
    public init(content: Content) {
        self.content = content
    }

    public var body: Never {
        fatalError("EquatableView is a primitive view")
    }
}

// MARK: - Rendering

extension EquatableView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let cache = context.renderCache!
        let identity = context.identity

        cache.markActive(identity)

        // Cache hit: view unchanged and context size matches
        if let cached = cache.lookup(
            identity: identity,
            view: content,
            contextWidth: context.availableWidth,
            contextHeight: context.availableHeight
        ) {
            // Still need to run hydration for @State properties inside
            // the cached subtree, so they stay active for GC.
            // But we skip the actual rendering work.
            markSubtreeActive(context: context)
            return cached
        }

        // Cache miss: render under a volatile-read tracker (reusing an
        // ancestor's, so nesting bubbles up) and only store buffers that are
        // safe to serve again — the same gate as `_MemoizedRow`:
        //   • never a measure-pass buffer (incomplete: interactive controls
        //     suppress their hit-test regions while measuring — and it would
        //     clobber the render-pass entry at a different size every frame);
        //   • never an interactive subtree (its regions/overlays capture
        //     per-frame handler state, and a focused control pulses);
        //   • never a time-varying subtree (a pulse-phase read or an animation
        //     request means the next frame differs even though the value
        //     compares equal — a cached Spinner would freeze, issue #1).
        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        let renderContext =
            existingTracker == nil
            ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
            : context
        let unsafeBefore = tracker.cacheUnsafeCount
        // See _MemoizedRow: a state write during this render invalidates
        // first, so storing afterwards would resurrect the pre-write buffer.
        let clearsBefore = cache.stats.subtreeClears

        let buffer = TUIkitView.renderToBuffer(content, context: renderContext)

        let readVolatile = tracker.cacheUnsafeCount > unsafeBefore
        if !context.isMeasuring && buffer.hitTestRegions.isEmpty && buffer.overlays.isEmpty
            && !readVolatile && cache.stats.subtreeClears == clearsBefore
        {
            cache.store(
                identity: identity,
                view: content,
                buffer: buffer,
                contextWidth: context.availableWidth,
                contextHeight: context.availableHeight
            )
        }

        return buffer
    }
}

// MARK: - Layout

extension EquatableView: Layoutable {
    /// Measures the wrapped content, memoizing the result by the content's
    /// *value* (`Equatable.==`) — the size twin of the buffer cache in
    /// `renderToBuffer`.
    ///
    /// Two-pass layout measures the same subtree repeatedly, and across frames a
    /// static subtree measures to the same size every time. Because the cache is
    /// keyed by the whole view value (not just identity), a hit means identical
    /// content — and therefore, between cache invalidations (which also bound
    /// the environment changes a measure could depend on), an identical size.
    /// That value comparison is exactly why this is safe where an
    /// identity-keyed measure memo is not. The cache shares `RenderCache`'s
    /// lifecycle: cleared on `@State`/global-environment change, GC'd with the
    /// buffer entries. When no cache is present (standalone measurement) this
    /// forwards straight to the content, uncached.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let cache = context.renderCache else {
            return measureChild(content, proposal: proposal, context: context)
        }
        // A measured view is in the tree just as a rendered one is — same
        // GC contract as `_MemoizedRow.sizeThatFits`: without this, a view
        // that a frame only measures had its size entries pruned by
        // `removeInactive` every pass and missed the memo every frame.
        cache.markActive(context.identity)
        let key = RenderCache.SizeKey(
            identity: context.identity,
            proposalWidth: proposal.width,
            proposalHeight: proposal.height,
            availableWidth: context.availableWidth,
            availableHeight: context.availableHeight,
            hasExplicitWidth: context.hasExplicitWidth,
            hasExplicitHeight: context.hasExplicitHeight)
        if let cached = cache.lookupSize(key: key, view: content) {
            return cached
        }
        let size = measureChild(content, proposal: proposal, context: context)
        cache.storeSize(key: key, view: content, size: size)
        return size
    }
}

// MARK: - Private Helpers

extension EquatableView {
    /// Marks the content's identity as active in StateStorage for GC.
    ///
    /// When returning a cached buffer, the subtree's views aren't visited.
    /// Their state identities must still be marked active to prevent
    /// StateStorage from garbage-collecting them.
    fileprivate func markSubtreeActive(context: RenderContext) {
        context.environment.stateStorage!.markActive(context.identity)
    }
}

// MARK: - View Extension

extension View where Self: Equatable {
    /// Wraps this view in an ``EquatableView`` for subtree memoization.
    ///
    /// When the view's properties are unchanged between frames, the entire
    /// subtree is skipped and the cached rendering result is reused.
    ///
    /// ```swift
    /// struct MyView: View, Equatable {
    ///     let title: String
    ///     var body: some View { Text(title) }
    /// }
    ///
    /// MyView(title: "Hello").equatable()
    /// ```
    ///
    /// - Returns: An ``EquatableView`` wrapping this view.
    public func equatable() -> EquatableView<Self> {
        EquatableView(content: self)
    }
}
