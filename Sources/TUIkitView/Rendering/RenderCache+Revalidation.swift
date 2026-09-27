//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Revalidation.swift
//
//  What a render cache keeps to re-check a row instead of dropping it.
//
//  Option C serves a memoized row after a parent's write when the row's
//  rebuilt value and its environment compare equal to what it was drawn
//  from. Everything the cache keeps for that lives in one object, held in one
//  stored property of the cache, so each piece added is a field here and not
//  another stored property on a class already at its file's length ceiling.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The cache's state for re-checking rows.
///
/// A class held by a `let`: reading a field reaches it through a pointer the
/// cache never reassigns. Main-actor only, as the cache's tables are.
package final class RevalidationState {
    /// What each row type can hold, walked once per type: whether a row of it
    /// can be re-checked by its value at all. See ``TypeWalk``.
    package var typeWalk = TypeWalk()

    package init() {}
}
