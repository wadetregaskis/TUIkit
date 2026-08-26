//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackSpacerAxisTests.swift
//
//  SwiftUI: a Spacer "expands along the major axis of its containing stack
//  layout, or on both axes if not contained in a stack." `Spacer` here has no
//  axis input and reports both axes flexible, so each stack has to exclude the
//  axis that is not its own. `_HStackCore` did, in a branch of its own;
//  `_VStackCore` carried a comment saying it did and then, one line below,
//  did not — so a column with a Spacer in it advertised itself as
//  WIDTH-flexible and swallowed its row's whole slack.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("stack spacer axis")
struct StackSpacerAxisTests {
    private func measure<V: View>(_ view: V, width: Int = 24, height: Int = 6) -> ViewSize {
        let context = makeRenderContext(width: width, height: height)
        return measureChild(view, proposal: ProposedSize(width: width, height: height), context: context)
    }

    private func render<V: View>(_ view: V, width: Int = 24, height: Int = 6) -> [String] {
        let context = makeRenderContext(width: width, height: height)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @Test("A Spacer makes a column height-flexible, never width-flexible")
    func columnStaysRigidAcross() {
        let plain = measure(VStack { Text("hi") })
        let spaced = measure(VStack { Text("hi"); Spacer() })

        #expect(spaced.isHeightFlexible, "the Spacer's own axis still expands")
        #expect(!spaced.isWidthFlexible, "but the column does not become width-flexible")
        #expect(
            spaced.isWidthFlexible == plain.isWidthFlexible,
            "adding a Spacer changes nothing about the column's width")
    }

    @Test("A column with a Spacer does not swallow its row")
    func doesNotSwallowTheRow() {
        // The canonical layout: a left column using a Spacer to push its
        // content to the top, beside something else.
        let lines = render(
            HStack {
                VStack { Text("hi"); Spacer() }
                Text("RIGHT")
            })

        #expect(
            lines[0].trimmingCharacters(in: .whitespaces) == "hi RIGHT",
            "the column hugs its content: \(lines[0].debugDescription)")
    }

    @Test("A Spacer still expands a row horizontally")
    func rowsAreUnaffected() {
        // The mirror case, which `_HStackCore` already guarded — here to catch
        // a fix that over-reached and disarmed the Spacer in its own axis.
        let row = measure(HStack { Text("a"); Spacer(); Text("b") })
        #expect(row.isWidthFlexible, "a row with a Spacer still fills its width")

        let lines = render(HStack { Text("a"); Spacer(); Text("b") })
        #expect(lines[0].hasPrefix("a"), "\(lines)")
        #expect(lines[0].hasSuffix("b"), "the Spacer pushed them apart: \(lines[0].debugDescription)")
    }
}
