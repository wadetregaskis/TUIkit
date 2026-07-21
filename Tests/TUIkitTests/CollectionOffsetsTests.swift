//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CollectionOffsetsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@Suite("Collection offset mutations")
struct CollectionOffsetsTests {

    // MARK: - remove(atOffsets:)

    @Test("Removes a single offset")
    func removeSingle() {
        var items = ["a", "b", "c", "d"]
        items.remove(atOffsets: IndexSet(integer: 1))
        #expect(items == ["a", "c", "d"])
    }

    @Test("Removes several non-contiguous offsets in one pass")
    func removeMultiple() {
        var items = [0, 1, 2, 3, 4, 5]
        items.remove(atOffsets: IndexSet([0, 2, 5]))
        #expect(items == [1, 3, 4])
    }

    @Test("An empty offset set leaves the collection unchanged")
    func removeEmpty() {
        var items = ["x", "y"]
        items.remove(atOffsets: IndexSet())
        #expect(items == ["x", "y"])
    }

    @Test("Out-of-range offsets are ignored, not trapped")
    func removeOutOfRange() {
        var items = [1, 2, 3]
        items.remove(atOffsets: IndexSet([1, 99]))
        #expect(items == [1, 3])
    }

    // MARK: - move(fromOffsets:toOffset:)

    @Test("Moves one element downward (SwiftUI destination convention)")
    func moveDown() {
        // Move "a" (offset 0) to just before the element now at offset 2.
        var items = ["a", "b", "c", "d"]
        items.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(items == ["b", "a", "c", "d"])
    }

    @Test("Moves one element to the very end with toOffset == count")
    func moveToEnd() {
        var items = ["a", "b", "c"]
        items.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(items == ["b", "c", "a"])
    }

    @Test("Moves one element upward")
    func moveUp() {
        var items = ["a", "b", "c", "d"]
        items.move(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        #expect(items == ["a", "d", "b", "c"])
    }

    @Test("Moves a contiguous block, preserving relative order")
    func moveBlock() {
        var items = [0, 1, 2, 3, 4]
        // Move offsets {1,2} to before offset 4.
        items.move(fromOffsets: IndexSet([1, 2]), toOffset: 4)
        #expect(items == [0, 3, 1, 2, 4])
    }

    @Test("Moves non-contiguous offsets, collapsing them together in order")
    func moveNonContiguous() {
        var items = ["a", "b", "c", "d", "e"]
        // Move {0, 4} to before offset 2 → they gather in original order.
        items.move(fromOffsets: IndexSet([0, 4]), toOffset: 2)
        #expect(items == ["b", "a", "e", "c", "d"])
    }

    @Test("A no-op move (destination inside the source's own gap) is stable")
    func moveNoOp() {
        var items = ["a", "b", "c"]
        items.move(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(items == ["a", "b", "c"])
        items.move(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        #expect(items == ["a", "b", "c"])
    }

    @Test("An empty source set leaves the collection unchanged")
    func moveEmpty() {
        var items = [1, 2, 3]
        items.move(fromOffsets: IndexSet(), toOffset: 0)
        #expect(items == [1, 2, 3])
    }

    @Test("An over-range destination clamps to the end instead of trapping")
    func moveClampsDestination() {
        var items = ["a", "b", "c"]
        items.move(fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(items == ["b", "c", "a"])
    }
}
