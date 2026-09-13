//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackZeroExtentGapDistributionTests.swift
//
//  `distributeLinearSpace` reserves a gap only between children that will
//  occupy the axis. A zero-extent child is appended through the assemblers'
//  contributes-nothing branch and earns no gap, so a gap reserved for it was
//  space the flexible siblings were never handed: a Spacer beside one stopped
//  `spacing` cells short of flush.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Zero-extent children in the stack distribution")
struct StackZeroExtentGapDistributionTests {

    @Test("A zero-extent child reserves no gap when everything fits")
    func fittingBranch() {
        // [A, empty, Spacer, B] in 20 cells at spacing 2: three children occupy
        // the row, so two gaps (4) and the spacer takes 20 - 2 - 4 = 14. A gap
        // per child (6) handed it 12.
        let sizes = distributeLinearSpace(
            naturalSizes: [1, 0, 0, 1], isFlexible: [false, false, true, false],
            available: 20, spacing: 2)
        #expect(sizes == [1, 0, 14, 1])
    }

    @Test("A zero-extent child reserves no gap when the flexible child is squeezed")
    func squeezedBranch() {
        // The flexible child wants 10 of 10 cells. Fixed content (2) and the two
        // real gaps (4) leave it 4; a gap per child left it 2.
        let sizes = distributeLinearSpace(
            naturalSizes: [1, 0, 10, 1], isFlexible: [false, false, true, false],
            available: 10, spacing: 2)
        #expect(sizes == [1, 0, 4, 1])
    }

    @Test("A Spacer beside an EmptyView pushes an HStack's last column flush right")
    func hStackBesideEmptyView() {
        let buffer = renderToBuffer(
            HStack(spacing: 2) {
                Text("A")
                EmptyView()
                Spacer()
                Text("B")
            }, context: makeBareRenderContext(width: 20, height: 3))
        let expected = "A" + String(repeating: " ", count: 18) + "B"
        #expect(buffer.width == 20)
        #expect(buffer.lines.first?.stripped == expected)
    }

    @Test("A Spacer beside an empty Text pushes an HStack's last column flush right")
    func hStackBesideEmptyText() {
        // Zero columns but one line of escape bytes: the contributing branch of
        // `appendHorizontally`, which withholds the gap on width all the same.
        let buffer = renderToBuffer(
            HStack(spacing: 2) {
                Text("A")
                Text("")
                Spacer()
                Text("B")
            }, context: makeBareRenderContext(width: 20, height: 3))
        let expected = "A" + String(repeating: " ", count: 18) + "B"
        #expect(buffer.width == 20)
        #expect(buffer.lines.first?.stripped == expected)
    }

    @Test("A Spacer below an EmptyView pushes a VStack's last row to the bottom edge")
    func vStackBelowEmptyView() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 1) {
                Text("A")
                EmptyView()
                Spacer()
                Text("B")
            }, context: makeBareRenderContext(width: 20, height: 10))
        let rows = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(rows.count == 10)
        #expect(rows.last == "B")
    }
}
