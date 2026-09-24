//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedWholeRowFadeTests.swift
//
//  A repeating `.opacity` fade replays as ONE run over its whole row (the
//  resolution builds it that way — see `OpacityResolution.cyclingRuns`), so the
//  run's cells sit on whatever the row has beneath each of them: a coloured label
//  for some, the page for the rest. Every tick is replayed against a render at
//  the same instant, on a page the palette paints and on the terminal's own
//  (`Color.default`, no RGB while the terminal has not reported one).
//
//  Two rows. `REC` opens on a label with a background of its own and fades the
//  text after it: the shape a single field for the whole run got wrong — the
//  field under the run's FIRST cell, the label's red, was restated after every
//  reset in the frame, and on the terminal's own page nothing painted over it, so
//  the rest of the row smeared red on every tick. `LIVE` fades a label that has a
//  background of its own: the shape a field read off the row the render drew
//  would get wrong, if any tick left those cells bare that another painted.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A palette whose page is the terminal's own.
private struct TerminalPagePalette: Palette {
    let id = "replayed-whole-row-fade-terminal-page"
    let name = "Terminal page"
    let background = Color.default
    let foreground = Color.rgb(220, 220, 220)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// The row, starting its repeating fade as it appears.
private struct FadingRow: View {
    let shape: ReplayedWholeRowFadeTests.Shape
    @State private var dim = false

    var body: some View {
        HStack(spacing: 0) {
            switch shape {
            case .recording:
                Text(" REC ").background(Color.rgb(200, 40, 40))
                Text(" recording").opacity(dim ? 0.2 : 1)
            case .live:
                Text("Status ")
                Text(" LIVE ").background(Color.rgb(200, 40, 40)).opacity(dim ? 0.2 : 1)
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 0.4).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

private struct FadingRowApp: App {
    let shape: ReplayedWholeRowFadeTests.Shape
    let page: ReplayedWholeRowFadeTests.Page
    init() { (shape, page) = (.recording, .painted) }
    init(_ shape: ReplayedWholeRowFadeTests.Shape, on page: ReplayedWholeRowFadeTests.Page) {
        (self.shape, self.page) = (shape, page)
    }

    var body: some Scene {
        WindowGroup {
            FadingRow(shape: shape)
                .palette(page == .painted ? SystemPalette(.green) as any Palette : TerminalPagePalette())
        }
    }
}

@MainActor
@Suite("A replayed whole-row fade draws what a render draws")
struct ReplayedWholeRowFadeTests {

    enum Shape: String, CaseIterable, Sendable {
        /// A label with a field of its own, then fading text.
        case recording
        /// A label with a field of its own, fading.
        case live
    }

    enum Page: String, CaseIterable, Sendable {
        /// A page the palette paints.
        case painted
        /// The terminal's own page, which has no RGB to blend with.
        case terminalDefault
    }

    @Test("Every tick shows what a render at that instant draws", arguments: Shape.allCases, Page.allCases)
    func everyTickMatchesARender(shape: Shape, page: Page) throws {
        let found = TerminalColors.withCurrent(.unknown) {
            ReplayOracle.compare({ FadingRowApp(shape, on: page) }, ticks: 24, size: (30, 4))
        }
        // The whole cycle: 0.4 s each way is 24 steps of 50 ms.
        try #require(found.compared >= 24, "\(shape) on \(page): only \(found.compared) rows were replayed")
        for mismatch in found.mismatches { Issue.record("\(shape) on \(page): \(mismatch)") }
    }
}
