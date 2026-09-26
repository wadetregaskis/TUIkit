//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiftedDragPreviewFadeTests.swift
//
//  A lifted drag preview is a card over the page (`OverlayLayer.isOpaque`): the
//  root paints it on the page's colour and composites it covering what is under
//  it. So what it lifts is what the row or view draws, fades included, and the
//  card is behind every one of them: a label faded in a dragged row is lifted
//  faded toward the card, on the card, and nothing behind the card shows
//  through it (`Opacity as composition.md` §106).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A lifted drag preview lifts the fades its rows draw")
struct LiftedDragPreviewFadeTests {

    /// A page of `#`, so a glyph behind the card showing through it is unambiguous.
    private static var hashes: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12, id: \.self) { _ in Text(String(repeating: "#", count: 40)) }
        }
    }

    /// The label a dragged row or view draws: `ab` faded, `cd` not.
    private static var label: some View {
        HStack(spacing: 0) { Text("ab").opacity(0.3); Text("cd") }
    }

    /// The preview layer `WindowGroup.renderScene` floats for `session`, composited as
    /// the run loop composites it, and the cells of its first row, in truecolor.
    private func liftedRow(
        context: RenderContext, tui: TUIContext
    ) throws -> [PaintedCell] {
        try ColorDepth.withCurrent(.truecolor) {
            let scene = WindowGroup { Self.hashes }
            let buffer = scene.renderScene(context: context)
            let layer = try #require(buffer.overlays.first, "no preview layer was emitted")
            let composited = buffer.compositingOverlays(
                maxWidth: context.availableWidth, maxHeight: context.availableHeight,
                palette: context.environment.palette)
            let placed = layer.placed(maxWidth: context.availableWidth, maxHeight: context.availableHeight)
            let row = paintedCells(composited.lines[placed.y])
            return Array(row[placed.x..<min(row.count, placed.x + placed.content.width)])
        }
    }

    /// `row`, the preview's first, holds the label on the card: its letters in their
    /// own ink faded 30% of the way from the card, on the card — nothing of the page
    /// of `#` behind it — and `cd` unfaded beside them.
    private func expectLiftedFaded(_ row: [PaintedCell], palette: any Palette) throws {
        let start = try #require(row.firstIndex { $0.glyph == "c" }, "no label on the card: \(String(row.map(\.glyph)))") - 2
        #expect(start >= 0 && row[start].glyph == "a" && row[start + 1].glyph == "b", "the card holds \(String(row.map(\.glyph)))")
        let card = try #require(palette.background.rgbComponents)
        let ink = try #require(palette.foreground.opacity(0.3, over: palette.background).rgbComponents)
        for column in start..<(start + 2) {
            #expect(
                row[column].background == "\u{1B}[48;2;\(card.red);\(card.green);\(card.blue)m",
                "column \(column) is on \(row[column].background.debugDescription)")
            #expect(
                row[column].ink == .rgb(Int(ink.red), Int(ink.green), Int(ink.blue)),
                "column \(column) is in \(String(describing: row[column].ink))")
        }
    }

    /// A view's own preview, as `.draggable` hands it over — the view's buffer, its
    /// fades on it — lifted over the page. Before, the fades went to the compositor
    /// with the card and were resolved against the page BEHIND it: below one half the
    /// page's `#` won the faded cells, through the card.
    @Test("A faded label in a dragged view is lifted faded, on the card")
    func aDraggedViewsFadeIsLifted() throws {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        let session = try #require(context.environment.dragAndDropSession)
        session.beginFrame()
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: 4, y: 3)
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 8, y: 5)
        let preview = ColorDepth.withCurrent(.truecolor) { renderToBuffer(Self.label, context: context) }
        session.begin(payload: "label", preview: preview, grabX: 0, grabY: 0)
        try expectLiftedFaded(liftedRow(context: context, tui: tui), palette: context.environment.palette)
    }

    /// A `List` row carried on the pointer (`.cursor`): the row's lines were lifted
    /// alone, so its label was lifted at full strength.
    @Test("A faded label in a row carried on the pointer is lifted faded, on the card")
    func aCarriedRowsFadeIsLifted() throws {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.rowReorderFeedback = .cursor
        environment.scrollIndicatorStyle = .text
        environment.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
        var items = ["one", "two", "three"]
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            let list = List(selection: .constant(String?.none)) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 0) { Text("ab").opacity(0.3); Text("cd"); Text(item) }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 5)
            var context = RenderContext(availableWidth: 20, availableHeight: 7, environment: environment, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(list, context: context) }
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }
        let buffer = render()
        let first = try #require(buffer.lines.firstIndex { $0.stripped.contains("one") })
        let last = try #require(buffer.lines.firstIndex { $0.stripped.contains("three") })
        tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: first))
        tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: last))
        _ = render()
        let session = tui.dragAndDropSession
        #expect(session.active != nil, "the row is riding the pointer")
        let context = RenderContext(availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        try expectLiftedFaded(liftedRow(context: context, tui: tui), palette: environment.palette)
    }
}
