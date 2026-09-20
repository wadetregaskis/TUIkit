//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EquatableView.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - EquatableView

/// A wrapper that enables subtree memoization for views conforming to `Equatable`.
///
/// When TUIkit renders an `EquatableView`, it compares the current content with
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
    /// Memoized by the whole VIEW value, through the shared value memo — see
    /// `renderValueMemoized(key:viewType:context:render:)`.
    ///
    /// The soundness argument is this type's own, and it is the strong form: the
    /// key IS the view, so a hit means the very thing that would have been
    /// rendered compares equal. `_MemoizedRow`, the other caller, keys on a
    /// `ForEach` element instead and so claims something weaker — that the row is
    /// a pure function of that element — which is why the argument lives here and
    /// at that type rather than once in the shared code.
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderValueMemoized(
            key: content, viewType: Content.self, context: context
        ) { TUIkitView.renderToBuffer(content, context: $0) }
    }
}

// MARK: - Layout

extension EquatableView: Layoutable {
    /// Measures the wrapped content, memoized by the content's *value*
    /// (`Equatable.==`) — the size twin of the buffer memo above, and the same
    /// shared implementation.
    ///
    /// Two-pass layout measures the same subtree repeatedly, and across frames a
    /// static subtree measures to the same size every time. Because the memo is
    /// keyed by the whole view value (not just identity), a hit means identical
    /// content — and therefore, between cache invalidations (which also bound the
    /// environment changes a measure could depend on), an identical size. That
    /// value comparison is exactly why this is safe where an identity-keyed
    /// measure memo is not.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureValueMemoized(key: content, proposal: proposal, context: context) {
            measureChild(content, proposal: proposal, context: $0)
        }
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

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension EquatableView: SingleContentWrapper {
    public var wrappedContent: Content { content }
}
