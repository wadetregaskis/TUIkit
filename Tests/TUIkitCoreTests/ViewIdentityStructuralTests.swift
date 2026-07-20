//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewIdentityStructuralTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitCore

/// Exhaustive checks for the structural ``ViewIdentity`` representation. The
/// correctness-critical property is that two identities built *independently*
/// for the same structural position compare equal and hash equal — the measure
/// pass and the render pass each construct their own node chain for a given
/// view, and they must land on the same `StateStorage` / `RenderCache` slot.
@Suite("ViewIdentity (structural)")
struct ViewIdentityStructuralTests {
    private struct TypeA {}
    private struct TypeB {}
    private struct TypeC {}

    // MARK: The linchpin

    @Test("Independently-built identities for the same position are equal and hash-equal")
    func samePositionEqualAndHashEqual() {
        let lhs = ViewIdentity(rootType: TypeA.self)
            .child(type: TypeB.self, index: 0)
            .child(type: TypeC.self)
            .branch("true")
        let rhs = ViewIdentity(rootType: TypeA.self)
            .child(type: TypeB.self, index: 0)
            .child(type: TypeC.self)
            .branch("true")

        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        // They MUST collapse to a single key — StateStorage marks liveness and
        // RenderCache memoizes through a Set / dictionary keyed by identity.
        #expect(Set([lhs, rhs]).count == 1)
        #expect([lhs: 1][rhs] == 1)
    }

    @Test("A structural child of a raw root composes equally across builds")
    func rawRootedChildEqual() {
        let lhs = ViewIdentity(path: "Root").child(type: TypeB.self, index: 2)
        let rhs = ViewIdentity(path: "Root").child(type: TypeB.self, index: 2)
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    // MARK: Distinctness

    @Test("Differing type, index, presence-of-index, branch, or kind are distinct")
    func distinctPositions() {
        let root = ViewIdentity(rootType: TypeA.self)
        #expect(root.child(type: TypeB.self, index: 0) != root.child(type: TypeC.self, index: 0))
        #expect(root.child(type: TypeB.self, index: 0) != root.child(type: TypeB.self, index: 1))
        #expect(root.child(type: TypeB.self) != root.child(type: TypeB.self, index: 0))
        #expect(root.branch("true") != root.branch("false"))
        #expect(root.child(type: TypeB.self) != root.branch("TypeB"))
        // Different roots, same descent, are distinct.
        #expect(ViewIdentity(rootType: TypeA.self).child(type: TypeB.self)
            != ViewIdentity(rootType: TypeB.self).child(type: TypeB.self))
    }

    @Test("Raw identities compare and render by their string")
    func rawStringSemantics() {
        let raw1 = ViewIdentity(path: "A/B")
        let raw2 = ViewIdentity(path: "A/B")
        #expect(raw1 == raw2)
        #expect(ViewIdentity(path: "A/B") != ViewIdentity(path: "A/C"))
        #expect(ViewIdentity(path: "A/B").path == "A/B")
        #expect(ViewIdentity(path: "").path.isEmpty)
    }

    // MARK: Path rendering (asserted against the same name source the path uses)

    @Test("Path renders the readable structural form")
    func pathRendering() {
        let nameB = cachedTypeName(TypeB.self)
        let root = ViewIdentity(rootType: TypeA.self)
        // Bare root — no leading slash.
        #expect(root.path == cachedTypeName(TypeA.self))
        // Typed child with index.
        #expect(root.child(type: TypeB.self, index: 1).path == "\(cachedTypeName(TypeA.self))/\(nameB).1")
        // Typed child without index (composite body).
        #expect(root.child(type: TypeB.self).path == "\(cachedTypeName(TypeA.self))/\(nameB)")
        // Branch.
        #expect(root.branch("true").path == "\(cachedTypeName(TypeA.self))#true")
        // Structural child of a raw root: the raw string is the prefix.
        #expect(ViewIdentity(path: "Root").child(type: TypeB.self, index: 0).path == "Root/\(nameB).0")
        // Child of the empty root gets a leading slash (matches the old format).
        #expect(ViewIdentity(path: "").child(type: TypeB.self, index: 0).path == "/\(nameB).0")
    }

    @Test("description equals path")
    func descriptionIsPath() {
        let id = ViewIdentity(rootType: TypeA.self).child(type: TypeB.self, index: 3)
        #expect(id.description == id.path)
    }

    // MARK: isAncestor (strict-prefix semantics, structural and raw)

    @Test("isAncestor is strict and respects component boundaries")
    func ancestry() {
        // Raw (the form the existing identity tests use).
        let ab = ViewIdentity(path: "A/B")
        #expect(ab.isAncestor(of: ViewIdentity(path: "A/B/C")))
        #expect(ab.isAncestor(of: ViewIdentity(path: "A/B#true/C")))
        #expect(!ab.isAncestor(of: ViewIdentity(path: "A/D")))
        #expect(!ab.isAncestor(of: ab))                          // strict
        #expect(!ab.isAncestor(of: ViewIdentity(path: "A/BC")))  // no false prefix match

        // Structural.
        let root = ViewIdentity(rootType: TypeA.self)
        let parent = root.child(type: TypeB.self, index: 0)
        let child = parent.child(type: TypeC.self)
        #expect(parent.isAncestor(of: child))
        #expect(root.isAncestor(of: child))
        #expect(!child.isAncestor(of: parent))
        #expect(!parent.isAncestor(of: root.child(type: TypeC.self, index: 0)))  // sibling
    }

    // MARK: Disjoint structural-vs-raw worlds (intentional)

    @Test("A structural and a raw identity with the same path are NOT equal (disjoint by design)")
    func structuralAndRawAreDistinctEvenWhenPathsMatch() {
        let structural = ViewIdentity(rootType: TypeA.self)
        let raw = ViewIdentity(path: cachedTypeName(TypeA.self))
        #expect(structural.path == raw.path)   // same rendering
        #expect(structural != raw)             // different construction → not equal
        // This never arises in practice: a render tree is uniformly structural
        // (production) or uniformly raw (tests).
    }

    // MARK: Graceful depth cap

    @Test("Identity depth caps instead of growing without bound")
    func depthCapIsGraceful() {
        func deepIdentity() -> ViewIdentity {
            var id = ViewIdentity(rootType: TypeA.self)
            for _ in 0..<(IdentityNode.maxDepth + 50) {
                id = id.child(type: TypeB.self, index: 0)
            }
            return id
        }
        let id = deepIdentity()
        // Stopped growing at the cap rather than allocating unbounded / overflowing.
        #expect(id.node.depth == IdentityNode.maxDepth)
        // Two independently-capped identities stay equal, and rendering works.
        #expect(id == deepIdentity())
        #expect(!id.path.isEmpty)
    }
}
