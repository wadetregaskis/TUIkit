//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectedRowMarkAcrossFramesTests.swift
//
//  A selected row the cursor is not on draws a dimmed ● — the accent at
//  `ViewConstants.selectionIndicator` over the page — unless
//  `.unfocusedSelectionVisibility(.hidden)` says to draw nothing. Neither the
//  accent nor that visibility is the row's data, so a control that keeps a row's
//  composed line across frames has to key on them, or it serves the mark the row
//  had under the previous palette. A `Table` keeps such rows (`TableRowMemo.swift`)
//  and its frame key named the ink and not the mark: cycling from Silver Aerogel to
//  Solid Colors — both black text — kept showing Silver Aerogel's ●.
//
//  A `List` composes its chrome every frame and keeps only its rows' content, so
//  it is asked the same questions as the twin that keeps more.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// What the app draws that a test changes between frames. A class, so the app the
/// loop holds and the test share one.
private final class SelectedRowMarkKnobs {
    var visibility = Visibility.automatic
}

/// A List or a Table with row 1 selected, behind a button that holds the focus: the
/// control has no cursor row, and every row it draws is one it may keep.
private struct SelectedRowMarkApp: App {
    var kind = ReversedCursorRowTests.Kind.list
    var knobs = SelectedRowMarkKnobs()

    init() {}

    init(kind: ReversedCursorRowTests.Kind, knobs: SelectedRowMarkKnobs) {
        self.kind = kind
        self.knobs = knobs
    }

    var body: some Scene {
        WindowGroup {
            VStack {
                Button("elsewhere") {}
                kind.view(selection: [1])
            }
            .unfocusedSelectionVisibility(knobs.visibility)
        }
    }
}

@MainActor
@Suite("A selected row's mark follows the palette and the visibility across frames", .serialized)
struct SelectedRowMarkAcrossFramesTests {

    private static func palette(named name: String) throws -> any Palette {
        try #require(PaletteRegistry.palette(withName: name), "no palette named \(name)")
    }

    /// A loop over `kind` under `palette`, settled.
    private func settled(
        _ kind: ReversedCursorRowTests.Kind, palette: any Palette, knobs: SelectedRowMarkKnobs
    ) -> (harness: RenderLoopHarness, loop: RenderLoop<SelectedRowMarkApp>) {
        let harness = RenderLoopHarness()
        harness.paletteManager.setCurrent(palette)
        let loop = harness.loop(SelectedRowMarkApp(kind: kind, knobs: knobs))
        for _ in 0..<3 { _ = loop.render() }
        return (harness, loop)
    }

    private func lines(_ loop: RenderLoop<SelectedRowMarkApp>) throws -> [String] {
        loop.render()
        return try #require(loop.replayable, "the loop kept no frame").contentLines
    }

    /// What a loop that only ever drew `palette` and `visibility` draws: nothing it
    /// kept can be from anywhere else.
    private func cold(
        _ kind: ReversedCursorRowTests.Kind, palette: any Palette, visibility: Visibility
    ) throws -> [String] {
        let knobs = SelectedRowMarkKnobs()
        knobs.visibility = visibility
        return try lines(settled(kind, palette: palette, knobs: knobs).loop)
    }

    /// Silver Aerogel to Solid Colors, the neighbours in the palette cycle the
    /// report named: the same ink, so a key on the ink alone cannot tell them apart,
    /// and a different accent, so the ● they draw differs.
    @Test("A palette with the same ink and another accent redraws the selected row's mark",
        arguments: ReversedCursorRowTests.Kind.allCases)
    func markFollowsThePalette(kind: ReversedCursorRowTests.Kind) throws {
        let silver = try Self.palette(named: "Silver Aerogel")
        let solid = try Self.palette(named: "Solid Colors")
        #expect(
            silver.foreground.resolve(with: silver) == solid.foreground.resolve(with: solid),
            "the premise: the two palettes share their ink")
        #expect(
            silver.accent.resolve(with: silver) != solid.accent.resolve(with: solid),
            "the premise: the two palettes' marks differ")

        let knobs = SelectedRowMarkKnobs()
        let (harness, loop) = settled(kind, palette: silver, knobs: knobs)
        let before = try lines(loop)
        harness.paletteManager.setCurrent(solid)
        let after = try lines(loop)

        let expected = try cold(kind, palette: solid, visibility: .automatic)
        #expect(after != before, "the premise: the two palettes draw the control differently")
        #expect(
            after == expected,
            """
            the selected row after the palette changed is not what a fresh Solid Colors \
            draws: \(Self.markState(after)) against \(Self.markState(expected))
            """)
    }

    /// `.unfocusedSelectionVisibility(.hidden)` takes the ● away from a selected row the
    /// cursor is not on — and back — while the rows' data stands still.
    @Test("Hiding the unfocused selection takes the mark away, and showing it brings it back",
        arguments: ReversedCursorRowTests.Kind.allCases)
    func markFollowsTheVisibility(kind: ReversedCursorRowTests.Kind) throws {
        let palette = try Self.palette(named: "Solid Colors")
        let knobs = SelectedRowMarkKnobs()
        let (_, loop) = settled(kind, palette: palette, knobs: knobs)
        let shown = try lines(loop)
        #expect(shown.contains { $0.stripped.contains("●") }, "the premise: the selected row is marked")

        knobs.visibility = .hidden
        let hidden = try lines(loop)
        #expect(
            hidden == (try cold(kind, palette: palette, visibility: .hidden)),
            "the selected row kept its mark after the unfocused selection was hidden: \(Self.markState(hidden))")

        knobs.visibility = .automatic
        #expect(try lines(loop) == shown, "the mark did not come back")
    }

    /// The ● and the SGR state it is drawn in, for a failure message.
    private static func markState(_ lines: [String]) -> String {
        guard let state = sgrState(of: "●", in: lines) else { return "no mark" }
        return "● under \(state.rendered.debugDescription)"
    }
}
