//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroundStyleRestatementTests.swift
//
//  `String.restatingGroundStyle(_:)`: a run's frame drawn in what its painters
//  restate beside the field — a row's reversal and the ink it exchanges — as a
//  render draws it. A painter restates its styling after every reset in the line,
//  so the render of a frame inside one is the frame with that styling put back
//  after each of its resets; that is the reference here, built by hand and read
//  by the independent model (`ReferenceSGRModel.swift`), never by `SGRState`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("A frame is drawn in the style its painters restate")
struct GroundStyleRestatementTests {

    private let esc = "\u{1B}"

    /// What a painter restating `restatement` after every reset makes of `frame`:
    /// the restatement in front, and again after each literal `ESC[0m` and each
    /// collapsed `ESC[0;…m` (a reset, the restatement, then the rest) — the rule
    /// `ANSIRenderer.restating(_:afterResetsIn:)` paints by, spelled out again here.
    private func painted(_ frame: String, restating restatement: String) -> String {
        let split = frame.replacing("\(esc)[0;", with: "\(esc)[0m\(esc)[")
        return restatement + split.replacing("\(esc)[0m", with: "\(esc)[0m" + restatement)
    }

    /// How each cell of `line` looks, from a reset, in the reference model's terms.
    private func appearance(_ line: String) -> [String] {
        var style = ReferenceStyle()
        var cells: [String] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, isSGR: true): style.apply(sequence)
            case .ansi: continue
            case .visible(let character): cells.append(style.appearance(of: character))
            }
        }
        return cells
    }

    /// `restatement` as the per-cell style the function takes, `cells` of it.
    private func style(_ restatement: String, cells: Int) -> [SGRState] {
        var state = SGRState()
        state.apply(restatement)
        return Array(repeating: state, count: cells)
    }

    /// The restatements a row can make beside its field: a reversal with its ink, a
    /// reversal of the terminal's own ink, and a dim.
    private var restatements: [String] {
        ["\(esc)[7;38;2;220;220;220m", "\(esc)[7m", "\(esc)[2m"]
    }

    @Test("A spinner's frames in a reversed row are drawn reversed")
    func spinnerFrames() {
        let restatement = "\(esc)[7;38;2;220;220;220m"
        for frame in ["\(esc)[38;2;230;120;40m⠋\(esc)[0m ", "⠙ ", "\(esc)[1m⠹\(esc)[0m\(esc)[0;31m "] {
            // The splice resets in front of the frame, as a render's row does not.
            let drawn = "\(esc)[0m" + frame.restatingGroundStyle(style(restatement, cells: 2))
            #expect(
                appearance(drawn) == appearance(painted(frame, restating: restatement)),
                "\(frame.debugDescription) came out \(drawn.debugDescription)")
        }
    }

    @Test("Randomised frames are drawn as a painter restating its style draws them")
    func randomisedFrames() {
        let sequences = [
            "\(esc)[0m", "\(esc)[0;31m", "\(esc)[0;0m", "\(esc)[m", "\(esc)[31m", "\(esc)[38;2;1;2;3m",
            "\(esc)[39m", "\(esc)[1m", "\(esc)[22m", "\(esc)[7m", "\(esc)[27m", "\(esc)[44m", "\(esc)[49m",
            "\(esc)[48;5;16m", "\(esc)[4m", "\(esc)[2K",
        ]
        let alphabet = Array("ab  ⠋")
        var seed: UInt64 = 0x0007_5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for restatement in restatements {
            for _ in 0..<400 {
                var frame = ""
                var cells = 0
                for _ in 0..<(1 + next(8)) {
                    if next(2) == 0 { frame += sequences[next(sequences.count)] }
                    frame.append(alphabet[next(alphabet.count)])
                    cells += 1
                }
                let drawn = "\(esc)[0m" + frame.restatingGroundStyle(style(restatement, cells: cells))
                #expect(
                    appearance(drawn) == appearance(painted(frame, restating: restatement)),
                    "\(restatement.debugDescription) under \(frame.debugDescription): \(drawn.debugDescription)")
            }
        }
    }

    @Test("A frame that states its painters' style already comes back as it was")
    func alreadyStated() {
        // The flatten behind a modal restyles every frame with the styling it paints
        // the lines and the ground with, so each frame restates it itself.
        let wash = "\(esc)[2;38;2;90;90;90;48;2;12;12;12m"
        let frame = "\(wash)⠋\(esc)[0m\(wash) "
        var restated = SGRState()
        restated.apply("\(esc)[2;38;2;90;90;90m")
        #expect(frame.restatingGroundStyle([restated, restated]) == frame)
    }

    @Test("Painters that restate nothing but a field leave the frame alone")
    func nothingToRestate() {
        let frame = "\(esc)[38;2;230;120;40m⠋\(esc)[0m "
        #expect(frame.restatingGroundStyle([SGRState(), SGRState()]) == frame)
        #expect(frame.restatingGroundStyle([]) == frame)
    }

    /// A style that differs between two cells of one run, which no painter makes
    /// today: each cell takes the style under its own column, the frame's own
    /// statements since its last reset over it. Switching the 7 OFF is spelled from a
    /// reset, and a field the frame stated as the terminal's own (`ESC[49m`) is
    /// stated again after it, so the field's restatement that follows
    /// (`paintedOver(fields:)`) still reads a stated 49 there, not none.
    @Test("A style that changes under a run is restated where it changes")
    func perColumn() {
        var reversed = SGRState()
        reversed.apply("\(esc)[7m")
        let frame = "\(esc)[49;31mab"
        let drawn = frame.restatingGroundStyle([reversed, SGRState()])
        var expectedA = ReferenceStyle()
        expectedA.apply("\(esc)[7;31;49m")
        var expectedB = ReferenceStyle()
        expectedB.apply("\(esc)[31;49m")
        #expect(appearance("\(esc)[0m" + drawn) == [expectedA.appearance(of: "a"), expectedB.appearance(of: "b")])
        // The last word about the background before `b` is a stated 49.
        var state = SGRState()
        var lastStatement: SGRState.BackgroundStatement?
        for segment in drawn.ansiSegments() {
            if case .ansi(let sequence, isSGR: true) = segment,
                let statement = state.applyReportingBackground(sequence)
            {
                lastStatement = statement
            }
            if case .visible("b") = segment { break }
        }
        #expect(lastStatement == .terminalDefault, "\(drawn.debugDescription)")
    }
}
