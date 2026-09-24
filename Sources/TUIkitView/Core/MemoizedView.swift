//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoizedView.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Memoizing by a caller-supplied token

/// A view that reuses its previous rendering while a caller-supplied token is
/// unchanged.
///
/// The token counterpart to ``EquatableView``. `.equatable()` proves a subtree
/// is unchanged by comparing the view value with `==`; this one takes the
/// caller's word for it, which is the only option available to a view that
/// cannot reasonably be `Equatable` — one holding a closure (every `Button`
/// action), an `AnyView`, or anything else whose equality is not decidable.
///
/// - Important: Framework infrastructure. Use ``View/memoized(id:)``.
public struct _MemoizedView<Content: View, ID: Hashable>: View {
    /// What the caller says the appearance is a function of.
    let id: ID

    /// The subtree whose rendering is reused while ``id`` holds.
    let content: Content

    /// Creates a token-memoized view.
    public init(id: ID, content: Content) {
        self.id = id
        self.content = content
    }

    /// The whole mechanism, in one line: two of these are "the same view" when
    /// the caller's token matches, whatever the content happens to be.
    ///
    /// `Content` is deliberately NOT compared. It usually cannot be — that is
    /// the reason this type exists — and comparing what part of it can be would
    /// be worse than not comparing at all: a promise that holds sometimes reads
    /// as a guarantee.
    public var body: Never {
        fatalError("_MemoizedView renders via Renderable")
    }
}

// `@preconcurrency`, as every other `Equatable` view in the tree declares it:
// `View` is `@MainActor`, so the conformance crosses isolation. Comparing two
// tokens touches nothing isolated, and this is the same spelling
// `FlexibleFrameView`, `OverlayModifier` and the rest already use.
extension _MemoizedView: @preconcurrency Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: - Rendering

// `Renderable` rather than a real `body`, so this wrapper adds NO level to the
// render identity. A composite body would append `V.Body.self` via
// `withChildIdentity`, which re-keys every `@State` slot beneath it — so adding
// or removing `.memoized(id:)` would silently reset the state of the subtree it
// was meant only to speed up. `EquatableView` is `Renderable` for the same
// reason.
extension _MemoizedView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: context)
    }
}

extension _MemoizedView: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - View Extension

extension View {
    /// Reuses this view's previous rendering for as long as `id` is unchanged.
    ///
    /// For a subtree that is expensive to draw and rarely changes. Where the
    /// view can be `Equatable`, prefer ``View/equatable()``: it *proves* the subtree
    /// is unchanged, where this *believes* you.
    ///
    /// ```swift
    /// ExpensiveChart(samples: samples)
    ///     .memoized(id: samples.count)
    /// ```
    ///
    /// # What the token has to cover
    ///
    /// Everything the subtree's appearance depends on that the framework cannot
    /// see for itself. A token that misses something leaves the old picture on
    /// screen — wrong pixels, and no error. The framework still invalidates the
    /// entry for the things it *can* see: a `@State` write, an `@Observable`
    /// read, an environment value applied by a modifier, and a change in the
    /// space the view is offered.
    ///
    /// # What is never reused
    ///
    /// The same rules ``EquatableView`` obeys, so an unsafe subtree is refused
    /// rather than served wrongly:
    ///
    /// * anything interactive — a buffer carrying hit-test regions, because
    ///   those hold handler registrations belonging to the frame that made them;
    /// * anything with overlays, for the same reason;
    /// * anything time-varying — a subtree that read the animation clock or the
    ///   pulse phase would freeze on the frame it was cached;
    /// * a measure pass, which draws an incomplete picture on purpose.
    ///
    /// The practical consequence is that a row containing a `Button` is not
    /// memoized today. That is a real limit, not an oversight, and it is why
    /// this is worth reaching for around expensive *presentation* rather than
    /// around controls.
    ///
    /// # Memory
    ///
    /// One rendered buffer per memoized identity, released when the view leaves
    /// the tree. A subtree scrolled out of view is dropped like any other, so
    /// this speeds up a view that stays put and changes rarely — it does not
    /// make scrolling back to an off-screen row free.
    ///
    /// - Parameter id: What this subtree's appearance is a function of.
    /// - Returns: A view that reuses its rendering while `id` holds.
    public func memoized<ID: Hashable>(id: ID) -> EquatableView<_MemoizedView<Self, ID>> {
        EquatableView(content: _MemoizedView(id: id, content: self))
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _MemoizedView: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _MemoizedView: DrawsContentUnchanged {}
