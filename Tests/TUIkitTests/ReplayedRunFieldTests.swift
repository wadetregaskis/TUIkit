//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedRunFieldTests.swift
//
//  Every run a catalogue of controls leaves behind, replayed through the run
//  loop on several grounds — the page, a tab's surface, a colour of the app's
//  own, the same colour inverted, a ramp (painted, and under a `ZStack`), the
//  terminal's own page (`Color.default`), and a colour on it — painted as a
//  `.background`, composited under a `ZStack`, faded, dimmed and behind a sheet —
//  and every replayed tick compared
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

/// The same colour on the terminal's page, faded: every covered cell is blended
/// — the rows at the root, each run's frames where the rows are — and a cell that
/// blends to the page is spelled `ESC[49m`. A chip's label states it; the
/// `.background` lets it through at full strength and so must the fade. (Faded
/// below one half the colour and every ink blend to the page there, a colour with
/// no RGB, and nothing of the catalogue is left to replay.)
private struct FadedColourOnTheTerminalPageApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { catalogue().padding(1).background(Color.rgb(90, 20, 120)).opacity(0.6) }
            .palette(terminalPagePalette)
    }
}

/// Below one half, the fade INSIDE the colour: the `.background` is its backdrop
/// and spends it (`Opacity as composition.md` §96), each run's frames at the
/// painter, which then paints their records as it paints the rows.
private struct FadedInsideAColourOnTheTerminalPageApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { catalogue().opacity(0.4).padding(1).background(Color.rgb(90, 20, 120)) }
            .palette(terminalPagePalette)
    }
}

/// And inside a `ZStack` over the colour: the compositor spends it against the
/// colour, and then fills a stated 49 — in the rows and in the runs' records —
/// with the colour, as it does unfaded.
private struct FadedInsideAComposedColourOnTheTerminalPageApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) { Color.rgb(90, 20, 120); catalogue().opacity(0.4) }
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

/// The same ramp UNDER the catalogue in a `ZStack`: compositing paints every cell
/// the catalogue leaves bare over the ramp's entry at its own column, and every
/// run records the same, cell by cell — where it once read one entry, the one
/// under a row's first column, for the whole row.
private struct ComposedOnARampApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.rgb(200, 40, 40), Color.rgb(40, 40, 200)],
                    startPoint: .leading, endPoint: .trailing)
                catalogue()
            }
        }
    }
}

@MainActor
@Suite("A replayed run draws what a render draws, on every ground")
struct ReplayedRunFieldTests {

    enum Ground: String, CaseIterable, Sendable {
        case page, tabSurface, colour, invertedColour, ramp, composedOnRamp, terminalPage
        case colourOnTerminalPage, composedOnTerminalPage, fadedColourOnTerminalPage
        case fadedInsideColourOnTerminalPage, fadedInsideComposedOnTerminalPage, dimmed, backdrop
    }

    /// The walk every ground takes: more stops than the catalogue has focusables,
    /// so it wraps; eight ticks a stop reach both halves of a caret's blink and
    /// half a breath.
    private func walk<A: App>(_ make: () -> A) -> ReplayOracle.Findings {
        ReplayOracle.compare(make, stops: 23, ticks: 8, size: (80, 64), reportOncePerRow: true)
    }

    /// The walk on `ground`.
    private func findings(on ground: Ground) -> ReplayOracle.Findings {
        switch ground {
        case .page: walk { OnThePageApp() }
        case .tabSurface: walk { InATabApp() }
        case .colour: walk { OnAColourApp() }
        case .invertedColour: walk { InvertedColourApp() }
        case .ramp: walk { OnARampApp() }
        case .composedOnRamp: walk { ComposedOnARampApp() }
        case .terminalPage: walk { OnTheTerminalPageApp() }
        case .colourOnTerminalPage: walk { ColourOnTheTerminalPageApp() }
        case .composedOnTerminalPage: walk { ComposedOnTheTerminalPageApp() }
        case .fadedColourOnTerminalPage: walk { FadedColourOnTheTerminalPageApp() }
        case .fadedInsideColourOnTerminalPage: walk { FadedInsideAColourOnTheTerminalPageApp() }
        case .fadedInsideComposedOnTerminalPage: walk { FadedInsideAComposedColourOnTheTerminalPageApp() }
        case .dimmed: walk { DimmedApp() }
        case .backdrop: walk { BehindASheetApp() }
        }
    }

    // One test per ground, not one test with the grounds as arguments. Each walk
    // is several seconds of main-actor work, and a parameterised test's cases
    // all run in one process, so as a single test this suite was 48 s of the
    // parallel runner's wall on its own (Tools/ParallelTest/README.md): the
    // runner distributes tests, not a test's arguments. As a test per ground the
    // walks spread across its processes.

    @Test("Every replayed tick matches a render, on the page")
    func onThePage() { check(.page) }

    @Test("Every replayed tick matches a render, on a tab's surface")
    func onATabSurface() { check(.tabSurface) }

    @Test("Every replayed tick matches a render, on a colour of the app's own")
    func onAColour() { check(.colour) }

    @Test("Every replayed tick matches a render, on that colour inverted")
    func onAnInvertedColour() { check(.invertedColour) }

    @Test("Every replayed tick matches a render, on a ramp")
    func onARamp() { check(.ramp) }

    @Test("Every replayed tick matches a render, composited over a ramp")
    func composedOnARamp() { check(.composedOnRamp) }

    @Test("Every replayed tick matches a render, on the terminal's own page")
    func onTheTerminalPage() { check(.terminalPage) }

    @Test("Every replayed tick matches a render, on a colour on the terminal's page")
    func onAColourOnTheTerminalPage() { check(.colourOnTerminalPage) }

    @Test("Every replayed tick matches a render, composited over a colour on the terminal's page")
    func composedOnTheTerminalPage() { check(.composedOnTerminalPage) }

    @Test("Every replayed tick matches a render, faded around a colour on the terminal's page")
    func fadedAroundAColourOnTheTerminalPage() { check(.fadedColourOnTerminalPage) }

    @Test("Every replayed tick matches a render, faded inside a colour on the terminal's page")
    func fadedInsideAColourOnTheTerminalPage() { check(.fadedInsideColourOnTerminalPage) }

    @Test("Every replayed tick matches a render, faded inside a ZStack over a colour on the terminal's page")
    func fadedInsideAComposedColourOnTheTerminalPage() { check(.fadedInsideComposedOnTerminalPage) }

    @Test("Every replayed tick matches a render, dimmed")
    func dimmed() { check(.dimmed) }

    @Test("Every replayed tick matches a render, behind a sheet")
    func behindASheet() { check(.backdrop) }

    /// Every replayed tick of every run shows what a render at that instant draws.
    private func check(_ ground: Ground) {
        let found = findings(on: ground)
        // Enough that the walk reached the catalogue, not just its first stop.
        #expect(found.compared >= 200, "only \(found.compared) rows were replayed")
        for mismatch in found.mismatches { Issue.record("\(ground): \(mismatch)") }
    }

    /// Each ground's test. As one parameterised test, the grounds came from
    /// `Ground.allCases`, so a new case was walked as soon as it was written; as
    /// a test per ground, a case added without a test is never walked, and
    /// nothing fails to say so. This switch has no `default`, so such a case does
    /// not compile until it names its test here. It is never called: the
    /// exhaustiveness check is all it is for.
    private static func test(for ground: Ground) -> (Self) -> () -> Void {
        switch ground {
        case .page: Self.onThePage
        case .tabSurface: Self.onATabSurface
        case .colour: Self.onAColour
        case .invertedColour: Self.onAnInvertedColour
        case .ramp: Self.onARamp
        case .composedOnRamp: Self.composedOnARamp
        case .terminalPage: Self.onTheTerminalPage
        case .colourOnTerminalPage: Self.onAColourOnTheTerminalPage
        case .composedOnTerminalPage: Self.composedOnTheTerminalPage
        case .fadedColourOnTerminalPage: Self.fadedAroundAColourOnTheTerminalPage
        case .fadedInsideColourOnTerminalPage: Self.fadedInsideAColourOnTheTerminalPage
        case .fadedInsideComposedOnTerminalPage: Self.fadedInsideAComposedColourOnTheTerminalPage
        case .dimmed: Self.dimmed
        case .backdrop: Self.behindASheet
        }
    }
}
