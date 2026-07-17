//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutPlacingTests.swift
//
//  Stage 1 of "Locating things without drawing them": a stack answers
//  "where is child N, and which child leads to identity X?" from measurement
//  alone — no rendering — and its answers agree with what the windowed render
//  actually draws, because both derive from the same slot walk.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("LayoutPlacing on the stacks")
struct LayoutPlacingTests {
    /// A stack of keyed rows with deliberately varied heights: row k is
    /// k%3+1 lines tall (via explicit frames), so prefix sums are non-trivial.
    private func makeStack(rows: Int) -> _VStackCore<ForEach<[Int], Int, some View>> {
        let items = Array(0..<rows)
        return _VStackCore(
            alignment: .leading, spacing: 1, overflow: .window,
            content: ForEach(items, id: \.self) { i in
                Text("row \(i)").frame(height: i % 3 + 1)
            })
    }

    @Test("Placements report measured geometry without rendering")
    func placementGeometry() {
        let stack = makeStack(rows: 10)
        let context = makeBareRenderContext(width: 30, height: 100)

        #expect(stack.placementCount(context: context) == 10)

        // Expected y: prefix sums of (height k%3+1) with spacing 1 between.
        var expectedY = 0
        for ordinal in 0..<10 {
            if ordinal > 0 { expectedY += 1 }  // spacing
            let placement = stack.placement(at: ordinal, proposal: .unspecified, context: context)
            #expect(placement?.y == expectedY, "row \(ordinal) y")
            #expect(placement?.height == ordinal % 3 + 1, "row \(ordinal) height")
            expectedY += ordinal % 3 + 1
        }
        #expect(stack.placement(at: 10, proposal: .unspecified, context: context) == nil)
    }

    @Test("ordinal(of:) routes a keyed identity chain in one step")
    func ordinalRoutesKeyedChildren() {
        let stack = makeStack(rows: 20)
        let context = makeBareRenderContext(width: 30, height: 100)

        // The placement's identity is the address the child really renders
        // under; routing it back must return the same ordinal.
        for ordinal in [0, 7, 19] {
            let identity = stack.placement(
                at: ordinal, proposal: .unspecified, context: context)!.identity
            #expect(stack.ordinal(of: identity, context: context) == ordinal)
        }

        // A DESCENDANT of a row routes to that row: the chain holds the answer.
        let rowIdentity = stack.placement(
            at: 13, proposal: .unspecified, context: context)!.identity
        let deep = rowIdentity.child(type: Int.self, index: 2).child(type: String.self)
        #expect(stack.ordinal(of: deep, context: context) == 13)

        // A foreign identity is not mine.
        let foreign = ViewIdentity(rootType: Double.self).child(type: Int.self, index: 1)
        #expect(stack.ordinal(of: foreign, context: context) == nil)

        // The stack's own identity is not a child either.
        #expect(stack.ordinal(of: context.identity, context: context) == nil)
    }

    @Test("ordinal(of:) routes positional (tuple) children")
    func ordinalRoutesPositionalChildren() {
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .clip,
            content: TupleView(Text("a"), Text("b")))
        let context = makeBareRenderContext(width: 30, height: 100)

        #expect(stack.placementCount(context: context) == 2)
        let second = stack.placement(at: 1, proposal: .unspecified, context: context)!
        #expect(stack.ordinal(of: second.identity, context: context) == 1)
    }

    @Test("The windowed render draws rows exactly where placements say they are")
    func windowedRenderAgreesWithPlacements() {
        let stack = makeStack(rows: 12)
        var context = makeBareRenderContext(width: 30, height: 200)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 9, viewportHeight: 5)

        let lines = renderToBuffer(stack, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }

        var queryContext = context
        queryContext.environment.scrollContentWindow = nil
        for ordinal in 0..<12 {
            let placement = stack.placement(
                at: ordinal, proposal: .unspecified, context: queryContext)!
            guard placement.y + placement.height > 9, placement.y < 14 else { continue }
            #expect(
                lines[placement.y] == "row \(ordinal)",
                "row \(ordinal) should render at its placement y \(placement.y)")
        }
    }
}

@MainActor
@Suite("ViewIdentity.childStep(below:)")
struct ChildStepTests {
    private final class Marker {}

    @Test("Extracts the routing step for keyed, indexed, and deep chains")
    func extractsSteps() {
        let root = ViewIdentity(rootType: Marker.self)
        let keyed = root.child(erasedType: Int.self, key: "42")
        #expect(keyed.childStep(below: root) == ViewIdentity.ChildStep(index: nil, key: "42"))

        let indexed = root.child(type: Int.self, index: 7)
        #expect(indexed.childStep(below: root) == ViewIdentity.ChildStep(index: 7, key: nil))

        // Deep chains answer with the FIRST step below the ancestor.
        let deep = keyed.child(type: String.self, index: 3).child(type: Double.self)
        #expect(deep.childStep(below: root) == ViewIdentity.ChildStep(index: nil, key: "42"))

        // Not on the chain: not mine.
        let sibling = ViewIdentity(rootType: Int.self)
        #expect(keyed.childStep(below: sibling) == nil)

        // Equal identity has no step below itself.
        #expect(root.childStep(below: root) == nil)
    }
}
