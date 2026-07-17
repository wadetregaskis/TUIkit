//  🖥️ TUIKit — Terminal UI Kit for Swift
//  UniformSeekWindowTests.swift
//
//  §5i/§6e of "Locating things without drawing them": a windowed lazy stack
//  of uniform rows renders a frame by arithmetic — the visible ordinals come
//  from a division, so the frame builds and measures O(window) rows, not N.
//  The extent is a verified hypothesis: any row measuring differently
//  falsifies it and the SAME frame re-walks exactly, so nothing wrong is
//  ever drawn (pinned by the mixed-height agreement test in
//  LayoutPlacingTests and the wrapped-row pin in LazyStackWindowingTests,
//  both of which route through the falsification path).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Counts row-builder invocations. @unchecked: driven on the main actor.
private final class BuildCounter: @unchecked Sendable {
    var calls = 0
}

@MainActor
@Suite("uniform seek windowing")
struct UniformSeekWindowTests {
    private static let rows = 100_000

    @discardableResult
    private func renderFrame(
        counter: BuildCounter, tuiContext: TUIContext, windowOffset: Int, spacing: Int = 0
    ) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<Self.rows, id: \.self) { i in
                counter.calls += 1
                return Text("row \(i)")
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: windowOffset, viewportHeight: 5)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.rows + 10,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("A frame deep in a 100k-row stack builds O(window) rows, not 100k")
    func framesBuildOnlyTheWindow() {
        let counter = BuildCounter()
        let tuiContext = TUIContext()

        let lines = renderFrame(counter: counter, tuiContext: tuiContext, windowOffset: 50_000)
        #expect(
            counter.calls < 30,
            "a windowed frame must not touch all 100k rows; built \(counter.calls)")

        // And it is CORRECT: rows land at their exact arithmetic positions.
        #expect(lines.count == Self.rows, "full-height buffer (Stage 6 shrinks this)")
        #expect(lines[50_000] == "row 50000")
        #expect(lines[50_004] == "row 50004")
        #expect(lines[49_999] == "row 49999", "top margin row")
        #expect(lines[50_005] == "row 50005", "bottom margin row")
        #expect(lines[49_998].isEmpty && lines[50_006].isEmpty, "beyond the margin is blank")

        // Steady state stays cheap: the hypothesis is persisted, so the next
        // frame doesn't even re-seed.
        let before = counter.calls
        renderFrame(counter: counter, tuiContext: tuiContext, windowOffset: 50_001)
        #expect(counter.calls - before < 20, "scrolling one line builds a handful of rows")
    }

    @Test("Spacing participates in the arithmetic")
    func spacingIsExact() {
        let counter = BuildCounter()
        let tuiContext = TUIContext()
        let lines = renderFrame(
            counter: counter, tuiContext: tuiContext, windowOffset: 40, spacing: 1)
        // pitch = 2: row k sits at line 2k.
        #expect(lines[40] == "row 20")
        #expect(lines[42] == "row 21")
        #expect(lines[41].isEmpty, "the spacing line between rows is blank")
        #expect(counter.calls < 30)
    }

    @Test("The focus-target key parser respects path boundaries")
    func rowKeyParsing() {
        typealias Core = _VStackCore<Text>
        #expect(Core.rowKey(
            inFocusID: "button-Root/Stack/Button<Text>[42]/Inner",
            belowStackPath: "Root/Stack") == "42")
        #expect(Core.rowKey(
            inFocusID: "button-Root/Stack/Button<Text>[42]",
            belowStackPath: "Root/Stack") == "42")
        // A key under a DEEPER stack must not match this one's path…
        #expect(Core.rowKey(
            inFocusID: "button-Root/Stack/Inner/Sub[7]/Leaf",
            belowStackPath: "Root/Stack") == nil,
            "the key belongs to Sub, not to Stack's own row component")
        // …and explicit ids embed no path at all.
        #expect(Core.rowKey(inFocusID: "save-button", belowStackPath: "Root/Stack") == nil)
    }
}
