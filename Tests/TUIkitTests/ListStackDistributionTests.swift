//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListStackDistributionTests.swift
//
//  Regression tests for GitHub issue #6: multiple Lists without explicit
//  heights in a VStack must share the available vertical space. A List
//  greedily fills the height it is offered, so it must report its height as
//  *flexible* (a minimum) — reporting the filled height as fixed made every
//  unframed List an immovable full-height demand, sending the stack down the
//  distributor's overflow branch: the first List got everything and the
//  siblings collapsed to zero rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("List height distribution in stacks (issue #6)")
struct ListStackDistributionTests {
    private func strippedLines(_ view: some View, width: Int, height: Int) -> [String] {
        let context = makeRenderContext(width: width, height: height)
        return renderToBuffer(view, context: context).lines.map { $0.stripped }
    }

    /// The row index of each list's title line, in order of appearance.
    private func titleRows(_ lines: [String], titles: [String]) -> [Int?] {
        titles.map { title in lines.firstIndex { $0.contains(title) } }
    }

    @Test("Three unframed Lists in a VStack all render, sharing the height")
    func threeListsShareHeight() {
        let view = VStack {
            List("First") { ForEach(0..<3) { Text("A\($0)") } }
            List("Second") { ForEach(0..<3) { Text("B\($0)") } }
            List("Third") { ForEach(0..<3) { Text("C\($0)") } }
            Spacer()
        }

        let lines = strippedLines(view, width: 40, height: 24)
        let rows = titleRows(lines, titles: ["First", "Second", "Third"])
        #expect(rows.allSatisfy { $0 != nil }, "all three lists render: \(lines)")

        // Equal thirds (8 rows each in 24): each title sits one row into its
        // box, so consecutive titles are exactly a box height apart.
        if let first = rows[0], let second = rows[1], let third = rows[2] {
            let heights = [second - first, third - second]
            #expect(heights.allSatisfy { (7...9).contains($0) }, "even split, got gaps \(heights)")
        }
    }

    @Test("Explicit .frame(height:) still pins each List (the old workaround)")
    func framedListsKeepTheirHeights() {
        let view = VStack {
            List("First") { ForEach(0..<3) { Text("A\($0)") } }.frame(height: 6)
            List("Second") { ForEach(0..<3) { Text("B\($0)") } }.frame(height: 6)
            List("Third") { ForEach(0..<3) { Text("C\($0)") } }.frame(height: 6)
            Spacer()
        }

        let lines = strippedLines(view, width: 40, height: 24)
        let rows = titleRows(lines, titles: ["First", "Second", "Third"])
        #expect(rows.allSatisfy { $0 != nil }, "all three framed lists render: \(lines)")
        if let first = rows[0], let second = rows[1], let third = rows[2] {
            #expect(second - first == 6 && third - second == 6, "6-row boxes, got \(rows)")
        }
    }

    @Test("The issue's shape: HStack → VStack → three Lists")
    func issueShapeNestedStacks() {
        let view = VStack {
            Text("Hello, TUIkit!")
            Text("Welcome to your new terminal app")
            HStack {
                VStack {
                    Card(title: "Card") { Toggle("A toggle", isOn: .constant(false)) }
                    Spacer()
                }
                Spacer()
                VStack {
                    List("First") { ForEach(0..<3) { Text("A\($0)") } }
                    List("Second") { ForEach(0..<3) { Text("B\($0)") } }
                    List("Third") { ForEach(0..<3) { Text("C\($0)") } }
                    Spacer()
                }
                Spacer()
            }
        }
        .padding()

        let lines = strippedLines(view, width: 100, height: 30)
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("First"), "first list renders")
        #expect(joined.contains("Second"), "second list renders")
        #expect(joined.contains("Third"), "third list renders")
    }

    @Test("A List followed by fixed content leaves that content its space")
    func listDoesNotStarveFixedSiblings() {
        let view = VStack {
            List("Items") { ForEach(0..<3) { Text("A\($0)") } }
            Text("Status line")
        }

        let lines = strippedLines(view, width: 40, height: 12)
        #expect(lines.joined(separator: "\n").contains("Status line"), "trailing text renders: \(lines)")
    }

    @Test("List reports a flexible height to the measure pass")
    func listMeasuresHeightFlexible() {
        let context = makeRenderContext(width: 40, height: 24)
        let list = List("First") { ForEach(0..<3) { Text("A\($0)") } }
        let size = measureChild(list, proposal: .unspecified, context: context)
        #expect(size.height == 24, "greedy fill: the offered height, as a minimum")
        #expect(size.isHeightFlexible, "the filled height is a minimum, not a fixed demand")
        #expect(size.isWidthFlexible)
    }

    @Test("Equal-weight flexible children split the column evenly")
    func flexibleDistributionSplitsEvenly() {
        let result = distributeLinearSpace(
            naturalSizes: [24, 24, 24, 0],
            isFlexible: [true, true, true, true],
            available: 24)
        #expect(result == [8, 8, 8, 0])
    }
}
