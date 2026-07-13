//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GradientEditorPanelTests.swift
//
//  The gradient editor's pure stop-list mutations (duplicate / remove / move,
//  with the ≥2-stop floor and selection follow), plus render smokes proving
//  the dialog embeds the colour-panel body (no nested dialog) and previews
//  with the shared gradient interpolation.
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

    @Test("Duplicating inserts a copy after the stop and selects it")
    func duplicate() {
        let (updated, selected) = Panel.duplicatingStop([teal, blue], at: 0)
        #expect(updated == [teal, teal, blue])
        #expect(selected == 1)
        // Editing the copy then diverges it — the original is untouched.
        let (atEnd, endSelected) = Panel.duplicatingStop([teal, blue], at: 1)
        #expect(atEnd == [teal, blue, blue])
        #expect(endSelected == 2)
    }

    @Test("Removing keeps at least two stops")
    func removeFloor() {
        let (unchanged, _) = Panel.removingStop([teal, blue], at: 0)
        #expect(unchanged == [teal, blue], "two stops is the floor — not a gradient below that")

        let (updated, selected) = Panel.removingStop([teal, blue, violet], at: 2)
        #expect(updated == [teal, blue])
        #expect(selected == 1, "removing the last stop pulls the selection back in range")
    }

    @Test("Moving swaps with the neighbour and follows the stop")
    func move() {
        let (right, rightSelected) = Panel.movingStop([teal, blue, violet], at: 0, by: 1)
        #expect(right == [blue, teal, violet])
        #expect(rightSelected == 1)

        let (left, leftSelected) = Panel.movingStop([teal, blue, violet], at: 2, by: -1)
        #expect(left == [teal, violet, blue])
        #expect(leftSelected == 1)

        // Edges are no-ops (the buttons are disabled there anyway).
        let (unmoved, unmovedSelected) = Panel.movingStop([teal, blue], at: 0, by: -1)
        #expect(unmoved == [teal, blue])
        #expect(unmovedSelected == 0)
    }

    @Test("Drag-moving relocates the stop (insert, not swap) and follows it")
    func moveFromTo() {
        let white = Color.rgb(255, 255, 255)

        // Forward: the stops between source and destination shift left.
        let (forward, forwardSelected) = Panel.movingStop(
            [teal, blue, violet, white], from: 0, to: 2)
        #expect(forward == [blue, violet, teal, white], "insert semantics, not a swap")
        #expect(forwardSelected == 2)

        // Backward: they shift right.
        let (backward, backwardSelected) = Panel.movingStop(
            [teal, blue, violet, white], from: 3, to: 1)
        #expect(backward == [teal, white, blue, violet])
        #expect(backwardSelected == 1)

        // Same place and out-of-range are no-ops.
        let (samePlace, _) = Panel.movingStop([teal, blue], from: 1, to: 1)
        #expect(samePlace == [teal, blue])
        let (outOfRange, outSelected) = Panel.movingStop([teal, blue], from: 5, to: 0)
        #expect(outOfRange == [teal, blue])
        #expect(outSelected == 1, "selection clamps into range")
    }
}

@MainActor
@Suite("GradientEditorPanel — rendering")
struct GradientEditorPanelRenderTests {

    @Test("The dialog embeds the colour-panel body (stops, actions, tabs, one Done)")
    func rendersEmbeddedEditor() {
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
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
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let buffer = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
        let text = buffer.lines.joined(separator: "\n")

        // Both endpoints appear as foreground colours in the preview strip,
        // and so does an interior cell computed exactly as the strip does:
        // 36 cells sampled at parameter i/35 (cell 18 here).
        let interior = TrackRenderer.gradientColor(
            stops: stops, parameter: 18.0 / 35.0, fallback: .rgb(0, 0, 0))
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
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))

        // ONE context (one render cache) across both renders, like the live
        // render loop between frames.
        let context = makeRenderContext(width: 70, height: 45)
        _ = renderToBuffer(panel, context: context)
        stops[0] = .rgb(0, 255, 0)  // the edit the colour panel would make
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
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
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
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
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
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
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
            stops == [.rgb(0, 255, 0), .rgb(255, 0, 0), .rgb(0, 0, 255)],
            "reaching slot 2 moves the stop immediately, mid-drag")
        (y, columns) = renderFrame()
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: columns[2] + 1, y: y))
        #expect(
            stops == [.rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 0, 0)],
            "following the cursor to slot 3, still mid-drag")
        (y, columns) = renderFrame()
        // Dragging far PAST the strip's right edge holds the end slot, and
        // a wild Y is clamped to the (single) row — tolerance by design.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: columns[2] + 30, y: y + 7))
        #expect(stops == [.rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 0, 0)], "end slot held")
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: columns[2] + 1, y: y))
        #expect(
            stops == [.rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 0, 0)],
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
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
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

    private let a: [Color] = [.rgb(1, 1, 1), .rgb(2, 2, 2)]
    private let b: [Color] = [.rgb(3, 3, 3), .rgb(4, 4, 4)]

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
        var recents: [[Color]] = []
        let gradients = (0..<12).map { n -> [Color] in
            [.rgb(UInt8(n), 0, 0), .rgb(0, UInt8(n), 0)]
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
        #expect(Panel.recordingRecent([.rgb(1, 1, 1)], in: []).isEmpty,
                "one stop is not a gradient")
    }

    @Test("Recents survive an encode/decode round trip; junk entries drop")
    func codecRoundTrip() {
        let recents = [a, b]
        let decoded = Panel.decodeRecents(Panel.encodeRecents(recents))
        #expect(decoded == recents)

        // Junk: an empty entry, a single-stop entry, and a malformed hex.
        let junk = Panel.decodeRecents(";010101;ZZZZZZ,010101;010101,020202")
        #expect(junk == [[Color.rgb(1, 1, 1), Color.rgb(2, 2, 2)]])
    }

    @Test("The panel renders preset chips (and no rule while recents are empty)")
    func presetsRender() {
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let raw = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 50))
            .lines.joined(separator: "\n")
        // A cell colour unique to each of two presets proves their chips drew:
        // both endpoints of Heat and Ocean.
        #expect(raw.contains("38;2;120;0;0"), "Heat's first stop is drawn")
        #expect(raw.contains("38;2;0;40;120"), "Ocean's first stop is drawn")
    }
}
