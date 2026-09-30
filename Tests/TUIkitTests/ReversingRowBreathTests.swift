//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversingRowBreathTests.swift
//
//  A 16-colour row breath can end in reverse video: on those frames the whole row is
//  the palette's pair exchanged, with its content's own colours dropped, so every
//  glyph on it — text, secondary text, the ●, a badge — is the page's colour on the
//  text's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("Reversing row breath")
struct ReversingRowBreathTests {
    private static let escape = "\u{1B}["

    @Test(
        "Dropping colours keeps every other attribute, and a sequence left empty is gone",
        arguments: [
            ("\u{1B}[31mred\u{1B}[0m", "red\u{1B}[0m"),
            ("\u{1B}[1;38;5;196mbold\u{1B}[0m", "\u{1B}[1mbold\u{1B}[0m"),
            ("\u{1B}[38;2;1;2;3;48;2;4;5;6;4mu\u{1B}[0m", "\u{1B}[4mu\u{1B}[0m"),
            ("\u{1B}[38:2::1:2:3;2mdim", "\u{1B}[2mdim"),
            ("\u{1B}[7;39;49mx\u{1B}[27m", "x"),
            ("\u{1B}[0;93;104mhi", "\u{1B}[0mhi"),
            ("plain", "plain"),
            ("\u{1B}[2Kcleared", "\u{1B}[2Kcleared"),
        ])
    func droppingColours(_ input: String, _ expected: String) {
        #expect(ANSIRenderer.droppingColours(input) == expected)
    }

    @Test("A reversed frame states only the palette's pair")
    func reversedFrameStatesOnlyThePair() {
        let row = "\u{1B}[38;2;255;0;0m●\u{1B}[0m \u{1B}[38;2;90;90;90mdetail\u{1B}[0m   "
        let ink = Color.ansi(.white)
        let field = Color.ansi(.black)
        let painted = ANSIRenderer.applyReversedPair(row, ink: ink, field: field)
        let opening = ANSIRenderer.applyPersistentReverse("", ink: ink, field: field)
            .replacingOccurrences(of: ANSIRenderer.reset, with: "")
        // Every SGR in the frame is the pair's opening or a reset.
        var sequences: [String] = []
        var rest = Substring(painted)
        while let start = rest.range(of: Self.escape), let end = rest[start.upperBound...].firstIndex(of: "m") {
            sequences.append(String(rest[start.lowerBound...end]))
            rest = rest[rest.index(after: end)...]
        }
        #expect(!sequences.isEmpty)
        #expect(sequences.allSatisfy { $0 == opening || $0 == ANSIRenderer.reset }, "\(painted.debugDescription)")
        #expect(painted.strippedLength == row.strippedLength)
    }

    /// A pulse over the cursor's 16 frames, as the clock draws it.
    private static let cycle = SelectionEmphasisCycle(
        frames: (0..<16).map { frame in
            SelectionEmphasis(
                isFocused: true, animation: .pulse,
                phase: CursorTimer.pulsePhase(atFrame: frame, of: 16), blinkOn: true)
        },
        step: 0)

    @Test("A reversing breath shows its fill end on the bright frames and reverses on the dim ones")
    func framesAlternateBetweenFillAndReversal() throws {
        let fill = Color.ansi(.blue)
        let (ink, field) = (Color.ansi(.white), Color.ansi(.black))
        let reversal = RowBackground.Paint.reversed(ink: ink, field: field)
        let background = RowBackground.pulsingReversal(Self.cycle, dim: reversal, bright: .fill(fill))
        let paints = try #require(background.framePaints)
        #expect(paints.count == 16)
        let bright = paints.indices.filter { paints[$0].fill == fill }
        #expect(bright == [0, 1, 2, 3, 4, 12, 13, 14, 15])
        #expect(paints.indices.filter { paints[$0].fill == nil } == Array(5...11))
        #expect(background.pulseTiming != nil)

        // And the other way round: the dim end filled, the bright end reversed.
        let flipped = RowBackground.pulsingReversal(Self.cycle, dim: .fill(fill), bright: reversal)
        let flippedPaints = try #require(flipped.framePaints)
        #expect(flippedPaints.indices.filter { flippedPaints[$0].fill == nil } == bright)
    }

    @Test("A site that cannot draw a reversing breath holds its fill end still")
    func stillFillHoldsTheFillEnd() {
        let (ink, field) = (Color.ansi(.white), Color.ansi(.black))
        let breath = HighlightFill.reversingPulse(dim: nil, bright: .ansi(.blue), ink: ink, field: field)
        #expect(breath.stillFill == .fill(.ansi(.blue)))
        let other = HighlightFill.reversingPulse(dim: .ansi(.cyan), bright: nil, ink: ink, field: field)
        #expect(other.stillFill == .fill(.ansi(.cyan)))
    }

    /// A label faded below one half on a reversed frame of a list's cursor row is spent
    /// against the reversal, as the still reversal spends it.
    @Test("A faded label on a reversed frame of a list's cursor row is spent against the reversal")
    func fadedLabelOnAReversedFrame() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = try #require(PaletteRegistry.palette(withName: "Red Sands"))
            let context = makeRenderContext(width: 24, height: 6) { environment, _ in environment.palette = palette }
            let view = List(selection: .constant(Set([0]))) {
                ForEach(0..<2, id: \.self) { index in
                    HStack(spacing: 1) { Text("row \(index)"); Text("faded").opacity(0.4) }
                }
            }
            let drawn = ColorDepth.withCurrent(.basic16) {
                _ = renderToBuffer(view, context: context)
                return renderToBuffer(view, context: context)
            }
            let run = try #require(drawn.animatedCells.first, "the cursor row does not breathe")
            let reversedFrame = run.frames[8]
            let states = ColorDepth.withCurrent(.basic16) { () -> [(Character, SGRState)] in
                var state = SGRState()
                var result: [(Character, SGRState)] = []
                for segment in reversedFrame.ansiSegments() {
                    switch segment {
                    case .ansi(let sequence, true): state.apply(sequence)
                    case .ansi: continue
                    case .visible(let character): result.append((character, state))
                    }
                }
                return result
            }
            let text = String(states.map(\.0))
            let start = try #require(text.range(of: "faded")).lowerBound
            let fadedIndex = text.distance(from: text.startIndex, to: start)
            let label = Set(states[1..<6].map(\.1.parameters))
            let faded = Set(states[fadedIndex..<fadedIndex + 5].map(\.1.parameters))
            #expect(faded.isDisjoint(with: label), "\(reversedFrame.debugDescription)")
        }
    }
}
