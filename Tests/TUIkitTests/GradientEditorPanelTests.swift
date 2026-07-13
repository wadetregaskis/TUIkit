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
        // The stop strip: one numbered button per stop, the first selected.
        #expect(text.contains("●1"))
        #expect(text.contains(" 2"))
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

    @Test("Stop chips have selection-independent geometry, numbers left of their swatch")
    func stopChipGeometry() {
        var stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)]
        var presented = true
        let panel = GradientEditorPanel(
            stops: Binding(get: { stops }, set: { stops = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))
        let lines = renderToBuffer(panel, context: makeRenderContext(width: 70, height: 45))
            .lines.map(\.stripped)

        let strip = lines.first { $0.contains("●1") }
        #expect(strip != nil, "the stop strip renders")
        guard let strip else { return }

        // Each number sits immediately LEFT of its own swatch — the marker
        // slot is always reserved (a no-break space when unselected, which
        // survives label flattening), so selection never shifts a chip.
        #expect(strip.contains("●1██"), "selected chip: marker + number + swatch: |\(strip)|")
        #expect(strip.contains("\u{00A0}2██"), "unselected chip reserves the marker slot: |\(strip)|")
        #expect(strip.contains("\u{00A0}3██"))

        // Uniform pitch: the distance between consecutive chips equals the
        // chip width + 1 spacing, whichever chip is selected.
        func column(of needle: String) -> Int? {
            strip.range(of: needle).map { strip.distance(from: strip.startIndex, to: $0.lowerBound) }
        }
        let c1 = column(of: "1██"), c2 = column(of: "2██"), c3 = column(of: "3██")
        #expect(c1 != nil && c2 != nil && c3 != nil)
        if let c1, let c2, let c3 {
            #expect(c2 - c1 == GradientEditorPanel.stopChipWidth(index: 0) + 1, "|\(strip)|")
            #expect(c3 - c2 == GradientEditorPanel.stopChipWidth(index: 1) + 1, "|\(strip)|")
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
