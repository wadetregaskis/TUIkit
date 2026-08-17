//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineLimitEnvironmentTests.swift
//
//  `.lineLimit(_:)` on a **View** — the cascading one, which SwiftUI has and
//  TUIkit did not. The interesting part is not that it caps lines; it is that
//  `nil` has to keep meaning *unlimited* rather than *unset*, or a subtree that
//  cascaded a limit could never let one branch out of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("lineLimit (View)")
struct LineLimitEnvironmentTests {

    /// Long enough to wrap to several lines at the widths used here.
    private let prose = "one two three four five six seven eight nine ten eleven twelve"

    private func rendered(_ view: some View, width: Int = 12, height: Int = 20) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    private func measured(_ view: some View, width: Int = 12, height: Int = 20) -> ViewSize {
        measureChild(
            view, proposal: ProposedSize(width: width, height: nil),
            context: makeRenderContext(width: width, height: height))
    }

    // MARK: - Cascading

    @Test("The cascaded limit reaches text that never mentioned one")
    func cascadeReachesDescendants() {
        let free = rendered(VStack { Text(prose) })
        let capped = rendered(VStack { Text(prose) }.lineLimit(2))
        #expect(free.count > 2, "the prose wraps past two lines to begin with: \(free)")
        #expect(capped.count == 2, "the cascade capped it: \(capped)")
    }

    @Test("A Text's own limit beats the one cascaded to it")
    func textOwnLimitWins() {
        let capped = rendered(VStack { Text(prose).lineLimit(1) }.lineLimit(3))
        #expect(capped.count == 1, "the Text's own 1 wins over the cascaded 3: \(capped)")
    }

    /// The reason `LineLimit` exists rather than a bare `Int?`: SwiftUI's `nil`
    /// means *unlimited*, and a stored `Int?` cannot tell that apart from
    /// *nobody said*. Get it wrong and the branch below silently keeps the
    /// inherited cap — the failure this pins.
    @Test("lineLimit(nil) on a Text opts back out of a cascaded limit")
    func nilOptsOutOfTheCascade() {
        let free = rendered(VStack { Text(prose) })
        let opted = rendered(VStack { Text(prose).lineLimit(nil) }.lineLimit(2))
        #expect(opted.count == free.count, "the Text asked for no limit: \(opted)")
        #expect(opted.count > 2, "…and got more than the cascaded two")
    }

    @Test("lineLimit(nil) on a View opts a whole subtree back out")
    func nilOptsOutASubtree() {
        let free = rendered(VStack { Text(prose) })
        let opted = rendered(
            VStack { VStack { Text(prose) }.lineLimit(nil) }.lineLimit(2))
        #expect(opted.count == free.count, "the inner subtree lifted the cap: \(opted)")
    }

    @Test("An inner limit overrides an outer one")
    func innerCascadeWins() {
        let capped = rendered(VStack { VStack { Text(prose) }.lineLimit(1) }.lineLimit(4))
        #expect(capped.count == 1, "the nearer modifier decides: \(capped)")
    }

    // MARK: - Measure / render parity

    /// A limit that only the render honours makes the parent reserve rows
    /// nothing draws into; one only the measure honours clips text the parent
    /// left no room for. Both passes resolve it the same way.
    @Test("The measured height matches the rendered height under a cascade")
    func measureAgreesWithRender() {
        let view = VStack { Text(prose) }.lineLimit(2)
        #expect(measured(view).height == 2, "measured \(measured(view).height)")
        #expect(rendered(view).count == 2, "rendered \(rendered(view).count)")
    }

    @Test("…and when a Text opts out of it")
    func measureAgreesWithRenderWhenOptedOut() {
        let view = VStack { Text(prose).lineLimit(nil) }.lineLimit(2)
        #expect(
            measured(view).height == rendered(view).count,
            "measured \(measured(view).height), rendered \(rendered(view).count)")
    }

    // MARK: - Defaults and edges

    @Test("The default is unlimited")
    func defaultIsUnlimited() {
        #expect(EnvironmentValues().lineLimit == .unlimited)
        #expect(LineLimit.unlimited.rowCount == nil)
    }

    @Test("A zero or negative limit still shows one line, not none")
    func nonPositiveLimitsClamp() {
        #expect(LineLimit.lines(0).rowCount == 1)
        #expect(LineLimit.lines(-3).rowCount == 1)
        #expect(rendered(VStack { Text(prose) }.lineLimit(0)).count == 1)
    }

    @Test("Int? maps onto the two cases the way SwiftUI spells it")
    func intOptionalMapping() {
        #expect(LineLimit(nil) == .unlimited)
        #expect(LineLimit(3) == .lines(3))
        #expect(LineLimit(3).reservedLines == nil, "a plain limit reserves nothing")
    }

    // MARK: - reservesSpace

    @Test("A short text still occupies the lines it reserved")
    func reservesSpacePadsShortText() {
        // The point of the modifier: two rows whose text differs in length are
        // the same height, so a column of them does not shuffle as the data
        // changes.
        let short = rendered(VStack { Text("one") }.lineLimit(3, reservesSpace: true))
        #expect(short.count == 3, "padded out to its reservation: \(short)")
        #expect(short[0].contains("one"))
        #expect(short[1].isEmpty && short[2].isEmpty, "the reserved rows are blank: \(short)")

        // …and without it, the same text is one line tall — which is the
        // comparison that makes the above mean something.
        #expect(rendered(VStack { Text("one") }.lineLimit(3)).count == 1)
    }

    @Test("A reservation is a floor, not a second ceiling")
    func reservationStillCaps() {
        // Long prose under `.lineLimit(2, reservesSpace: true)` is still capped
        // at two lines — an implementation that only ever padded would let it
        // run on.
        let long = rendered(VStack { Text(prose) }.lineLimit(2, reservesSpace: true))
        #expect(long.count == 2, "\(long)")
        #expect(!long[1].isEmpty, "and both lines carry text: \(long)")
    }

    @Test("The measure reports the reserved height, not the drawn one")
    func measureMatchesTheReservation() {
        // The trap: measure and render resolve the policy separately. A
        // reservation the measure did not claim gives the text fewer rows than
        // it pads out to, and it spills; one the render does not fill leaves
        // rows allocated that nothing draws into. Asserting they AGREE is what
        // catches either direction.
        let view = VStack { Text("one") }.lineLimit(4, reservesSpace: true)
        #expect(measured(view).height == 4, "measured \(measured(view).height)")
        #expect(measured(view).height == rendered(view).count)
    }

    @Test("A squeezed reservation draws what fits rather than overflowing")
    func reservationYieldsToTheParent() {
        // The floor is honoured only as far as the parent allows. Two rows of
        // budget and a four-line reservation must give two rows, not four.
        let squeezed = rendered(
            VStack { Text("one") }.lineLimit(4, reservesSpace: true), height: 2)
        #expect(squeezed.count <= 2, "\(squeezed)")
    }

    @Test("A new limit further down replaces the reservation with its own")
    func innerLimitDropsTheReservation() {
        // `reservesSpace` rides on the limit, so stating a limit states a
        // reservation too — here, none. A `Bool` cascading separately would
        // have left the outer reservation hanging over the inner limit.
        let inner = rendered(
            VStack { Text("one").lineLimit(2) }.lineLimit(4, reservesSpace: true))
        #expect(inner.count == 1, "the inner limit reserves nothing: \(inner)")
    }
}
