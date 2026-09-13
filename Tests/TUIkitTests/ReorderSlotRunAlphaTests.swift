//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReorderSlotRunAlphaTests.swift
//
//  A row in hand is drawn only at the slot, as a faint copy rebuilt from its lines
//  and claims. A several-alpha border states its alpha only on its runs, which the
//  copy leaves behind, so the held row's border drew at full strength (§52, §69.4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A row in hand keeps what its runs said about alpha")
struct ReorderSlotRunAlphaTests {

    /// The order, in a reference type so `onMove` writes back where the render reads.
    @MainActor
    private final class Rows {
        var items = ["row0", "row1", "row2"]
    }

    /// One colour at two alphas, drawn at the faded frame, for the reason
    /// `ListBreathingRowRunAlphaTests` gives: at the opaque one there is nothing to leave.
    private static let border = AnimatedColor(
        frames: [Color.rgb(200, 40, 40), Color.rgb(200, 40, 40).opacity(0.5)], step: 1)

    /// Picked up from the keyboard and not yet moved: the slot sits where row 0 was,
    /// holding its faint copy. `ListReorderFixture`'s shape, with bordered rows, which
    /// the shared fixture does not draw.
    @Test("A List row held from the keyboard keeps its several-alpha border's alpha in the slot")
    func heldRowLeavesItsAlpha() throws {
        let rows = Rows()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.rowReorderFeedback = .dimmed
        env.scrollIndicatorStyle = .text
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)

        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            let list = List(selection: .constant(String?.none)) {
                ForEach(rows.items, id: \.self) { Text($0).border(Self.border) }
                    .onMove { rows.items.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 12)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 14, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(list, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        _ = render()
        _ = env.focusManager?.dispatchKeyEvent(KeyEvent(key: .character("r"), ctrl: true))
        let held = render()

        // The premise: the copy is in the slot, on lines of its own.
        let slotLines = Set(held.lines.indices.filter { held.lines[$0].contains(ANSIRenderer.dim) })
        try #require(!slotLines.isEmpty, "no faint copy in the slot: \(held.lines.map(\.stripped))")

        // What was missing: the border's drawn alpha on every line of the copy.
        let owedLines = Set(held.opacityRegions.filter { $0.inkOpacity < 1 }.map(\.offsetY))
        #expect(
            slotLines.isSubset(of: owedLines),
            "the held row's border owes nothing on slot lines \(slotLines.subtracting(owedLines).sorted())")
    }
}
