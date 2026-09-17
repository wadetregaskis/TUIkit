//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InternedIDTable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Interned ID Table

/// A table of ids interned per view identity, pruned along with the render
/// cache.
///
/// One implementor: the mouse event dispatcher, which mints a handler id per
/// `(identity, slot)` so a control keeps its own id from frame to frame instead
/// of taking whatever number its position in the walk left it.
///
/// Such a table has to live exactly as long as the cache entries that can serve
/// a buffer carrying its ids. A `FrameBuffer` stores its hit-test regions with
/// the ids baked in, so a cached buffer served again needs its control's id to
/// still mean that control — and an id dropped while such an entry survives
/// would leave the served regions pointing at a handler no one registers.
/// ``RenderCache/removeInactive()`` therefore prunes this table with the same
/// retention rule it prunes itself by, rather than the table guessing from its
/// own frame counting.
///
/// A class, and held weakly by the cache: the dispatcher owns itself, and its
/// `TUIContext` owns both.
package protocol InternedIDTable: AnyObject {
    /// Drops every interned id whose identity neither asked for it since the
    /// last prune nor is retained.
    ///
    /// - Parameter isRetained: Whether a cached subtree still covers this
    ///   identity, even though nothing under it was visited this pass — the
    ///   cache's own ``RetainedSubtreeIndex`` question.
    func pruneInternedIDs(retaining isRetained: (ViewIdentity) -> Bool)
}
