//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedRunFieldTests.swift
//
//  Every run a catalogue of controls leaves behind, replayed through the run
//  loop on several grounds — the page, a tab's surface, a colour of the app's
//  own, a ramp — and every replayed tick compared with a render at the same
//  instant (`ReplayOracle`): each cell's glyph and field, and the ink a glyph is
//  drawn in. The class `ReplayedTabChipBackgroundTests` is one case of, and the
//  class `ReplayedCaretBlinkTests` is another: whatever a frame leaves bare has
//  to land on the field its containers painted beneath it, and nothing else on
//  the row may move.
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
        // A menu row's bar over a label that animates on its own: the bar paints
        // under the label's run (`_MenuItemRowBar`, which records it). Still, so
        // the bar leaves no run of its own: a breathing bar's run spans the row
        // and replays the label as it was drawn, so a spinner under it holds the
        // glyph it rendered with until the next render — a limit of runs that
        // overlap, not of what is under them.
        Menu("Tasks") {
            Button(action: {}, label: { HStack(spacing: 0) { Text("Busy "); Spinner() } })
            Button("Idle") {}
        }
        .menuStyle(.inline)
        .selectionIndicatorStyle(.none)
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
        case page, tabSurface, colour, ramp
    }

    /// The walk every ground takes: more stops than the catalogue has focusables,
    /// so it wraps; eight ticks a stop reach both halves of a caret's blink and
    /// half a breath.
    private func walk<A: App>(_ make: () -> A) -> ReplayOracle.Findings {
        ReplayOracle.compare(make, stops: 23, ticks: 8, size: (80, 64), reportOncePerRow: true)
    }

    @Test("Every replayed tick of every run shows what a render at that instant draws", arguments: Ground.allCases)
    func everyTickMatchesARender(ground: Ground) {
        let found =
            switch ground {
            case .page: walk { OnThePageApp() }
            case .tabSurface: walk { InATabApp() }
            case .colour: walk { OnAColourApp() }
            case .ramp: walk { OnARampApp() }
            }
        // Enough that the walk reached the catalogue, not just its first stop.
        #expect(found.compared >= 200, "only \(found.compared) rows were replayed")
        for mismatch in found.mismatches { Issue.record("\(ground): \(mismatch)") }
    }
}
