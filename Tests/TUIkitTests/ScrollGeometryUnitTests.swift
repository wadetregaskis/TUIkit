//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollGeometryUnitTests.swift
//
//  Unit pins for the pure functions the windowed pipeline leans on: the
//  scrollTo anchor arithmetic at the clamped edges, the indicator label's
//  degradation-ladder boundaries, and the window-consumption identity gate.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("scroll geometry units")
struct ScrollGeometryUnitTests {

    @Test("windowOffset clamps anchored targets at both edges")
    func windowOffsetEdgeClamps() {
        // viewport 6, insets 1 each side, 100 rows of height 1.
        func request(_ anchor: UnitPoint?) -> ScrollToRequest {
            ScrollToRequest(key: "k", anchor: anchor, topInset: 1, bottomInset: 1)
        }
        // .center near the top: raw goes negative and clamps to 0.
        #expect(
            request(.center).windowOffset(
                targetY: 2, rowHeight: 1, currentOffset: 50,
                viewportHeight: 6, totalHeight: 100) == 0)
        // .bottom at the very top row: clamps to 0 (cannot bottom-align).
        #expect(
            request(.bottom).windowOffset(
                targetY: 0, rowHeight: 1, currentOffset: 50,
                viewportHeight: 6, totalHeight: 100) == 0)
        // .top near the tail: the row cannot top-align — clamps to maxOffset.
        #expect(
            request(.top).windowOffset(
                targetY: 98, rowHeight: 1, currentOffset: 0,
                viewportHeight: 6, totalHeight: 100) == 94)
        // .top at row 0 charges no top pad (offset 0 shows no indicator).
        #expect(
            request(.top).windowOffset(
                targetY: 0, rowHeight: 1, currentOffset: 50,
                viewportHeight: 6, totalHeight: 100) == 0)
        // nil anchor, already visible within the indicator-clipped band:
        // exactly the current offset.
        #expect(
            request(nil).windowOffset(
                targetY: 52, rowHeight: 1, currentOffset: 50,
                viewportHeight: 6, totalHeight: 100) == 50)
        // Content smaller than the viewport: always 0.
        #expect(
            request(.bottom).windowOffset(
                targetY: 2, rowHeight: 1, currentOffset: 0,
                viewportHeight: 6, totalHeight: 4) == 0)
    }

    @Test("The indicator ladder degrades at exactly its width boundaries")
    func indicatorLadderBoundaries() {
        let palette = EnvironmentValues().palette
        func label(_ width: Int) -> String {
            renderScrollIndicator(
                direction: .down, count: 14, unit: .lines,
                width: width, palette: palette
            ).stripped.trimmingCharacters(in: .whitespaces)
        }
        // Rung minima for count 14 / .lines: full 22, no-"more" 17,
        // no-direction 11, bare count 5. One column narrower drops a rung;
        // never a mid-word clip.
        #expect(label(22) == "▼ 14 more lines below")
        #expect(label(21) == "▼ 14 lines below")
        #expect(label(17) == "▼ 14 lines below")
        #expect(label(16) == "▼ 14 lines")
        #expect(label(11) == "▼ 14 lines")
        #expect(label(10) == "▼ 14")
        #expect(label(5) == "▼ 14")
        #expect(label(4) == "▼")
        // Zero count (edge callers): "more below" with no number, and it
        // degrades to the bare arrow.
        func zero(_ width: Int) -> String {
            renderScrollIndicator(
                direction: .down, count: 0, unit: .lines,
                width: width, palette: palette
            ).stripped.trimmingCharacters(in: .whitespaces)
        }
        #expect(zero(13) == "▼ more below")
        #expect(zero(12) == "▼")
        // No rendered form ever exceeds its width budget.
        for width in 1...25 {
            let body = label(width)
            #expect(body.count <= width, "width \(width) overflows: '\(body)'")
        }
    }

    @Test("isDirectDescent admits single-child chains and rejects siblings/rows")
    func directDescentGate() {
        // The window-consumption gate: a stack consumes the ScrollView's
        // window only when its identity is a single-child descent from the
        // scroll content — typed no-index and branch steps pass; keyed,
        // indexed, and unrelated paths must not.
        struct Content {}
        struct Wrapper {}
        let root = ViewIdentity(rootType: Content.self)

        let child = root.child(type: Wrapper.self)
        #expect(child.isDirectDescent(from: root), "typed no-index step passes")
        let grandchild = child.child(type: Wrapper.self)
        #expect(grandchild.isDirectDescent(from: root), "chains pass")

        let sibling = root.child(type: Wrapper.self, index: 1)
        #expect(!sibling.isDirectDescent(from: root), "an indexed sibling is NOT at the origin")

        let keyedRow = root.child(erasedType: Wrapper.self, key: "7")
        #expect(!keyedRow.isDirectDescent(from: root), "a keyed row is NOT at the origin")

        let stranger = ViewIdentity(rootType: Wrapper.self)
        #expect(!root.isDirectDescent(from: stranger), "unrelated identities reject")
        #expect(root.isDirectDescent(from: root), "an identity descends from itself")
    }
}
