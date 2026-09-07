//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuMeasureParityTests.swift
//
//  An inline `Menu` now reports its size from the plan `renderMenuColumn` makes
//  before it draws, rather than by drawing the whole column and reading the
//  buffer's dimensions. That is only right while the two agree to the cell, and
//  a disagreement is a menu laid out somewhere it does not draw — wrong cells,
//  not a crash. So: render the matrix, measure the matrix, compare.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A menu measures what it draws")
struct MenuMeasureParityTests {
    private func context(width: Int, height: Int) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// Rows both ways round: a menu whose widest row is its label, and one whose
    /// widest is an item, so the hug is decided in both places.
    @ViewBuilder
    private func items(count: Int, wide: Bool) -> some View {
        ForEach(0..<count, id: \.self) { index in
            Button(wide ? "Item number \(index) with a long name" : "It \(index)") {}
                .keyboardShortcut(index.isMultiple(of: 2) ? "a" : "b", modifiers: [])
        }
    }

    /// The sweep: narrow enough to clamp, tall enough to fit, short enough to
    /// scroll, and both hug directions.
    @Test(
        "the measured size is the rendered size",
        arguments: [1, 3, 12], [6, 12, 40])
    func measuredEqualsRendered(rows: Int, height: Int) {
        for wide in [true, false] {
            for width in [8, 20, 44, 120] {
                let view = Menu("A menu title") { items(count: rows, wide: wide) }
                    .menuStyle(.inline)
                let rendered = renderToBuffer(view, context: context(width: width, height: height))
                let measured = measureChild(
                    view, proposal: .unspecified, context: context(width: width, height: height))
                let place = "\(rows) rows, \(wide ? "wide" : "narrow"), \(width)x\(height)"
                #expect(
                    measured.width == rendered.width,
                    "\(place): measured \(measured.width) wide, drew \(rendered.width)")
                #expect(
                    measured.height == rendered.height,
                    "\(place): measured \(measured.height) tall, drew \(rendered.height)")
            }
        }
    }

    /// A proposal narrower than the context is what a stack hands a child it has
    /// already divided space between — the case the measure has to apply itself,
    /// since it no longer gets it for free from a render.
    @Test("a narrowed proposal is honoured", arguments: [6, 8, 10, 14, 18, 24, 30, 41])
    func proposalIsHonoured(proposedWidth: Int) {
        let view = Menu("Title") { items(count: 4, wide: true) }
            .menuStyle(.inline)
        let full = context(width: 120, height: 20)
        let measured = measureChild(
            view, proposal: ProposedSize(width: proposedWidth, height: nil), context: full)
        let rendered = renderToBuffer(view, context: context(width: proposedWidth, height: 20))
        #expect(measured.width == rendered.width, "at \(proposedWidth)")
        #expect(measured.height == rendered.height, "at \(proposedWidth)")
    }

    /// A menu taller than its budget scrolls inside its border, and reports the
    /// budget — not the content it holds.
    @Test("a menu taller than its budget reports the budget")
    func tallMenuReportsTheCap() {
        let view = Menu("Title") { items(count: 40, wide: false) }
            .menuStyle(.inline)
        for height in [6, 10, 14] {
            let rendered = renderToBuffer(view, context: context(width: 60, height: height))
            let measured = measureChild(
                view, proposal: .unspecified, context: context(width: 60, height: height))
            #expect(rendered.height == height, "drew \(rendered.height) in \(height)")
            #expect(measured.height == rendered.height, "at height \(height)")
            #expect(measured.width == rendered.width, "at height \(height)")
        }
    }

    /// The awkward content: a rule between groups, a row that declines focus, a
    /// destructive role, a label whose cells outnumber its characters, and one
    /// with nothing in it at all. Each of these takes a different path through
    /// the row, and the plan has to price all of them.
    @Test("awkward content still agrees", arguments: [10, 16, 28, 60, 120])
    func awkwardContentAgrees(width: Int) {
        for height in [5, 9, 30] {
            let view = Menu("菜单 title 🎛️") {
                Button("First") {}
                Divider()
                Button("Disabled row") {}.disabled(true)
                Button("Delete everything", role: .destructive) {}
                    .keyboardShortcut("d", modifiers: [])
                Button("宽宽宽宽宽宽") {}
                Button("") {}
            }
            .menuStyle(.inline)
            let rendered = renderToBuffer(view, context: context(width: width, height: height))
            let measured = measureChild(
                view, proposal: .unspecified, context: context(width: width, height: height))
            #expect(measured.width == rendered.width, "\(width)x\(height) width")
            #expect(measured.height == rendered.height, "\(width)x\(height) height")
        }
    }

    /// Every width from too-narrow-to-draw to far wider than the content, at the
    /// three heights that pick the fits / exactly-fills / scrolls arms. This is
    /// the sweep that found the reflow the natural height could not see: a
    /// hugging row is measured against the menu's whole interior, a drawn one
    /// against that interior less its hint column.
    @Test("the whole width sweep agrees", arguments: [4, 8, 14, 22])
    func everyWidthAgrees(rows: Int) {
        for height in [4, 7, 13, 25] {
            for width in 3...48 {
                let view = Menu("Menu") { items(count: rows, wide: width.isMultiple(of: 2)) }
                    .menuStyle(.inline)
                let rendered = renderToBuffer(view, context: context(width: width, height: height))
                let measured = measureChild(
                    view, proposal: .unspecified, context: context(width: width, height: height))
                #expect(
                    measured.width == rendered.width,
                    "\(rows) rows at \(width)x\(height): measured \(measured.width), drew \(rendered.width)")
                #expect(
                    measured.height == rendered.height,
                    "\(rows) rows at \(width)x\(height): measured \(measured.height), drew \(rendered.height)")
            }
        }
    }

    /// A `@ViewBuilder` label, which reaches the rows through `AnyView` rather
    /// than as a `Text` — a different measure path through the same plan.
    @Test("a @ViewBuilder row label agrees")
    func viewBuilderRowAgrees() {
        for width in [12, 30, 80] {
            let view = Menu {
                Button(action: {}, label: { Text("Composed").bold() })
                Button("Plain") {}
            } label: {
                Text("Head")
            }
            .menuStyle(.inline)
            let rendered = renderToBuffer(view, context: context(width: width, height: 12))
            let measured = measureChild(
                view, proposal: .unspecified, context: context(width: width, height: 12))
            #expect(measured.width == rendered.width, "at \(width)")
            #expect(measured.height == rendered.height, "at \(width)")
        }
    }
}
