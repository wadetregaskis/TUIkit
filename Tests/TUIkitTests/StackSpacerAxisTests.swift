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
//  The stacks as `Layout` VALUES then shipped with the same hole and neither
//  guard: `VStackLayout`/`HStackLayout` passed the subviews' own reports
//  through, so a Spacer made them flexible on BOTH axes. Their cases here
//  assert against the view spellings, which is the invariant that matters —
//  the two must place and report identically.
//
//  The render then kept the hole the measure had closed: `renderClip` sized
//  the column's WIDTH from its vertical distribution's flags, which a Spacer
//  always sets, so a column reported its widest child and painted the whole
//  offer. `LazyVStack` agreed with itself only by being wrong in both halves:
//  its Spacer's own both-axes report leaked through the width test.
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

    @Test("The layout values report the same axes their view spellings do")
    func layoutValuesAgreeWithTheirViews() {
        // `VStackLayout`/`HStackLayout` place subviews exactly as `VStack` and
        // `HStack` do, so they have to report the same flexibility: they read
        // the subviews' own `ViewSize`s, and `Spacer` says BOTH axes without
        // knowing which stack it is in.
        let column = measure(VStackLayout(spacing: 0) { Text("hi"); Spacer() })
        #expect(column.isHeightFlexible, "the Spacer's own axis still expands")
        #expect(!column.isWidthFlexible, "the column does not become width-flexible")
        #expect(column.isWidthFlexible == measure(VStack { Text("hi"); Spacer() }).isWidthFlexible)

        let row = measure(HStackLayout { Text("a"); Spacer(); Text("b") })
        #expect(row.isWidthFlexible, "a row with a Spacer still fills its width")
        #expect(!row.isHeightFlexible, "the row does not become height-flexible")
        #expect(
            row.isHeightFlexible
                == measure(HStack { Text("a"); Spacer(); Text("b") }).isHeightFlexible)
    }

    @Test("A layout-value row with a Spacer does not steal its column's slack")
    func layoutRowDoesNotStealSlack() {
        // What the wrong flag costs, visibly. The row said height-flexible, so
        // the column split its eight rows between the row and the real Spacer
        // — and the row paints one line whatever it is given, so its share
        // evaporated and the footer sat halfway up the screen instead of at
        // the bottom.
        let lines = render(
            VStack(spacing: 0) {
                HStackLayout { Text("a"); Spacer(); Text("b") }
                Spacer()
                Text("bottom")
            }, width: 12, height: 8)

        #expect(lines.count == 8, "the column fills its height: \(lines)")
        #expect(lines.last?.contains("bottom") == true, "the Spacer took it all: \(lines)")
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

    @Test("A column with a Spacer paints only as wide as it measures")
    func columnPaintsItsMeasuredWidth() {
        // The render half of the first test. The measure left the Spacer out of
        // the width; the render sized the width from the HEIGHT distribution's
        // flags, which a Spacer always sets — 2 cells reported, all 24 painted.
        let view = VStack { Text("hi"); Spacer() }
        let measured = measure(view)
        let painted = renderToBuffer(view, context: makeRenderContext(width: 24, height: 6))

        #expect(!measured.isWidthFlexible, "the precondition: a rigid width")
        #expect(
            painted.width == measured.width,
            "measured \(measured.width) cells, painted \(painted.width)")
        #expect(painted.height == 6, "the Spacer still fills the height")
    }

    @Test("A Spacer-bearing column inside a leading column starts at the leading edge")
    func nestedColumnHugsItsContent() {
        // What the painted width cost where it shows: the inner column centred
        // "hi" across the whole offer rather than inside its own two cells, so
        // it sat mid-screen under a header drawn at column 0. Its own measure —
        // and SwiftUI — put it at column 0.
        let lines = render(
            VStack(alignment: .leading) {
                Text("Header")
                VStack { Text("hi"); Spacer() }
            })

        #expect(lines[0].hasPrefix("Header"), "\(lines)")
        #expect(
            lines[1].hasPrefix("hi"),
            "the inner column hugs its content: \(lines[1].debugDescription)")
    }

    @Test("A lazy column with a Spacer hugs its content as the eager one does")
    func lazyColumnAgreesWithEager() {
        // Its Spacer's own both-axes report reached the width test, and the
        // render filled to match — so the same content measured 2 wide as a
        // `VStack` and 24 wide as a `LazyVStack`.
        let lazy = measure(LazyVStack { Text("hi"); Spacer() })
        let eager = measure(VStack { Text("hi"); Spacer() })

        #expect(lazy.isHeightFlexible, "the Spacer's own axis still expands")
        #expect(!lazy.isWidthFlexible, "but the lazy column does not become width-flexible")
        #expect(lazy.width == eager.width, "lazy \(lazy.width) cells, eager \(eager.width)")

        let lines = render(LazyVStack { Text("hi"); Spacer() })
        #expect(lines[0] == "hi", "the lazy column hugs its content: \(lines[0].debugDescription)")
    }

    @Test("A width-flexible child still makes a Spacer-bearing column fill")
    func widthFlexibleChildStillFills() {
        // The guard against over-reach: the fix takes the SPACER out of the
        // width decision, not the children that really do fill their width.
        let eager = VStack { Text("hi").frame(maxWidth: .infinity); Spacer() }
        let lazy = LazyVStack { Text("hi").frame(maxWidth: .infinity); Spacer() }
        let eagerWidth = renderToBuffer(eager, context: makeRenderContext(width: 24, height: 6)).width
        let lazyWidth = renderToBuffer(lazy, context: makeRenderContext(width: 24, height: 6)).width

        #expect(measure(eager).isWidthFlexible)
        #expect(measure(lazy).isWidthFlexible)
        #expect(eagerWidth == 24, "the flexible child fills the column: \(eagerWidth)")
        #expect(lazyWidth == 24, "the flexible child fills the lazy column: \(lazyWidth)")
    }
}
