//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Identity.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Splices a keyed step into the wrapped content's structural identity, so
/// changing the key gives the subtree a fresh identity. It carries no visual
/// effect (`modify` returns the buffer unchanged) — only `adjustContext`
/// re-keys, and because `ModifiedView` calls `adjustContext` on **both** the
/// measure and render passes, `@State` keys off the same spliced identity in
/// each, preserving measure/render alignment.
private struct _IDModifier: ViewModifier {
    let key: String

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        buffer
    }

    func adjustContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(erasedType: Self.self, key: key)
    }
}

extension View {
    /// Binds an explicit identity to this view.
    ///
    /// Mirrors SwiftUI's `id(_:)`. When `id` changes, the view is treated as a
    /// *different* view: its `@State` resets to its initial values, its
    /// `onAppear`/`task` fire again, and its cached buffer is discarded — all of
    /// which fall out automatically from the identity change, since `@State`,
    /// lifecycle tokens, and the render cache all key off the structural
    /// identity path.
    ///
    /// ```swift
    /// ProfileView(user: user)
    ///     .id(user.id)   // switching users restarts the subtree
    /// ```
    ///
    /// - Note: `.id()` re-keys only what sits *below* it in the modifier chain,
    ///   matching SwiftUI: put it outermost (`content.onAppear{…}.id(k)`) so the
    ///   whole subtree, including its lifecycle, resets on a key change. The
    ///   `Hashable` id is collapsed to `String(describing:)` for the key (as
    ///   `ForEach` does), so two distinct values with identical descriptions
    ///   would alias one identity.
    ///
    /// - Parameter id: A value that identifies this view.
    /// - Returns: A view with the given identity bound to it.
    public func id<ID: Hashable>(_ id: ID) -> some View {
        modifier(_IDModifier(key: String(describing: id)))
    }
}
