//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PresentationVariantsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The three presentations that are not a plain sheet: an anchored `popover`, a
/// `fullScreenCover`, and the `presentationDetents` that decide a sheet's height.
///
/// What separates them is *where the content lands*, so that is what these
/// assert — an overlay's level, offset and dimming, not merely that something
/// was drawn.
@MainActor
@Suite("Presentation variants")
struct PresentationVariantsTests {

    private func context(width: Int = 40, height: Int = 20) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tuiContext in
            // A presentation needs a mouse dispatcher: the dismiss backdrop and
            // every click region go through it, and a popover declines to
            // present at all without one.
            environment.mouseEventDispatcher = MouseEventDispatcher()
            environment.terminalWidth = width
            environment.overlayContentHeight = height
            _ = tuiContext
        }
    }

    // MARK: - Popover

    @Test("A popover is an undimmed overlay anchored below its view")
    func popoverAnchorsBelow() {
        let buffer = renderToBuffer(
            Text("anchor")
                .popover(isPresented: .constant(true)) { Text("detail") },
            context: context())

        #expect(buffer.overlays.count == 1)
        let overlay = buffer.overlays[0]
        // A popover belongs beside the thing it came from, so it must NOT be
        // the centred, dimming presentation a sheet is.
        #expect(overlay.level == .popover)
        #expect(overlay.dimsBackground == false)
        #expect(overlay.centered == false)
        // Directly under the one-line anchor, declaring that line's height so
        // the compositor's flip and a ScrollView's culling both work.
        #expect(overlay.offsetY == 1)
        #expect(overlay.anchorHeight == 1)
    }

    @Test("arrowEdge chooses the side the popover sits on")
    func arrowEdgePlacesThePanel() {
        func offset(_ edge: Edge) -> (x: Int, y: Int) {
            let buffer = renderToBuffer(
                Text("anchor")
                    .popover(isPresented: .constant(true), arrowEdge: edge) { Text("d") },
                context: context())
            guard let overlay = buffer.overlays.first else { return (0, 0) }
            return (overlay.offsetX, overlay.offsetY)
        }

        // Below the anchor (its height is 1); above it by the panel's own
        // height; and beside it by the anchor's width either way.
        #expect(offset(.bottom).y == 1)
        #expect(offset(.top).y < 0)
        #expect(offset(.leading).x < 0)
        #expect(offset(.trailing).x > 0)
    }

    @Test("A dismissed popover adds no overlay")
    func dismissedPopoverIsInert() {
        let buffer = renderToBuffer(
            Text("anchor").popover(isPresented: .constant(false)) { Text("detail") },
            context: context())
        #expect(buffer.overlays.isEmpty)
        #expect(buffer.lines.first?.stripped.contains("anchor") == true)
    }

    // MARK: - Full-screen cover

    @Test("A cover fills the content area and dims nothing")
    func coverFillsTheScreen() {
        let height = 12
        let buffer = renderToBuffer(
            Text("page").fullScreenCover(isPresented: .constant(true)) { Text("cover") },
            context: context(width: 30, height: height))

        #expect(buffer.overlays.count == 1)
        let overlay = buffer.overlays[0]
        // Nothing shows through a cover, so dimming would be painting under an
        // opaque thing — and there is nowhere to drag it to.
        #expect(overlay.dimsBackground == false)
        #expect(overlay.offsetX == 0)
        #expect(overlay.offsetY == 0)
        #expect(overlay.content.height == height)
        #expect(overlay.content.width == 30)
    }

    /// Content smaller than the screen sits in the MIDDLE of it. The fixed
    /// `frame(width:height:)` the cover is built on defaults to `.topLeading`
    /// — deliberately, for fixed-width columns — so the cover has to ask for
    /// centring, and did not: a short message huddled in the top-left corner
    /// of an otherwise empty terminal.
    @Test("A cover centres content smaller than the screen")
    func coverCentresItsContent() {
        let height = 11
        let width = 21
        let buffer = renderToBuffer(
            Text("page").fullScreenCover(isPresented: .constant(true)) { Text("hi") },
            context: context(width: width, height: height))

        let lines = buffer.overlays[0].content.lines.map(\.stripped)
        let row = lines.firstIndex { $0.contains("hi") }
        #expect(row != nil, "cover content missing: \(lines)")
        guard let row else { return }
        let line = lines[row]
        // 11 rows, 1 of content → 5 above and 5 below; "hi" is 2 cells in 21 →
        // 9 before and 10 after (the odd cell falls to the trailing side, as
        // every centring here floors once).
        #expect(row == 5, "content row \(row), lines: \(lines)")
        let leading = line.prefix { $0 == " " }.count
        #expect(leading == 9, "leading spaces \(leading) in \(line.debugDescription)")
    }

    @Test("A sheet still dims and centres — the cover did not change it")
    func sheetIsUnchanged() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { Text("sheet") },
            context: context())
        #expect(buffer.overlays.count == 1)
        #expect(buffer.overlays[0].dimsBackground == true)
        #expect(buffer.overlays[0].centered == true)
    }

    // MARK: - Detents

    @Test("Detent heights are a floor of the extent, never over it")
    func detentArithmetic() {
        #expect(PresentationDetent.large.resolved(in: 20) == 20)
        #expect(PresentationDetent.medium.resolved(in: 20) == 10)
        // 7 × 0.5 = 3.5 → 3. Rounding up would ask for a row the arithmetic
        // downstream would then have to defend against.
        #expect(PresentationDetent.fraction(0.5).resolved(in: 7) == 3)
        #expect(PresentationDetent.height(4).resolved(in: 20) == 4)
        // Clamped at both ends: never taller than the screen, never zero.
        #expect(PresentationDetent.height(999).resolved(in: 20) == 20)
        #expect(PresentationDetent.fraction(0).resolved(in: 20) == 1)
    }

    /// A detent is a height for the sheet, and the sheet here is the content's
    /// own box — so the BOX is that tall, enclosing the leftover as empty
    /// interior. It used to be imposed as a fixed frame around the box instead,
    /// which is top-aligned: the dialog stayed content-sized and the remaining
    /// rows went out as blank, unstyled, opaque overlay lines that punched a
    /// hole through the page below it.
    @Test("A detent sizes the sheet's box, and the box encloses the slack")
    func detentSizesTheSheet() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("title") { Text("one line") }
                    .presentationDetents([.medium])
            },
            context: context(width: 30, height: 20))
        #expect(buffer.overlays.count == 1)
        // Half of 20, not the three rows the panel would take by itself.
        let lines = buffer.overlays[0].content.lines.map(\.stripped)
        #expect(lines.count == 10)
        // Every row belongs to the box: the last one is its bottom border, and
        // the slack rows before it carry side walls, not blanks.
        #expect(lines.last?.contains("─") == true, "last row is not the border: \(lines)")
        #expect(lines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                "a blank row escaped the box: \(lines)")
    }

    /// Content with no box has nothing to stretch, so it keeps its own size —
    /// and, crucially, gains no opaque skirt underneath it.
    @Test("Boxless sheet content keeps its size rather than gaining blank rows")
    func detentLeavesBoxlessContentAlone() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Text("one line").presentationDetents([.medium])
            },
            context: context(width: 30, height: 20))
        #expect(buffer.overlays[0].content.height == 1)
    }

    @Test("Without a selection the smallest detent wins")
    func smallestDetentIsTheDefault() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("t") { Text("x") }
                    .presentationDetents([.large, .medium, .height(5)])
            },
            context: context(width: 30, height: 20))
        #expect(buffer.overlays[0].content.height == 5)
    }

    @Test("A selection binding chooses among the detents")
    func selectionChoosesTheDetent() {
        // The terminal's stand-in for dragging a grabber: a bound selection.
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("t") { Text("x") }
                    .presentationDetents([.large, .medium], selection: .constant(.large))
            },
            context: context(width: 30, height: 20))
        #expect(buffer.overlays[0].content.height == 20)
    }

    /// The height belongs to the sheet's own box and to that box alone: a panel
    /// nested inside a detented one must not stretch to the sheet's height too.
    @Test("Only the outermost box takes the detent's height")
    func nestedBoxesDoNotAlsoStretch() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("outer") { Panel("inner") { Text("x") } }
                    .presentationDetents([.large])
            },
            context: context(width: 30, height: 20))
        let lines = buffer.overlays[0].content.lines.map(\.stripped)
        #expect(lines.count == 20)
        // The inner panel is three rows near the top, not a second 18-row box:
        // its bottom border lands well above the outer one.
        let borders = lines.enumerated().filter { $0.element.contains("─") }.map(\.offset)
        #expect(borders.count == 4, "expected two boxes' worth of borders: \(lines)")
        #expect(borders[2] < 8, "the inner box stretched too: \(lines)")
    }

    @Test("Detents are read only from the content's outermost view")
    func detentsMustBeOutermost() {
        // The same rule `.alignmentGuide` and `.zIndex` follow, and the reason
        // is the same: the value has to be readable without rendering, so it is
        // read off the type the presenter is handed. Buried under a `.padding`
        // it is invisible — the sheet sizes to its content instead, which is
        // the documented behaviour, not a silent half-application.
        let buried = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("t") { Text("x") }.presentationDetents([.large]).padding()
            },
            context: context(width: 30, height: 20))
        let outermost = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) {
                Panel("t") { Text("x") }.padding().presentationDetents([.large])
            },
            context: context(width: 30, height: 20))
        #expect(outermost.overlays[0].content.height == 20)
        #expect(buried.overlays[0].content.height < 20)
    }
}
