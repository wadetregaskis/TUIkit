//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollDisabled.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Scroll adjustability

private struct ScrollEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the **user** may move the scroll position of the scrollables in
    /// this subtree.
    ///
    /// Set by ``TUIkit/View/scrollDisabled(_:)``. Scrollables capture it each
    /// render onto their persistent handler, so event-time code (a wheel tick, a
    /// scrollbar drag) can consult it when the environment is out of reach.
    ///
    /// Programmatic movement ignores this entirely — see the modifier.
    public var isScrollEnabled: Bool {
        get { self[ScrollEnabledKey.self] }
        set { self[ScrollEnabledKey.self] = newValue }
    }
}

extension View {
    /// Disables (or re-enables) the user's ability to scroll the scrollables in
    /// this subtree.
    ///
    /// This governs *gestures* — the wheel and trackpad, the scrollbar's arrows,
    /// track and thumb, the scroll keys (arrows, Page Up/Down, Home/End) when a
    /// `ScrollView` holds focus, and drag auto-scroll. **Programmatic movement
    /// is unaffected**: a `ScrollViewProxy.scrollTo(_:)`, a scroll anchor, and
    /// the reveal that keeps a focused control or a selected row on screen all
    /// still work. A `List` or `Table` therefore still follows its selection
    /// under the arrow keys — moving a cursor is not adjusting a scroll
    /// position, and a list whose selection could leave the viewport for good
    /// would be unusable.
    ///
    /// The scroll chrome stays visible and is drawn in a disabled state, so the
    /// view still reads as scrollable content that happens to be pinned rather
    /// than as content that mysteriously has no more of itself. A `ScrollView`
    /// with no scroll commands left does drop out of the focus ring, since a Tab
    /// stop that can do nothing is just an obstacle.
    ///
    /// A blocked wheel tick is **not consumed**, so it chains to the enclosing
    /// scroller exactly as a tick at a scroller's own edge does — a pinned inner
    /// pane doesn't trap the wheel over the page behind it.
    ///
    /// ```swift
    /// ScrollView {
    ///     LogLines(entries)
    /// }
    /// .scrollDisabled(isPinned)
    /// ```
    ///
    /// Unlike ``View/disabled(_:)``, this is **not** additive: a nested
    /// `.scrollDisabled(false)` re-enables scrolling for its own subtree, which
    /// matches SwiftUI. Use `.disabled(_:)` when you mean "this whole region is
    /// inert".
    ///
    /// - Parameter disabled: Whether to prevent user scrolling.
    /// - Returns: A view whose scrollables ignore user scroll input.
    public func scrollDisabled(_ disabled: Bool) -> some View {
        environment(\.isScrollEnabled, !disabled)
    }
}
