//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ErasedChainSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit

/// An `AnyView` of a stack holding an `AnyView` of a stack …, `depth` levels
/// over a leaf, and every level of it: `levels[0]` is the leaf, `levels.last`
/// the whole chain. Built by a loop, so no stack is needed to build it however
/// deep it is — which is the point: a value deeper than any stack can walk.
///
/// Every level is kept so the chain can be released from the top, one level at
/// a time (``releaseFromTheTop(_:)``). Dropped as one value, the chain frees
/// each box from inside the one before, recursively, and a chain this deep
/// overflows the stack in its own deinitialisation.
@MainActor
func erasedChain(depth: Int) -> [AnyView] {
    var levels = [AnyView(Text("leaf"))]
    levels.reserveCapacity(depth + 1)
    for _ in 0..<depth {
        let inner = levels[levels.count - 1]
        levels.append(AnyView(VStack { Text("level"); inner }))
    }
    return levels
}

/// Releases an ``erasedChain(depth:)`` from its top level down, so each box
/// freed finds the one below it still held by `levels`, and nothing recurses.
@MainActor
func releaseFromTheTop(_ levels: inout [AnyView]) {
    while !levels.isEmpty { levels.removeLast() }
}
