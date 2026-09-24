//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnchoredTallRowTests.swift
//
//  A row TALLER than the viewport, in a lazy stack past the anchored-window
//  threshold: every line of it is drawn as the scroll view passes over it. The
//  anchored path measured each row at its ideal height but drew it at the
//  viewport's height and padded the rest with blank lines, so everything below
//  a tall row's first screenful was never drawn — a group of forty lines in a
//  twelve-line viewport showed twelve and then blank space where the other
//  twenty-eight belonged. Below the threshold the exact path drew them all,
//  which is why 200 such groups looked right and 300 did not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("anchored windowing: rows taller than the viewport")
struct AnchoredTallRowTests {
    /// Past the 256-row threshold, so the anchored path draws the stack.
    private static let groups = 300
    private static let viewport = 12

    /// The lines one frame draws, stripped, for a stack of groups where group
    /// `g` is `40 + g % 5` one-line rows — every group taller than the viewport.
    private func renderFrame(tuiContext: TUIContext, offset: Int) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<(40 + group % 5), id: \.self) { row in
                        Text("g\(group) r\(row)")
                    }
                }
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.groups * 45,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// What the scroll view's clip would show at `offset`.
    private func visible(_ lines: [String], at offset: Int) -> [String] {
        guard lines.count >= offset + Self.viewport else { return [] }
        return Array(lines[offset..<(offset + Self.viewport)])
    }

    @Test("Every line of a tall row is drawn as the viewport passes over it")
    func tallRowIsDrawnWhole() {
        let tuiContext = TUIContext()
        // Group 0 is forty lines: offsets 0, 12, 24 and 28 between them show
        // all of it, and each must show exactly the lines it covers.
        for offset in [0, 1, 12, 24, 28] {
            let shown = visible(renderFrame(tuiContext: tuiContext, offset: offset), at: offset)
            let expected = (offset..<(offset + Self.viewport)).map { "g0 r\($0)" }
            #expect(shown == expected, "offset \(offset) showed \(shown)")
        }
    }

    @Test("A tall row straddling the viewport's top is drawn from where the clip starts")
    func tallRowAcrossTheTopIsDrawn() {
        let tuiContext = TUIContext()
        // Group 0 is 40 lines and group 1 is 41, so offset 70 is group 1's
        // line 30: the viewport opens inside it and runs on into group 2.
        let offset = 70
        let shown = visible(renderFrame(tuiContext: tuiContext, offset: offset), at: offset)
        let expected = (30..<41).map { "g1 r\($0)" } + ["g2 r0"]
        #expect(shown == expected, "offset \(offset) showed \(shown)")
    }
}
