//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackFlexibilityTests.swift
//
//  What a stack tells its PARENT about wanting more space. Getting this wrong
//  is invisible in the stack itself and wrong one level up: a parent hands out
//  space in proportion to who says they want it, so a child that under-reports
//  is simply not offered any.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("Stack flexibility reporting")
struct StackFlexibilityTests {

    private func measure(_ view: some View, width: Int = 40, height: Int = 12) -> ViewSize {
        measureChild(
            view, proposal: .unspecified,
            context: makeRenderContext(width: width, height: height))
    }

    @Test("An HStack holding something that grows vertically says so")
    func hstackReportsHeightFlexibility() {
        // Was hard-coded `false` on the `.clip` path — the same under-reporting
        // VStack had on its own axis, and fixed there with the same reasoning.
        let flexible = measure(HStack { ScrollView { Text("a\nb\nc\nd\ne\nf\ng\nh") } })
        #expect(flexible.isHeightFlexible, "a row containing a ScrollView reported rigid")

        // …and a row of plain text still reports rigid, or the check above
        // passes for everything.
        #expect(!measure(HStack { Text("a") }).isHeightFlexible)
    }

    @Test("An HStack's two overflow policies agree about flexibility")
    func overflowPoliciesAgree() {
        // `.clip` and `.window` are two ways to handle an over-wide row, not
        // two opinions about what the row wants. `.window` computed height
        // flexibility correctly all along, so it is the reference.
        @ViewBuilder func content() -> some View {
            ScrollView { Text("a\nb\nc\nd\ne\nf") }
            Text("label")
        }
        func flexibility(_ overflow: StackOverflow) -> Bool {
            let core = _HStackCore(
                alignment: .center, spacing: 1, overflow: overflow,
                content: content())
            return core.sizeThatFits(
                proposal: .unspecified,
                context: makeRenderContext(width: 40, height: 12)
            ).isHeightFlexible
        }
        #expect(
            flexibility(.clip) == flexibility(.window),
            "clip \(flexibility(.clip)) vs window \(flexibility(.window))")
        #expect(flexibility(.window), "precondition: the reference path reports flexible")
    }

    @Test("A VStack holding something that grows horizontally says so")
    func vstackReportsWidthFlexibility() {
        // The twin of the above, and the one that was fixed first — kept here
        // so the pair is visible in one place rather than one axis at a time.
        #expect(measure(VStack { Spacer(); Text("x") }).isHeightFlexible)
        #expect(!measure(VStack { Text("x") }).isWidthFlexible)
    }
}
