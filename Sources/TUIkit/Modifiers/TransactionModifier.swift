//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransactionModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension View {
    /// Changes the ``Transaction`` this view's subtree renders under.
    ///
    /// The subtree-shaped counterpart to ``withTransaction(_:_:)``: that one
    /// scopes a transaction to *a change*, this one to *a place*. Most usefully,
    /// it is how part of the tree opts out of an animation the rest of it wants:
    ///
    /// ```swift
    /// VStack {
    ///     Header(count: items.count)
    ///         .transaction { $0.disablesAnimations = true }   // snaps
    ///     ItemList(items)                                     // slides
    /// }
    /// ```
    ///
    /// - Parameter transform: Receives the inherited transaction and modifies it
    ///   in place. It runs on both the measure and the render walk, so it must
    ///   be a pure function of the value it is handed.
    /// - Returns: A view whose subtree sees the transformed transaction.
    public func transaction(
        _ transform: @escaping (inout Transaction) -> Void
    ) -> some View {
        transformEnvironment(\.transaction, transform: transform)
    }
}
