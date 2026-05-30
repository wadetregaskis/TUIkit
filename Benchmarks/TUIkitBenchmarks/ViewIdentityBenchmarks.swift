//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewIdentityBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks for `ViewIdentity` path construction and
/// ancestry queries.
///
/// `ViewIdentity` is the string-path key that the state-
/// storage and focus systems use to keep `@State` stable
/// across render passes. A fresh identity is derived for every
/// node on every render (root → child → child …), so path
/// construction sits on the per-frame hot path and its
/// allocation profile matters. `isAncestor(of:)` backs
/// subtree queries (e.g. focus containment). It's a `Hashable`
/// value type with no isolation, so it runs off the main
/// actor.
enum ViewIdentityBenchmarks {

    static func register() {
        registerPathConstruction()
        registerAncestry()
    }

    // MARK: - Test inputs

    /// Marker types used purely to feed `child(type:)` a stream
    /// of distinct type names, mirroring a real view tree's mix
    /// of node types.
    private struct NodeA {}
    private struct NodeB {}
    private struct NodeC {}

    private static let depth = 16

    private static let ancestor = ViewIdentity(path: "Root/0:Stack/1:List/2:Row")
    private static let descendant = ViewIdentity(
        path: "Root/0:Stack/1:List/2:Row/3:Cell/4:Button/5:Label"
    )

    // MARK: - Path construction

    private static func registerPathConstruction() {
        Benchmark("identity/build path — 16 levels") { benchmark in
            for _ in benchmark.scaledIterations {
                var identity = ViewIdentity(rootType: NodeA.self)
                for level in 0..<depth {
                    switch level % 3 {
                    case 0: identity = identity.child(type: NodeA.self, index: level)
                    case 1: identity = identity.child(type: NodeB.self, index: level)
                    default: identity = identity.child(type: NodeC.self, index: level)
                    }
                }
                blackHole(identity)
            }
        }

        Benchmark("identity/child + branch — 16 levels") { benchmark in
            for _ in benchmark.scaledIterations {
                var identity = ViewIdentity(rootType: NodeA.self)
                for level in 0..<depth {
                    identity = identity.child(type: NodeB.self, index: level)
                    identity = identity.branch(level.isMultiple(of: 2) ? "#true" : "#false")
                }
                blackHole(identity)
            }
        }
    }

    // MARK: - Ancestry queries

    private static func registerAncestry() {
        Benchmark("identity/isAncestor ×1000") { benchmark in
            for _ in benchmark.scaledIterations {
                var hits = 0
                for _ in 0..<1_000 where ancestor.isAncestor(of: descendant) {
                    hits += 1
                }
                blackHole(hits)
            }
        }
    }
}
