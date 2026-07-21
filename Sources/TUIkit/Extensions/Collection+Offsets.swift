//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Collection+Offsets.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Offset-based mutation

// The primitives a `ForEach(...).onMove`/`.onDelete` closure calls on the data
// binding, matching SwiftUI's signatures exactly so the same call site compiles
// against either framework:
//
//     ForEach(items) { … }
//         .onMove   { items.move(fromOffsets: $0, toOffset: $1) }
//         .onDelete { items.remove(atOffsets: $0) }
//
// The handlers deal in *offsets from the start* (an `IndexSet`), because a
// `List` row's ordinal is its distance from row 0 — not its collection `Index`
// (which for a non-`Int`-indexed collection needn't be an integer at all). Both
// helpers translate those offsets to real indices before mutating.
//
// Constraint note — why not the bare `RangeReplaceableCollection` SwiftUI uses:
// on Apple platforms a Foundation⇄SwiftUI *cross-import overlay* makes SwiftUI's
// own `move(fromOffsets:toOffset:)` / `remove(atOffsets:)` (declared on
// `RangeReplaceableCollection where Self: MutableCollection`) VISIBLE to overload
// resolution the instant `Foundation` is imported — even though `SwiftUI` is
// never imported and, being in SwiftUICore, cannot be linked into a plain
// executable ("not an allowed client of it"). An unconstrained TUIkit extension
// loses that overload race to SwiftUI's more-specialised one, and the resulting
// call links against an unavailable symbol. Adding `Self.Index == Int` makes the
// TUIkit overloads STRICTLY more specialised than SwiftUI's, so ours win for the
// int-indexed collections that back a `List`/`ForEach` (`Array`, `ContiguousArray`,
// `ArraySlice`) and link cleanly. Off Apple platforms there is no overlay and the
// constraint is simply harmless.

extension RangeReplaceableCollection where Self: MutableCollection, Self.Index == Int {
    /// Removes the elements at the given offsets from the start of the
    /// collection. Mirrors SwiftUI's `remove(atOffsets:)`.
    ///
    /// Offsets are measured from ``startIndex`` (row 0), so they compose
    /// directly with a `List`/`ForEach` row ordinal. Out-of-range offsets are
    /// ignored rather than trapping — a delete racing an async reload that
    /// already shrank the data must not crash.
    ///
    /// - Parameter offsets: The offsets of the elements to remove.
    public mutating func remove(atOffsets offsets: IndexSet) {
        // Rebuild keeping only the elements whose offset isn't in the set.
        let kept = enumerated().lazy
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        self = Self(kept)
    }

    /// Moves the elements at the given offsets to just before the element at
    /// the destination offset. Mirrors SwiftUI's `move(fromOffsets:toOffset:)`.
    ///
    /// `destination` is the offset the moved block should end up *in front of*,
    /// measured against the collection **before** the move — so moving row 0 to
    /// the very end uses `toOffset: count`. This is the exact convention
    /// SwiftUI's `onMove` closure hands you, so the pass-through
    /// `move(fromOffsets:toOffset:)` call is a no-op translation.
    ///
    /// Offsets outside the collection are dropped and an out-of-range
    /// destination is clamped, so a stale drag can't trap.
    ///
    /// - Parameters:
    ///   - source: The offsets of the elements to move.
    ///   - destination: The offset to insert the moved elements before.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let all = Array(self)
        let sourceOffsets = source.filter { $0 >= 0 && $0 < all.count }
        guard !sourceOffsets.isEmpty else { return }
        let clampedDestination = Swift.max(0, Swift.min(destination, all.count))

        // The moved block, in its original relative order.
        let moved = sourceOffsets.map { all[$0] }
        // Everything else, and where the destination lands once the moved
        // elements are pulled out: every removed offset strictly below the
        // destination shifts it left by one.
        let sourceSet = Set(sourceOffsets)
        var remaining: [Element] = []
        remaining.reserveCapacity(all.count - moved.count)
        var insertAt = clampedDestination
        for (offset, element) in all.enumerated() {
            if sourceSet.contains(offset) {
                if offset < clampedDestination { insertAt -= 1 }
            } else {
                remaining.append(element)
            }
        }
        remaining.insert(contentsOf: moved, at: Swift.max(0, Swift.min(insertAt, remaining.count)))
        self = Self(remaining)
    }
}
