//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GreedyIdealWidthTests.swift
//
//  A view that fills whatever it is offered, asked for its ideal width. SwiftUI's
//  have none — measured through a `Layout` that proposes `.unspecified`, a
//  `TextEditor`, a `List` and a linear `ProgressView` all report 0 — and a
//  two-axis `ScrollView` whose content still fills the probe's budget draws it
//  at the viewport rather than taking the budget for a width.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// One greedy view, by name, for the table below.
struct GreedyCase: Sendable, CustomTestStringConvertible {
    let name: String
    var testDescription: String { name }

    @MainActor
    var view: AnyView {
        switch name {
        case "TextEditor": AnyView(TextEditor(text: .constant("hello")))
        case "List": AnyView(List { Text("row") })
        case "ProgressView": AnyView(ProgressView(value: 0.5))
        case "Gauge": AnyView(Gauge(value: 0.5) { Text("g") })
        default: AnyView(GeometryReader { _ in Text("g") })
        }
    }
}

/// Whether the last line of a 40x12 two-axis `ScrollView` over `content` — its
/// horizontal bar, when it has one — is there.
@MainActor
private func hasHorizontalBar(_ content: some View) -> Bool {
    let buffer = renderToBuffer(
        ScrollView([.horizontal, .vertical]) { content },
        context: RenderContext(
            availableWidth: 40, availableHeight: 12, tuiContext: TUIContext()
        ).isolatingRenderCache())
    return buffer.lines.last?.stripped.contains("\u{25C0}") ?? false
}

@MainActor
@Suite("A greedy view asked for its ideal width")
struct GreedyIdealWidthTests {
    /// Under the ideal-width ask a greedy view has no width of its own and
    /// says so — 0, still flexible — and anywhere else fills the offer as
    /// before.
    @Test(
        "A greedy view has no ideal width",
        arguments: ["TextEditor", "List", "ProgressView", "Gauge", "GeometryReader"].map(GreedyCase.init))
    func aGreedyViewHasNoIdealWidth(_ greedy: GreedyCase) {
        let context = RenderContext(
            availableWidth: 4_096, availableHeight: 4_096, tuiContext: TUIContext())
        let open = ProposedSize(width: nil, height: nil)
        let ideal = measureChild(greedy.view, proposal: open, context: context.askingIdealWidth())
        #expect(ideal.width == 0)
        #expect(ideal.isWidthFlexible)
        let filled = measureChild(greedy.view, proposal: open, context: context)
        #expect(filled.width == 4_096, "outside the ask it no longer fills the offer")
    }

    /// With nothing around it to leave it out, a greedy view's answer WAS the
    /// canvas: a `TextEditor` in a two-axis view scrolled sideways through
    /// four thousand blank columns. It is drawn at the viewport now.
    @Test("A greedy view alone in a two-axis view draws no horizontal bar")
    func aGreedyViewAloneHasNoBar() {
        #expect(!hasHorizontalBar(TextEditor(text: .constant("hello"))))
    }

    /// Content that still fills whatever it is offered — here `.position`,
    /// which takes the whole offer as SwiftUI's does — ends the ladder with
    /// the budget as its answer, and the ladder says so: the scroll view
    /// draws it at the viewport rather than making the rung the canvas.
    @Test("Content that fills the probe's budget is drawn at the viewport")
    func contentThatFillsTheBudgetIsDrawnAtTheViewport() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let answer = naturalExtent(
            Text("hi").position(x: 2, y: 0), along: .horizontal,
            proposal: ProposedSize(width: nil, height: nil),
            context: RenderContext(
                availableWidth: 40, availableHeight: 4_096,
                environment: environment, tuiContext: tuiContext),
            startingBudget: 4_096)
        #expect(answer.fillsBudget, "precondition: the positioned view fills the offer")
        #expect(!hasHorizontalBar(Text("hi").position(x: 2, y: 0)))
    }

    /// And content with a width of its own is not mistaken for filling:
    /// wider than the viewport, it still gets its bar.
    @Test("Content with a width of its own is not taken for a filler")
    func contentWithAWidthIsNotAFiller() {
        #expect(hasHorizontalBar(Text(String(repeating: "0", count: 120))))
    }
}
