//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RetainedSubtreeIndexTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// `RetainedSubtreeIndex.retains` must answer exactly what
/// `roots.contains { $0.isAncestor(of:) }` answers — the walk it replaces —
/// on trees with shared prefixes, keyed and branched steps, roots at several
/// depths, and identities equal to a root (not retained: strict ancestry).
@Suite("The retained-subtree index answers the ancestor walk")
struct RetainedSubtreeIndexTests {

    private enum Alpha {}
    private enum Beta {}
    private enum Gamma {}

    /// A little forest: every identity reachable in a few steps from one root.
    private static func forest() -> [ViewIdentity] {
        let root = ViewIdentity(rootType: Alpha.self)
        var all: [ViewIdentity] = [root]
        for index in 0..<4 {
            let child = root.child(type: Beta.self, index: index)
            all.append(child)
            for key in ["x", "y", "z"] {
                let keyed = child.child(erasedType: Gamma.self, key: key)
                all.append(keyed)
                all.append(keyed.branch("true"))
                all.append(keyed.child(type: Alpha.self, index: 0).child(type: Beta.self, index: 1))
            }
        }
        return all
    }

    @Test("Every (roots, identity) pair agrees with the naive walk")
    func agreesWithTheWalk() {
        let forest = Self.forest()
        var generator = SplitMix(seed: 0x5EED)
        for _ in 0..<40 {
            let roots = forest.filter { _ in generator.next().isMultiple(of: 5) }
            var index = RetainedSubtreeIndex(roots: roots)
            for identity in forest {
                let expected = roots.contains { $0.isAncestor(of: identity) }
                let actual = index.retains(identity)
                #expect(actual == expected, "\(roots.map(\.path)) vs \(identity.path)")
            }
        }
        var empty = RetainedSubtreeIndex(roots: [])
        let emptyAnswer = empty.retains(forest[3])
        #expect(!emptyAnswer)

        // Raw-rooted identities: ancestry is a path prefix, and the index
        // must answer as the walk does for them too.
        let raw = ["a", "a/b", "a/b/c", "a/bc", "x/b/c"].map { ViewIdentity(path: $0) }
        for root in raw {
            var index = RetainedSubtreeIndex(roots: [root])
            for identity in raw {
                let actual = index.retains(identity)
                #expect(actual == root.isAncestor(of: identity), "\(root.path) vs \(identity.path)")
            }
        }
        #expect(RetainedSubtreeIndex(roots: []).isEmpty)
    }

    /// A tiny deterministic generator, so the forests are the same each run.
    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
