//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewIndicatorFloorTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A `ScrollView` too short for the "N more" pair decides so ONCE, from its
/// viewport, before anything is reserved out of it. That is the rule `List` and
/// `Table` already resolve theirs by: `ResolvedScrollIndicators.fitting(contentHeight:)`.
///
/// It used to decide three times. `.visible` reserved the two lines
/// unconditionally. The draw site then applied the three-line floor to the
/// content window the reservation had just shortened, so a four-line view
/// reserved two lines, found two left, drew no indicators and never gave the
/// lines back. And the seek asked the environment, which knows nothing of the
/// viewport's height, so a two-line view that draws no indicator still stepped
/// a `.top` seek past one.
@MainActor
@Suite("A short ScrollView's indicator floor")
struct ScrollViewIndicatorFloorTests {

    /// One frame, driven the way the run loop drives it: the seek and its
    /// adoption are render-time side effects.
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, height: Int, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: height,
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
    }

    /// Three lines or more keeps the pair and fills the viewport with it. Two
    /// drops the pair and gives the content every line, as `List` does. Five is
    /// the control: its content window was three lines even after the
    /// reservation, so it was already right.
    @Test("A .visible ScrollView fills a short viewport, with the pair or without it",
          arguments: 2...5)
    func visibleFillsAShortViewport(height: Int) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let drawn = renderFrame(
            rows(40).scrollIndicators(.visible).scrollIndicatorStyle(.text),
            height: height, tuiContext: tuiContext, focusManager: focusManager)
        let rowLines = drawn.filter { $0.hasPrefix("row ") }.count
        let first = drawn.first ?? ""
        let last = drawn.last ?? ""
        #expect(drawn.count == height, "a \(height)-line viewport drew \(drawn.count) lines: \(drawn)")
        if height >= ResolvedScrollIndicators.minimumTextHeight {
            #expect(first.contains("▲") && last.contains("▼"), "both lines at \(height): \(drawn)")
            #expect(rowLines == height - 2, "the rows between them: \(drawn)")
        } else {
            #expect(!first.contains("▲") && !last.contains("▼"), "no room for the pair: \(drawn)")
            #expect(rowLines == height, "the content gets every line: \(drawn)")
        }
    }

    /// Under three lines no indicator is drawn, so none may be charged for.
    /// `.automatic` never reserved anything, so this is the floor's other
    /// consumer: the seek stamped a line of headroom for an "▲ N more" line the
    /// frame did not draw, and the requested row landed on the SECOND line.
    @Test("A viewport too short for the pair seeks without headroom for it")
    func shortViewportSeekChargesNoIndicator() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = rows(40).scrollPosition(binding).scrollIndicatorStyle(.text)

        renderFrame(view, height: 2, tuiContext: tuiContext, focusManager: focusManager)
        position.scrollTo(id: 20, anchor: .top)
        let landed = renderFrame(view, height: 2, tuiContext: tuiContext, focusManager: focusManager)
        #expect(landed == ["row 20", "row 21"], "the row on the top line: \(landed)")
    }
}
