//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReservedIndicatorInsetTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Under `.scrollIndicators(.visible)` + `.scrollIndicatorStyle(.text)` a
/// `ScrollView` RESERVES the "N more" pair outside its content window, so every
/// line of that window is readable. The seek, the `.scrollPosition` sample and
/// the reveal must therefore charge no line for an indicator covering one.
///
/// They did. The one-line-per-edge inset those three read was derived from "the
/// text indicators are drawn" and never learned "over the content". So it went
/// on charging a line the reservation had already taken out: a `.top` seek
/// landed its row on the second content line, a `.bottom` position reported the
/// row above the last one, and focusing the last content line scrolled a control
/// that was already fully on screen. Only `pageDistance` had been taught the
/// difference.
@MainActor
@Suite("Reserved indicator lines charge no inset")
struct ReservedIndicatorInsetTests {
    /// Six lines: "▲ N more", four content lines, "▼ N more".
    private static let viewport = 6

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func rows(_ count: Int) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollIndicators(.visible)
        .scrollIndicatorStyle(.text)
    }

    /// On the very first frame, before anything scrolls: the bottom of the four
    /// content lines is row 3, and nothing covers it.
    @Test("A bottom-anchored position reports the last content line")
    func bottomSampleIsTheLastContentLine() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        let shown = renderFrame(
            rows(40).scrollPosition(binding, anchor: .bottom),
            tuiContext: tuiContext, focusManager: focusManager)
        let lastContentLine = shown.dropFirst(4).first
        #expect(lastContentLine == "row 3", "precondition: rows 0…3 between the pair: \(shown)")
        #expect(position.viewID(type: Int.self) == 3)
    }

    @Test("scrollTo(anchor: .top) puts the row on the first content line")
    func topSeekLandsOnTheFirstContentLine() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = rows(40).scrollPosition(binding)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        position.scrollTo(id: 20, anchor: .top)
        let landed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let firstContentLine = landed.dropFirst().first
        #expect(firstContentLine == "row 20", "directly under the above line: \(landed)")
        // …and the read-back names the same row. A seek fixed without the sample
        // would land at 20 and then report 21 from here.
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(position.viewID(type: Int.self) == 20)
    }

    @Test("Focusing the last content line does not scroll a control already on screen")
    func revealLeavesAVisibleControlWhereItIs() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { index in
                    Button("b\(index)e") {}.focusID("b\(index)")
                }
            }
        }
        .scrollIndicators(.visible)
        .scrollIndicatorStyle(.text)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        // b3 is the fourth content line: the last one, directly above "▼ N more".
        focusManager.focus(id: "b3")
        let shown = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let firstContentLine = shown.dropFirst().first ?? ""
        let lastContentLine = shown.dropFirst(4).first ?? ""
        #expect(firstContentLine.contains("b0e"), "nothing scrolled: \(shown)")
        #expect(lastContentLine.contains("b3e"), "the focused control is on screen: \(shown)")
    }
}
