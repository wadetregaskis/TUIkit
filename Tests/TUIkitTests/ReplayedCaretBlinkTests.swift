//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedCaretBlinkTests.swift
//
//  A block caret that blinks, in a `.plain` field — a field with no background of
//  its own — replayed tick by tick against a render at each tick's instant.
//
//  The caret is the sharpest case of a run whose frames disagree about the FIELD
//  under one cell: the on frame paints the cell in the caret's colour, the off
//  frame leaves it bare, over whatever the field sits on. So the one thing that
//  cannot say what is under that cell is the row the render drew with the caret
//  on — it shows the caret's colour there — and anything that took the field
//  from that row gave the off frame the caret's colour: a caret that never
//  blinks off. `AnimatedRunGroundTests` pins where the field comes from instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A button, then a `.plain` field with a blinking block caret, on `ground`. The
/// button takes the focus first, so one step puts it on the field — and the
/// frame after that step draws the caret visible, at the top of its blink.
private struct CaretApp: App {
    let ground: ReplayedCaretBlinkTests.Ground
    init() { ground = .inAFade }
    init(on ground: ReplayedCaretBlinkTests.Ground) { self.ground = ground }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button("Before") {}
                switch ground {
                case .onThePage:
                    field
                case .onAColour:
                    field.padding(1).background(Color.rgb(90, 20, 120))
                case .inAFade:
                    field.opacity(0.5)
                }
            }
        }
    }

    @MainActor private var field: some View {
        TextField("Prompt", text: .constant("plain"))
            .textFieldStyle(.plain)
            .textCursor(.block, animation: .blink)
            .frame(width: 12)
    }
}

@MainActor
@Suite("A replayed block caret blinks off")
struct ReplayedCaretBlinkTests {

    enum Ground: String, CaseIterable, Sendable {
        /// On the page: the replay puts the page under the hidden frame's cell.
        case onThePage
        /// On a colour a `.background` paints: the replay puts that colour there.
        case onAColour
        /// Under `.opacity(0.5)`: the fade blends every frame of the caret once, at
        /// render time, each frame's bare cell over the field beneath it.
        case inAFade
    }

    @Test("Every tick shows what a render at that instant draws", arguments: Ground.allCases)
    func everyTickMatchesARender(ground: Ground) throws {
        let found = ReplayOracle.compare({ CaretApp(on: ground) }, focusSteps: 1, ticks: 30, size: (40, 6))
        // Both halves of the blink: a caret that left no run to replay is frozen,
        // not blinking, whatever it froze on.
        try #require(
            found.compared >= 20, "\(ground): only \(found.compared) rows were replayed — the caret does not animate")
        for mismatch in found.mismatches { Issue.record("\(ground): \(mismatch)") }
    }
}
