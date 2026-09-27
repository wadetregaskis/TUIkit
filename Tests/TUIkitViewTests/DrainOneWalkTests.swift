//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DrainOneWalkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

/// The frame-start drain clears for every queued writer in one walk of each
/// table, and drops exactly what one clear per writer dropped.
///
/// The reference is the pairwise clear itself: the same random tree of
/// identities, a buffer and a size stored at every one of them, in two caches;
/// one clears for each writer in turn with the public
/// `clearAffected(by:keepingSizes:includingDescendants:)`, the other queues
/// the writers as `@State` writes do and drains them. The survivors, the size
/// generation and the clear count must match; and the walk must visit each
/// table once, whether one writer is queued or two hundred.
@MainActor
@Suite("The drain walks each table once, however many writes are pending")
struct DrainOneWalkTests {
    private enum Root {}
    private enum Step {}

    /// SplitMix64, so a tree and a writer set are functions of a seed.
    private struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    }

    /// `count` identities under one root, each a child of a random earlier
    /// one: deep chains and wide fans alike. Raw-rooted when `raw`, as tests
    /// and the empty default root are.
    private static func tree(count: Int, random: inout Random, raw: Bool) -> [ViewIdentity] {
        var nodes = [raw ? ViewIdentity(path: "Root") : ViewIdentity(rootType: Root.self)]
        for index in 1..<count {
            nodes.append(nodes[random.below(nodes.count)].child(type: Step.self, index: index))
        }
        return nodes
    }

    private static func sizeKey(_ node: ViewIdentity) -> RenderCache.SizeKey {
        RenderCache.SizeKey(
            identityHash: node.structuralHash, proposalWidth: nil, proposalHeight: nil, availableWidth: 10,
            availableHeight: 1, hasExplicitWidth: false, hasExplicitHeight: false, measureGeneration: 0)
    }

    /// A cache holding a buffer and a size at every identity of `nodes`.
    private static func filled(_ nodes: [ViewIdentity]) -> RenderCache {
        let cache = RenderCache()
        for (index, node) in nodes.enumerated() {
            cache.store(identity: node, view: index, buffer: FrameBuffer(text: "\(index)"), contextWidth: 10, contextHeight: 1)
            cache.storeSize(key: sizeKey(node), identity: node, view: index, size: .fixed(index, 1))
        }
        return cache
    }

    /// Which identities still hold a buffer, and which a size.
    private static func survivors(_ cache: RenderCache, _ nodes: [ViewIdentity]) -> [String] {
        nodes.enumerated().map { index, node in
            let buffer = cache.lookup(identity: node, view: index, contextWidth: 10, contextHeight: 1) != nil
            let size = cache.lookupSize(key: sizeKey(node), view: index) != nil
            return "\(buffer ? "B" : "-")\(size ? "S" : "-")"
        }
    }

    /// One case: a tree, a writer set, both clears, and every comparison.
    private static func compare(seed: UInt64, count: Int, writers writerCount: Int, raw: Raw) {
        var random = Random(state: seed)
        var nodes = tree(count: count, random: &random, raw: raw == .all)
        if raw == .someWriters {
            // A raw-rooted tree beside the structural one, and writers from both.
            nodes += tree(count: count / 4, random: &random, raw: true)
        }
        var writers = Set<ViewIdentity>()
        while writers.count < writerCount { writers.insert(nodes[random.below(nodes.count)]) }

        let pairwise = filled(nodes)
        for writer in writers { pairwise.clearAffected(by: writer) }

        let drained = filled(nodes)
        for writer in writers { drained.invalidateRender(for: writer) }
        drained.beginRenderPass()

        #expect(drained.sizeClearGeneration == pairwise.sizeClearGeneration, "the size generation moves once per writer")
        #expect(drained.stats.subtreeClears == pairwise.stats.subtreeClears, "one subtree clear per writer")
        #expect(drained.count == pairwise.count, "as many buffers survive")
        let expected = survivors(pairwise, nodes)
        let found = survivors(drained, nodes)
        let differing = nodes.indices.filter { expected[$0] != found[$0] }.map { "\(nodes[$0].path): \(found[$0]) where \(expected[$0])" }
        #expect(differing.isEmpty, "seed \(seed), \(writerCount) writers: \(differing.prefix(5))")
    }

    /// Where raw-rooted identities are.
    enum Raw: String, CaseIterable { case none, all, someWriters }

    @Test("It drops exactly what one clear per writer dropped", arguments: Raw.allCases, [1, 2, 5, 40, 200])
    func sameAsOneClearPerWriter(raw: Raw, writers: Int) {
        for seed in UInt64(1)...8 {
            Self.compare(seed: seed &* 0x5DEE_CE66D &+ UInt64(writers), count: 300, writers: writers, raw: raw)
        }
    }

    @Test("It visits each table once, with one writer queued and with two hundred", arguments: [1, 200])
    func visitsEachTableOnce(writers writerCount: Int) {
        var random = Random(state: 7)
        let nodes = Self.tree(count: 1_000, random: &random, raw: false)
        let cache = Self.filled(nodes)
        var writers = Set<ViewIdentity>()
        // Leaves, so every writer drops little and the tables stay near full:
        // what one walk per writer would cost is then writers × the tables.
        let parents = Set(nodes.compactMap(\.parent))
        let leaves = nodes.filter { !parents.contains($0) }
        while writers.count < writerCount { writers.insert(leaves[random.below(leaves.count)]) }
        let before = cache.stats
        let tables = cache.count * 2
        for writer in writers { cache.invalidateRender(for: writer) }
        cache.beginRenderPass()
        let visits = cache.stats.delta(since: before).clearVisits
        #expect(visits == tables, "\(writerCount) writers visited \(visits) entries of \(tables)")
    }
}
