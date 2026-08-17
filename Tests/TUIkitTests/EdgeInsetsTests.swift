//  TUIKit - Terminal UI Kit for Swift
//  EdgeInsetsTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - EdgeInsets Tests

@MainActor
@Suite("EdgeInsets Tests")
struct EdgeInsetsTests {

    @Test("EdgeInsets uniform value")
    func edgeInsetsUniform() {
        let insets = EdgeInsets(all: 3)
        #expect(insets.top == 3)
        #expect(insets.leading == 3)
        #expect(insets.bottom == 3)
        #expect(insets.trailing == 3)
    }

    @Test("EdgeInsets horizontal and vertical")
    func edgeInsetsHorizontalVertical() {
        let insets = EdgeInsets(horizontal: 2, vertical: 1)
        #expect(insets.top == 1)
        #expect(insets.leading == 2)
        #expect(insets.bottom == 1)
        #expect(insets.trailing == 2)
    }

    @Test("EdgeInsets is Equatable")
    func edgeInsetsEquatable() {
        let insetsA = EdgeInsets(all: 2)
        let insetsB = EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        #expect(insetsA == insetsB)
    }
}

// MARK: - Edge.Set Tests

@MainActor
@Suite("Edge.Set Tests")
struct EdgeSetTests {

    @Test("Edge.Set.all contains all edges")
    func edgeAll() {
        #expect(Edge.Set.all.contains(.top))
        #expect(Edge.Set.all.contains(.leading))
        #expect(Edge.Set.all.contains(.bottom))
        #expect(Edge.Set.all.contains(.trailing))
    }

    @Test("Edge.Set.horizontal contains leading and trailing")
    func edgeHorizontal() {
        #expect(Edge.Set.horizontal.contains(.leading))
        #expect(Edge.Set.horizontal.contains(.trailing))
        #expect(!Edge.Set.horizontal.contains(.top))
        #expect(!Edge.Set.horizontal.contains(.bottom))
    }

    @Test("Edge.Set.vertical contains top and bottom")
    func edgeVertical() {
        #expect(Edge.Set.vertical.contains(.top))
        #expect(Edge.Set.vertical.contains(.bottom))
        #expect(!Edge.Set.vertical.contains(.leading))
        #expect(!Edge.Set.vertical.contains(.trailing))
    }

    @Test("Edge enumerates its four cases")
    func edgeCases() {
        #expect(Edge.allCases == [.top, .leading, .bottom, .trailing])
    }

    @Test("A single edge makes a set of exactly itself")
    func edgeSetFromOneEdge() {
        // Every case, not one sample: the two families are spelled alike (a
        // `Set.top` static beside an `Edge.top` case), so a mapping that
        // returned the wrong sibling is the mistake to expect, and it hides
        // completely if only one case is checked.
        for edge in Edge.allCases {
            let set = Edge.Set(edge)
            #expect(set.contains(Edge.Set(edge)), "\(edge)")
            for other in Edge.allCases where other != edge {
                #expect(!set.contains(Edge.Set(other)), "\(edge) leaked into \(other)")
            }
        }
        // …and each lands on the static of the same name.
        #expect(Edge.Set(.top) == .top)
        #expect(Edge.Set(.leading) == .leading)
        #expect(Edge.Set(.bottom) == .bottom)
        #expect(Edge.Set(.trailing) == .trailing)
    }

    @Test("The vertical edge set takes one edge the same way")
    func verticalEdgeSetFromOneEdge() {
        #expect(VerticalEdge.Set(.top) == .top)
        #expect(VerticalEdge.Set(.bottom) == .bottom)
        #expect(!VerticalEdge.Set(.top).contains(.bottom))
    }
}
