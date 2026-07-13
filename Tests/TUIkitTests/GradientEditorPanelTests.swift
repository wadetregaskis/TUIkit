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
}
