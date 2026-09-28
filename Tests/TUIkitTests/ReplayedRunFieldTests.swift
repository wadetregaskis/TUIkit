//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedRunFieldTests.swift
//
//  Every run a catalogue of controls leaves behind, replayed through the run
//  loop on several grounds — the page, a tab's surface, a colour of the app's
//  own, the same colour inverted, a ramp, the terminal's own page
//  (`Color.default`), and a colour on it — painted as a `.background`, composited
//  under a `ZStack`, dimmed and behind a sheet — and every replayed tick compared
//  with a render at the same instant (`ReplayOracle`): each cell's glyph and
//  field, and the ink a glyph is drawn in. The class
//  `ReplayedTabChipBackgroundTests` is one case of, and the class
//  `ReplayedCaretBlinkTests` is another: whatever a frame leaves bare has to land
//  on the field its containers painted beneath it, and nothing else on the row
//  may move.
//
//  The replay used to put the PAGE's background back after each reset in a
//  frame, and a frame that names a background is one the splice leaves alone.
//  Three producers showed that in a container: a compact tab chip's right cap,
//  the blank cell beside a focused button's dot, and an indeterminate progress
//  bar's sweep. The field before the frame's first reset came from the row the
//  render drew, under the run's first cell — which a block caret drawn visible
//  had painted itself, so the caret never blinked off.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// One of everything that leaves a run: the focusable controls breathe when the
/// focus reaches them, and the spinner and the bar animate regardless.
@MainActor
private func catalogue() -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Button("Default") {}
        Button("Plain") {}.buttonStyle(.plain)
        Toggle("Toggle", isOn: .constant(true))
        Slider(value: .constant(0.5), in: 0...1).frame(width: 16)
        Stepper("Stepper", value: .constant(3))
        TextField("Prompt", text: .constant("hello")).frame(width: 12)
        // A block caret in a field with no background of its own: the frames
        // disagree about the field under its one cell.
        TextField("Plain", text: .constant("plain")).textFieldStyle(.plain)
            .textCursor(.block, animation: .blink).frame(width: 12)
        SecureField("Pin", text: .constant("abc")).frame(width: 12)
        Picker("Inline", selection: .constant(1)) {
            Text("One").tag(0)
            Text("Two").tag(1)
        }
        .pickerStyle(.inline)
        Picker("Radio", selection: .constant(1)) {
            Text("One").tag(0)
            Text("Two").tag(1)
        }
        .pickerStyle(.radioGroup)
        Menu("Menu") {
            Button("First") {}
            Button("Second") {}
        }
        .menuStyle(.inline)
        // A menu row's bar over a label that animates on its own. Where the bar
        // holds still (a reversal on a `Color.default` palette), it paints under
        // the label's run (`_MenuItemRowBar`, which records it); where it breathes,
        // its runs repaint the whole row, so it drops the label's run and asks for
        // a render at the spinner's next step (`MenuBreathingBarRunTests`).
        Menu("Tasks") {
            Button(action: {}, label: { HStack(spacing: 0) { Text("Busy "); Spinner() } })
            Button("Idle") {}
        }
        .menuStyle(.inline)
        TabView(selection: .constant(0)) {
            Tab("Alpha", value: 0) { Text("a") }
            Tab("Beta", value: 1) { Text("b") }
        }
        .tabViewStyle(.compact)
        TabView(selection: .constant(0)) {
            Tab("Gamma", value: 0) { Text("g") }
            Tab("Delta", value: 1) { Text("d") }
        }
        .tabViewStyle(.bordered)
        // A spinner in each row of a list, and a selected row the list fills:
        // the rows' own runs, carried up through the list's row painting.
        List(selection: .constant(Optional(1))) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) { Text("row \(row) "); Spinner() }
            }
        }
        .frame(width: 20, height: 3)
        Spinner("Spinning")
        ProgressView()
        // A link's frames carry the hyperlink's own escapes around the breath,
        // so the frame ends in a sequence after its last reset.
        Link("Link", destination: URL(string: "https://example.com")!)
        // A swatch's focus bullet is ink with no field, over the swatch's fill.
        ColorPicker("Colour", selection: .constant(.rgb(200, 40, 40)))
        // A swatch grid's cursor mark, drawn on the swatch under it.
        _SwatchGridCore(
            entries: [.rgb(200, 40, 40), .rgb(40, 200, 40), .rgb(40, 40, 200)], columns: 3,
            selection: .constant(.rgb(40, 200, 40)))
    }
}

private struct OnThePageApp: App {
    init() {}
    var body: some Scene { WindowGroup { catalogue() } }
}

private struct InATabApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TabView(selection: .constant(0)) {
                Tab("Outer", value: 0) { catalogue() }
                Tab("Other", value: 1) { Text("o") }
            }
            .tabViewStyle(.bordered)
        }
    }
}

private struct OnAColourApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { catalogue().padding(1).background(Color.rgb(90, 20, 120)) }
    }
}

/// The same colour under a colour effect, which recolours every field and ink
/// the catalogue drew — its runs' frames and grounds included.
private struct InvertedColourApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { catalogue().padding(1).background(Color.rgb(90, 20, 120)).colorInvert() }
    }
}

/// The terminal's own page: every field the palette names for the page — the
/// page itself, a tab's surface, a chip's label, the wash a dim or a backdrop
/// flattens everything to — is `Color.default`, spelled `ESC[49m`, and nothing
/// has an RGB to blend with.
@MainActor
let terminalPagePalette = ThemeProbePalette(background: .default, overlayBackground: .default)

private struct OnTheTerminalPageApp: App {
    init() {}
    var body: some Scene { WindowGroup { catalogue() }.palette(terminalPagePalette) }
}

/// A colour of the app's own on the terminal's page, as a `.background`: which
/// paints its field only where content states none, so a tab chip's label — on
/// the page's field, `ESC[49m` — shows the terminal's own through it.
private struct ColourOnTheTerminalPageApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { catalogue().padding(1).background(Color.rgb(90, 20, 120)) }
            .palette(terminalPagePalette)
    }
}

/// The same colour UNDER the catalogue in a `ZStack`: compositing reads a stated
/// `ESC[49m` as no field and fills it, so the chip's label is on the colour.
private struct ComposedOnTheTerminalPageApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) { Color.rgb(90, 20, 120); catalogue() }
        }
        .palette(terminalPagePalette)
    }
}

/// A colour of the app's own on the terminal's page, flattened by `.dimmed()`:
/// every line and every frame of every run washed to the terminal's own field.
private struct DimmedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { catalogue().padding(1).background(Color.rgb(90, 20, 120)).dimmed() }
            .palette(terminalPagePalette)
    }
}

/// The same colour behind a sheet: the backdrop's flatten, at the root.
private struct BehindASheetApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            catalogue().padding(1).background(Color.rgb(90, 20, 120))
                .sheet(isPresented: .constant(true)) { Text("Sheet") }
        }
        .palette(terminalPagePalette)
    }
}

/// A ramp: a different field under each column of a run, painted by the ramp's
/// own row painter.
private struct OnARampApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            catalogue().padding(1)
                .background(
                    LinearGradient(
                        colors: [Color.rgb(200, 40, 40), Color.rgb(40, 40, 200)],
                        startPoint: .leading, endPoint: .trailing))
        }
    }
}

@MainActor
@Suite("A replayed run draws what a render draws, on every ground")
struct ReplayedRunFieldTests {

    enum Ground: String, CaseIterable, Sendable {
        case page, tabSurface, colour, invertedColour, ramp, terminalPage
        case colourOnTerminalPage, composedOnTerminalPage, dimmed, backdrop
    }

    /// The walk every ground takes: more stops than the catalogue has focusables,
    /// so it wraps; eight ticks a stop reach both halves of a caret's blink and
    /// half a breath.
    private func walk<A: App>(_ make: () -> A) -> ReplayOracle.Findings {
        ReplayOracle.compare(make, stops: 23, ticks: 8, size: (80, 64), reportOncePerRow: true)
    }

    // One test per ground, not one test with the grounds as arguments. Each walk
    // is several seconds of main-actor work, and a parameterised test's cases
    // all run in one process, so as a single test this suite was 48 s of the
    // parallel runner's wall on its own (Tools/ParallelTest/README.md): the
    // runner distributes tests, not a test's arguments. As ten tests the walks
    // spread across its processes.

    @Test("Every replayed tick matches a render, on the page")
    func onThePage() { check(.page, walk { OnThePageApp() }) }

    @Test("Every replayed tick matches a render, on a tab's surface")
    func onATabSurface() { check(.tabSurface, walk { InATabApp() }) }

    @Test("Every replayed tick matches a render, on a colour of the app's own")
    func onAColour() { check(.colour, walk { OnAColourApp() }) }

    @Test("Every replayed tick matches a render, on that colour inverted")
    func onAnInvertedColour() { check(.invertedColour, walk { InvertedColourApp() }) }

    @Test("Every replayed tick matches a render, on a ramp")
    func onARamp() { check(.ramp, walk { OnARampApp() }) }

    @Test("Every replayed tick matches a render, on the terminal's own page")
    func onTheTerminalPage() { check(.terminalPage, walk { OnTheTerminalPageApp() }) }

    @Test("Every replayed tick matches a render, on a colour on the terminal's page")
    func onAColourOnTheTerminalPage() { check(.colourOnTerminalPage, walk { ColourOnTheTerminalPageApp() }) }

    @Test("Every replayed tick matches a render, composited over a colour on the terminal's page")
    func composedOnTheTerminalPage() { check(.composedOnTerminalPage, walk { ComposedOnTheTerminalPageApp() }) }

    @Test("Every replayed tick matches a render, dimmed")
    func dimmed() { check(.dimmed, walk { DimmedApp() }) }

    @Test("Every replayed tick matches a render, behind a sheet")
    func behindASheet() { check(.backdrop, walk { BehindASheetApp() }) }

    /// Every replayed tick of every run shows what a render at that instant draws.
    private func check(_ ground: Ground, _ found: ReplayOracle.Findings) {
        // Enough that the walk reached the catalogue, not just its first stop.
        #expect(found.compared >= 200, "only \(found.compared) rows were replayed")
        for mismatch in found.mismatches { Issue.record("\(ground): \(mismatch)") }
    }
}
