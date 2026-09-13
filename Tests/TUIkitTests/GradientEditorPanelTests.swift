//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientEditorPanelTests.swift
//
//  The gradient editor's pure stop mutations (duplicate / remove / move, with
//  the ≥2-stop floor, the selection follow, and what happens to the stops'
//  POSITIONS), plus render smokes proving the dialog embeds the colour-panel
//  body (no nested dialog) and previews with the shared gradient
//  interpolation.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("GradientEditorPanel — stop mutations")
struct GradientEditorPanelMutationTests {

    typealias Panel = GradientEditorPanel

    private let teal = Color.rgb(60, 200, 190)
    private let blue = Color.rgb(80, 110, 240)
    private let violet = Color.rgb(170, 70, 220)

    private func gradient(_ colours: [Color]) -> Gradient { Gradient(colors: colours) }
    private func colours(_ gradient: Gradient) -> [Color] { gradient.stops.map(\.color) }
    private func locations(_ gradient: Gradient) -> [Double] { gradient.stops.map(\.location) }

    /// The copy lands in the gap beside the stop and NOTHING ELSE MOVES —
    /// which is the only thing "split here" can mean once a stop has a
    /// position, and what every gradient editor does.
    @Test("Duplicating inserts a copy in the gap beside the stop and selects it")
    func duplicate() {
        let (updated, selected) = Panel.duplicatingStop(gradient([teal, blue]), at: 0)
        #expect(colours(updated) == [teal, teal, blue])
        #expect(locations(updated) == [0, 0.5, 1], "the copy halves the gap after it")
        #expect(selected == 1)

        // The last stop has no gap after it, so the copy takes the one before
        // — a stop stacked exactly on another would be invisible until edited
        // and then a hard edge, which is not what the button says.
        let (atEnd, endSelected) = Panel.duplicatingStop(gradient([teal, blue]), at: 1)
        #expect(colours(atEnd) == [teal, blue, blue])
        #expect(locations(atEnd) == [0, 0.5, 1])
        #expect(endSelected == 1, "the copy is selected, and it is the one in the gap")
    }

    /// Uneven spacing is the case the even-`[Color]` version could not have:
    /// the existing stops must stay exactly where they were put.
    @Test("Duplicating leaves an uneven gradient's other stops where they are")
    func duplicatePreservesPositions() {
        let uneven = Gradient(stops: [
            .init(color: teal, location: 0), .init(color: blue, location: 0.2),
            .init(color: violet, location: 1),
        ])
        let (updated, _) = Panel.duplicatingStop(uneven, at: 1)
        #expect(locations(updated) == [0, 0.2, 0.6, 1])
        #expect(colours(updated) == [teal, blue, blue, violet])
    }

    /// The floor is ONE, because one stop is a solid colour and this dialog
    /// can express one — the same edit the Gradient switch makes.
    @Test("Removing stops at one, and one stop is a solid colour")
    func removeFloor() {
        let (solid, solidSelected) = Panel.removingStop(gradient([teal, blue]), at: 0)
        #expect(colours(solid) == [blue], "taking one of two leaves a solid colour")
        #expect(solidSelected == 0)

        let (unchanged, _) = Panel.removingStop(solid, at: 0)
        #expect(colours(unchanged) == [blue], "and there is nothing below one")

        let (updated, selected) = Panel.removingStop(gradient([teal, blue, violet]), at: 2)
        #expect(colours(updated) == [teal, blue])
        #expect(locations(updated) == [0, 0.5], "the survivors keep their own positions")
        #expect(selected == 1, "removing the last stop pulls the selection back in range")
    }

    /// Reordering moves COLOURS between positions. The stops are where they
    /// are; what "move this stop left" means on screen is that its colour is
    /// now the one further left, and the ramp keeps its shape.
    @Test("Flipping reverses an evenly spaced ramp's colours and keeps its positions exactly")
    func flipEvenRamp() {
        let ramp = gradient([teal, blue, violet])
        let (flipped, selected) = Panel.flippingStops(ramp, at: 0)
        #expect(colours(flipped) == [violet, blue, teal])
        #expect(locations(flipped) == locations(ramp), "bit-identical positions")
        #expect(selected == 2, "the selection follows teal to the far end")
    }

    @Test("Flipping a lopsided ramp mirrors its positions")
    func flipLopsidedRamp() {
        let ramp = Gradient(stops: [
            Gradient.Stop(color: teal, location: 0),
            Gradient.Stop(color: blue, location: 0.2),
            Gradient.Stop(color: violet, location: 1),
        ])
        let (flipped, selected) = Panel.flippingStops(ramp, at: 1)
        #expect(colours(flipped) == [violet, blue, teal])
        let mirrored = locations(flipped)
        #expect(mirrored.count == 3 && mirrored[0] == 0 && abs(mirrored[1] - 0.8) < 1e-12 && mirrored[2] == 1, "\(mirrored)")
        #expect(selected == 1, "blue stays the middle stop")
    }

    @Test("Flipping an evenly spaced ramp twice gives back the same ramp")
    func flipTwiceIsIdentity() {
        let ramp = gradient([teal, blue, violet, teal])
        let once = Panel.flippingStops(ramp, at: 1)
        let twice = Panel.flippingStops(once.0, at: once.selected)
        #expect(colours(twice.0) == colours(ramp))
        #expect(locations(twice.0) == locations(ramp))
        #expect(twice.selected == 1)
    }

    @Test("Moving swaps with the neighbour and follows the stop")
    func move() {
        let (right, rightSelected) = Panel.movingStop(gradient([teal, blue, violet]), at: 0, by: 1)
        #expect(colours(right) == [blue, teal, violet])
        #expect(locations(right) == [0, 0.5, 1], "the positions did not move")
        #expect(rightSelected == 1)

        let (left, leftSelected) = Panel.movingStop(gradient([teal, blue, violet]), at: 2, by: -1)
        #expect(colours(left) == [teal, violet, blue])
        #expect(leftSelected == 1)

        // Edges are no-ops (the buttons are disabled there anyway).
        let (unmoved, unmovedSelected) = Panel.movingStop(gradient([teal, blue]), at: 0, by: -1)
        #expect(colours(unmoved) == [teal, blue])
        #expect(unmovedSelected == 0)
    }

    @Test("Drag-moving relocates the stop (insert, not swap) and follows it")
    func moveFromTo() {
        let white = Color.rgb(255, 255, 255)
        let four = gradient([teal, blue, violet, white])

        // Forward: the stops between source and destination shift left.
        let (forward, forwardSelected) = Panel.movingStop(four, from: 0, to: 2)
        #expect(colours(forward) == [blue, violet, teal, white], "insert semantics, not a swap")
        #expect(forwardSelected == 2)

        // Backward: they shift right.
        let (backward, backwardSelected) = Panel.movingStop(four, from: 3, to: 1)
        #expect(colours(backward) == [teal, white, blue, violet])
        #expect(backwardSelected == 1)

        // Same place and out-of-range are no-ops.
        let (samePlace, _) = Panel.movingStop(gradient([teal, blue]), from: 1, to: 1)
        #expect(colours(samePlace) == [teal, blue])
        let (outOfRange, outSelected) = Panel.movingStop(gradient([teal, blue]), from: 5, to: 0)
        #expect(colours(outOfRange) == [teal, blue])
        #expect(outSelected == 1, "selection clamps into range")
    }

    // MARK: - Solid ⇄ gradient

    /// The switch is the two edits at the floor, so it must agree with them:
    /// collapsing keeps the SELECTED stop, and expanding a solid gives a
    /// two-stop ramp spanning the whole range.
    @Test("Collapsing keeps the selected stop; expanding it spans the range")
    func solidRoundTrip() {
        let solid = Panel.collapsedToSolid(gradient([teal, blue, violet]), at: 1)
        #expect(colours(solid) == [blue], "the selected stop is the one that survives")
        #expect(locations(solid) == [0], "a lone stop's position cannot be seen, so it is 0")

        let (expanded, selected) = Panel.duplicatingStop(solid, at: 0)
        #expect(colours(expanded) == [blue, blue])
        #expect(locations(expanded) == [0, 1], "expanding spans the whole ramp")
        #expect(selected == 1)
    }

    @Test("An out-of-range selection still collapses to something drawable")
    func collapseClamps() {
        let solid = Panel.collapsedToSolid(gradient([teal, blue]), at: 9)
        #expect(colours(solid) == [teal], "the first stop stands in")
        #expect(Panel.collapsedToSolid(Gradient(stops: []), at: 0).stops.isEmpty)
    }

    // MARK: - Persistence

    /// The migration, and it is the whole of it: a stop written without a
    /// position reads as evenly spaced, which is what the old bare-hex format
    /// meant back when a gradient WAS an even `[Color]`.
    @Test("Recents written in the old format read as evenly-spaced gradients")
    func recentsMigrateByBeingRead() {
        let decoded = Panel.decodeRecents("FF0000,00FF00,0000FF;112233,445566")
        #expect(decoded.count == 2)
        #expect(colours(decoded[0]) == [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)])
        #expect(locations(decoded[0]) == [0, 0.5, 1], "even spacing is what the old format meant")
        #expect(locations(decoded[1]) == [0, 1])
    }

    @Test("Positions survive the round trip")
    func recentsRoundTrip() {
        let uneven = Gradient(stops: [
            .init(color: .rgb(255, 0, 0), location: 0),
            .init(color: .rgb(0, 255, 0), location: 0.125),
            .init(color: .rgb(0, 0, 255), location: 1),
        ])
        let decoded = Panel.decodeRecents(Panel.encodeRecents([uneven]))
        #expect(decoded.count == 1)
        #expect(decoded.first == uneven, "encode → decode is not the identity")
    }

    @Test("A mixed or corrupt entry degrades rather than throwing the list away")
    func recentsDegrade() {
        // One unreadable colour inside an otherwise good entry; a whole entry
        // with too few stops; and a stop with an unparseable position.
        let decoded = Panel.decodeRecents("FF0000@0.000,zzz,0000FF@1.000;AABBCC;FF0000@x,0000FF@1")
        #expect(decoded.count == 2, "the one-stop entry drops, the other two survive")
        #expect(colours(decoded[0]) == [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        #expect(decoded[1].stops.first?.location == 0, "an unreadable position falls back to even")
    }
}

@MainActor
@Suite("GradientEditorPanel — rendering")
struct GradientEditorPanelRenderTests {

    @Test("The dialog embeds the colour-panel body (stops, actions, tabs, one Done)")
    func rendersEmbeddedEditor() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let buffer = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")

        #expect(text.contains("Gradient"), "the default title: \(text.prefix(200))")
        // The stop strip: one bare swatch per stop, the first (selected)
        // carrying the centre bullet.
        #expect(text.contains("█●█"))
        // The action row.
        for glyph in ["+", "−", "◀", "▶"] {
            #expect(text.contains(glyph), "missing action '\(glyph)'")
        }
        // The embedded colour panel: its hex read-out shows the SELECTED stop
        // (red), and its tab strip is present — inside this dialog, not nested.
        #expect(text.contains("#FF0000"), "the embedded panel edits stop 1")
        #expect(text.contains("RGB") && text.contains("HSL"), "the colour tabs are embedded")
        #expect(
            text.components(separatedBy: "Done").count == 2,
            "exactly one Done footer — no nested dialog")
    }

    @Test("The preview strip uses the shared gradient interpolation")
    func previewUsesSharedInterpolation() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let buffer = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
        let text = buffer.lines.joined(separator: "\n")

        // Both endpoints appear as foreground colours in the preview strip,
        // and so does an interior cell computed exactly as the strip does: the
        // ramp overload, 36 cells, cell 18.
        let interior = TrackRenderer.gradientColor(
            ramp, index: 18, span: 36, fallback: .rgb(0, 0, 0), depth: ColorDepth.current)
        let components = interior.rgbComponents!
        #expect(text.contains("38;2;255;0;0"), "the left endpoint is drawn")
        #expect(text.contains("38;2;0;0;255"), "the right endpoint is drawn")
        #expect(
            text.contains("38;2;\(components.red);\(components.green);\(components.blue)"),
            "an interior cell matches TrackRenderer.gradientColor")
    }

    @Test("The preview updates live when a stop's colour changes (no stale memo)")
    func previewUpdatesLive() {
        // Regression: the preview rows were built under a ForEach over row
        // numbers, so the element-keyed render memo (keyed 0/1) served the old
        // colours until something else invalidated the cache — edits through
        // the embedded colour panel never showed until the selection moved.
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))

        // ONE context (one render cache) across both renders, like the live
        // render loop between frames.
        let context = makeRenderContext(width: 70, height: 45)
        _ = renderToBuffer(panel, context: context)
        ramp.stops[0].color = .rgb(0, 255, 0)  // the edit the colour panel would make
        let after = renderToBuffer(panel, context: context)

        // Scope to the PREVIEW rows (the only lines whose stripped content
        // holds the full 36-cell block run) — the RGB sliders legitimately
        // sweep through pure red whatever the stops are.
        let fullRun = String(repeating: "█", count: 36)
        let previewLines = after.lines.filter { $0.stripped.contains(fullRun) }
        #expect(previewLines.count == 2, "both preview rows present")
        #expect(
            previewLines.allSatisfy { $0.contains("38;2;0;255;0") },
            "the edited endpoint is drawn")
        #expect(
            previewLines.allSatisfy { !$0.contains("38;2;255;0;0") },
            "no preview cell still shows the OLD endpoint colour")
    }

    @Test("Stop chips are bare 3-cell swatches; the centre cell carries the selection bullet")
    func stopChipGeometry() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let buffer = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
        let strip = buffer.lines.first { $0.stripped.contains("█●█") }
        #expect(strip != nil, "the stop strip renders with the selected chip's bullet")
        guard let strip else { return }
        let stripped = strip.stripped

        // Selected chip: a bullet dead-centre in its swatch. Unselected
        // chips: unbroken colour. Single-space gaps, gradient order, and NO
        // numbering, rings, or reserved indicator columns beside the swatch.
        #expect(stripped.contains("█●█ ███ ███"), "|\(stripped)|")
        #expect(stripped.filter { $0 == "●" }.count == 1, "exactly one selection bullet: |\(stripped)|")

        // The raw line: the bullet sits ON the selected stop's colour (red
        // backdrop), and the other chips draw in their own stop colours.
        #expect(strip.contains("48;2;255;0;0"), "the bullet cell keeps stop 1's red behind it")
        #expect(strip.contains("38;2;0;255;0"), "stop 2's swatch in green")
        #expect(strip.contains("38;2;0;0;255"), "stop 3's swatch in blue")
    }

    @Test("A divider separates the gradient library from the colour editor")
    func libraryDividerPresent() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let lines = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
            .lines.map(\.stripped)

        // The section divider: a solid ─ rule at the library column's width,
        // on a row of its own. (Dialog border rows never match: their runs
        // terminate in corner/junction glyphs.)
        let rules = lines.flatMap { line in
            line.split(separator: " ").filter { $0.allSatisfy { $0 == "─" } }.map(\.count)
        }
        #expect(rules.contains(36), "the library-closing rule renders (runs: \(rules))")

        // Regression: the divider must NOT stretch the content-hugging
        // dialog — an unconstrained (width-flexible) Divider inflates it to
        // the full proposed width.
        let dialogWidth = lines.first { $0.contains("╭") }?.count ?? 0
        #expect(dialogWidth < 70, "the dialog hugs its content (got \(dialogWidth) of 70)")
    }

    @Test("Dragging a chip onto another reorders the stops; a bare click still selects")
    func dragReordersStops() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))

        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 70, availableHeight: 45, environment: env, tuiContext: tui
        ).isolatingRenderCache()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        // One frame: render, publish regions (the buffer is the root here,
        // so its region offsets ARE absolute), locate the chip strip.
        func renderFrame() -> (y: Int, columns: [Int]) {
            tui.dragAndDropSession.beginFrame()
            let buffer = renderToBuffer(panel, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            let stripped = buffer.lines.map(\.stripped)
            let y = stripped.firstIndex { $0.contains("█●█") }
            #expect(y != nil, "the stop strip renders")
            guard let y else { return (0, []) }
            // Chip columns: each chip is 3 cells with 1-cell gaps, so chip
            // starts sit at pitch 4 from the first block cell.
            let line = stripped[y]
            let first = line.distance(
                from: line.startIndex,
                to: line.range(of: "█")!.lowerBound)
            return (y, [first, first + 4, first + 8])
        }

        var (y, columns) = renderFrame()

        // A bare click (press + release, no movement) on the THIRD chip
        // selects it — through the draggable wrapper.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: columns[2] + 1, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: columns[2] + 1, y: y))
        (y, columns) = renderFrame()
        let strip = renderToBuffer(panel, context: context).lines.map(\.stripped)[y]
        #expect(strip.contains("███ ███ █●█"), "click through .draggable selects: |\(strip)|")

        // Drag the FIRST chip: the reorder is LIVE — the stop moves the
        // moment the cursor reaches another slot, before any release.
        // Re-render between events, exactly like the live loop (consumed
        // events request a render); the drag's coordinates stay anchored to
        // the pressed chip's original region (press capture) throughout.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: columns[0] + 1, y: y))
        (y, columns) = renderFrame()
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: columns[1] + 1, y: y))
        #expect(
            ramp.stops.map(\.color) == [.rgb(0, 255, 0), .rgb(255, 0, 0), .rgb(0, 0, 255)],
            "reaching slot 2 moves the stop immediately, mid-drag")
        (y, columns) = renderFrame()
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: columns[2] + 1, y: y))
        #expect(
            ramp.stops.map(\.color) == [.rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 0, 0)],
            "following the cursor to slot 3, still mid-drag")
        (y, columns) = renderFrame()
        // Dragging far PAST the strip's right edge holds the end slot, and
        // a wild Y is clamped to the (single) row — tolerance by design.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: columns[2] + 30, y: y + 7))
        #expect(
            ramp.stops.map(\.color) == [.rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 0, 0)],
            "end slot held")
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: columns[2] + 1, y: y))
        #expect(
            ramp.stops.map(\.color) == [.rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 0, 0)],
            "release keeps the live order")

        // The selection followed the dragged stop to the end.
        (y, columns) = renderFrame()
        let after = renderToBuffer(panel, context: context).lines.map(\.stripped)[y]
        #expect(after.contains("███ ███ █●█"), "selection rides the dragged stop: |\(after)|")
    }

    @Test("Live-drag geometry: X picks the slot, Y the nearest row")
    func dragSlotGeometry() {
        // Single row (3 chips at origins 0/4/8, centres 1/5/9): X decides,
        // Y is irrelevant however wild.
        #expect(GradientEditorPanel.dragSlot(forX: 1, y: 0, count: 3) == 0)
        #expect(GradientEditorPanel.dragSlot(forX: 4, y: -5, count: 3) == 1, "gap maps to nearest")
        #expect(GradientEditorPanel.dragSlot(forX: 9, y: 12, count: 3) == 2)
        #expect(GradientEditorPanel.dragSlot(forX: -10, y: 0, count: 3) == 0, "clamps left")
        #expect(GradientEditorPanel.dragSlot(forX: 99, y: 0, count: 3) == 2, "clamps right")

        // Ten chips wrap (9 per 36-cell row): row 0 holds 0-8, row 1 holds 9.
        let rows = GradientEditorPanel.chipRows(count: 10)
        #expect(rows == [[0, 1, 2, 3, 4, 5, 6, 7, 8], [9]])
        // Y above the strip → row 0; below → row 1 (the nearest row).
        #expect(GradientEditorPanel.dragSlot(forX: 0, y: -3, count: 10) == 0)
        #expect(GradientEditorPanel.dragSlot(forX: 0, y: 9, count: 10) == 9)
        // Row 1 is centred: its single chip is the answer at any X in row 1.
        #expect(GradientEditorPanel.dragSlot(forX: 0, y: 1, count: 10) == 9)
        #expect(GradientEditorPanel.dragSlot(forX: 34, y: 1, count: 10) == 9)

        // chipStripOrigin agrees with the mapping: a chip's own centre maps
        // back to itself.
        for index in 0..<10 {
            let origin = GradientEditorPanel.chipStripOrigin(of: index, count: 10)
            #expect(
                GradientEditorPanel.dragSlot(forX: origin.x + 1, y: origin.y, count: 10) == index,
                "chip \(index) round-trips")
        }
    }

    @Test("The footer offers Cancel alongside Done")
    func footerHasCancel() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let text = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
            .lines.map(\.stripped).joined(separator: "\n")
        #expect(text.contains("Cancel"))
        #expect(text.components(separatedBy: "Done").count == 2, "exactly one Done")
    }
}

@MainActor
@Suite("GradientEditorPanel — chip wrapping")
struct GradientEditorPanelWrappingTests {

    typealias Panel = GradientEditorPanel

    @Test("Items pack greedily into rows within the budget")
    func greedyPacking() {
        // 5 items of width 10, spacing 1, budget 36: 10+1+10+1+10 = 32 fits,
        // adding a fourth (43) does not.
        let rows = Panel.wrappedRows(itemWidths: Array(repeating: 10, count: 5), spacing: 1, budget: 36)
        #expect(rows == [[0, 1, 2], [3, 4]])
    }

    @Test("Everything fits on one row when it can")
    func singleRow() {
        let rows = Panel.wrappedRows(itemWidths: [6, 6, 6], spacing: 1, budget: 36)
        #expect(rows == [[0, 1, 2]])
    }

    @Test("An over-budget item still gets a row of its own")
    func overBudgetItem() {
        let rows = Panel.wrappedRows(itemWidths: [40, 6], spacing: 1, budget: 36)
        #expect(rows == [[0], [1]], "never drop an item, however wide")
    }

    @Test("No items, no rows")
    func empty() {
        #expect(Panel.wrappedRows(itemWidths: [], spacing: 1, budget: 36).isEmpty)
    }
}

@MainActor
@Suite("GradientEditorPanel — presets & recents")
struct GradientEditorPanelRecentsTests {

    typealias Panel = GradientEditorPanel

    private let a = Gradient(colors: [.rgb(1, 1, 1), .rgb(2, 2, 2)])
    private let b = Gradient(colors: [.rgb(3, 3, 3), .rgb(4, 4, 4)])

    @Test("Applying records at the front; re-applying moves to the front (MRU)")
    func mruOrdering() {
        var recents = Panel.recordingRecent(a, in: [])
        recents = Panel.recordingRecent(b, in: recents)
        #expect(recents == [b, a], "most recent first")
        recents = Panel.recordingRecent(a, in: recents)
        #expect(recents == [a, b], "re-applying moves to the front, no duplicate")
    }

    @Test("The list caps at the limit, evicting the least recently used")
    func lruEviction() {
        var recents: [Gradient] = []
        let gradients = (0..<12).map { n in
            Gradient(colors: [.rgb(UInt8(n), 0, 0), .rgb(0, UInt8(n), 0)])
        }
        for gradient in gradients {
            recents = Panel.recordingRecent(gradient, in: recents)
        }
        #expect(recents.count == Panel.recentLimit)
        #expect(recents.first == gradients.last, "newest at the front")
        #expect(
            !recents.contains(gradients[0]) && !recents.contains(gradients[1]),
            "the two least recently used were evicted")
    }

    @Test("Presets and non-gradients are never recorded")
    func exclusions() {
        for preset in Panel.presets {
            #expect(Panel.recordingRecent(preset, in: []).isEmpty,
                    "presets already have a home above the rule")
        }
        #expect(
            Panel.recordingRecent(Gradient(colors: [.rgb(1, 1, 1)]), in: []).isEmpty,
            "one stop is a solid colour, and a solid colour is not worth recalling")
    }

    @Test("Recents survive an encode/decode round trip; junk entries drop")
    func codecRoundTrip() {
        let recents = [a, b]
        let decoded = Panel.decodeRecents(Panel.encodeRecents(recents))
        #expect(decoded == recents)

        // Junk: an empty entry, a single-stop entry, and a malformed hex.
        let junk = Panel.decodeRecents(";010101;ZZZZZZ,010101;010101,020202")
        #expect(junk == [Gradient(colors: [.rgb(1, 1, 1), .rgb(2, 2, 2)])])
    }

    /// The union surface, on screen: a one-stop gradient IS a colour, so the
    /// dialog drops the rows that only mean something to a ramp and leaves the
    /// colour editor — with the switch to expand it again.
    @Test("A one-stop gradient renders as a colour editor with a Gradient switch")
    func solidModeHidesTheRampRows() {
        func render(_ ramp: Gradient) -> String {
            var stored = ramp
            var presented = true
            let panel = GradientEditorPanel(
                gradient: Binding(get: { stored }, set: { stored = $0 }),
                isPresented: Binding(get: { presented }, set: { presented = $0 }))
            return renderToBuffer(panel, context: makeRenderContext(width: 70, height: 50))
                .lines.map(\.stripped).joined(separator: "\n")
        }

        let solid = render(Gradient(colors: [.rgb(255, 0, 0)]))
        let ramp = render(Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)]))

        // The switch is in both, and localized — a raw `label.gradient` on
        // screen is the failure this catches.
        for text in [solid, ramp] {
            #expect(text.contains("Gradient"), "the switch's label")
            #expect(!text.contains("label.gradient"), "the key leaked instead of its translation")
        }
        #expect(solid.contains("□"), "solid: the switch reads off")
        #expect(ramp.contains("■"), "a ramp: the switch reads on")

        // The ramp-only rows: a stop strip with a selection bullet, and the
        // action row. Neither means anything with one stop.
        #expect(ramp.contains("█●█"), "the stop strip")
        #expect(!solid.contains("█●█"), "no stop strip for a solid")
        // Matched on the button chrome: a bare ◀ also belongs to the colour
        // panel's slider arrows, which are in both.
        #expect(ramp.contains("▐ + ▌") && ramp.contains("▐ ◀ ▌"), "the action row")
        #expect(!solid.contains("▐ + ▌"), "no action row for a solid")

        // The colour editor is in both — it is what a solid colour IS.
        #expect(solid.contains("#FF0000") && ramp.contains("#FF0000"))
    }

    @Test("The panel renders preset chips (and no rule while recents are empty)")
    func presetsRender() {
        var ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        var presented = true
        let panel = GradientEditorPanel(
            gradient: Binding(get: { ramp }, set: { ramp = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let raw = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 50))
            .lines.joined(separator: "\n")
        // A cell colour unique to each of two presets proves their chips drew:
        // both endpoints of Heat and Ocean.
        #expect(raw.contains("38;2;120;0;0"), "Heat's first stop is drawn")
        #expect(raw.contains("38;2;0;40;120"), "Ocean's first stop is drawn")
    }
}
