//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+GroundStyle.swift
//
//  A run's frame drawn in the rest of what its painters restate beneath it,
//  beside the field: a row's reversal, and the ink the reversal exchanges.
//
//  A painter restates its styling after every reset in the lines it paints, so
//  whatever a run's frame leaves unsaid after one of its own resets is the
//  painter's. For most painters that is a field (a `.background`, a compositor,
//  a ramp, the page), which `String.paintedOver(fields:)` puts back. A row that
//  REVERSES — a menu's focused row and a list's cursor row, where the highlight
//  has no RGB to breathe between (`Opacity as composition.md` §86, §88) —
//  restates `ESC[7;<ink>;<field>m`, so a spinner drawn in it is reversed with
//  it: its glyph in the row's field, on a block of its own colour. Drawn over the
//  field alone, the same frame came out unreversed: its glyph in its own colour
//  on the terminal's own field, a one-cell hole in the bar.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drawing a frame in its ground's style

extension String {
    /// This frame with, in front of every cell, the rest of the state its painters
    /// restate there beside the field — `style[k]` under the frame's column `k`,
    /// as ``AnimatedCellRun/groundStyle`` reads it — under the frame's own
    /// statements since its last reset.
    ///
    /// What a render draws: a painter restates its styling after every reset in
    /// the line, the frame's included, and the frame's own escapes after that reset
    /// then override what they name. So the style under a cell is the painters'
    /// restatement where the frame last reset (or began), with every sequence of the
    /// frame since applied over it, and that is what is put in force in front of each
    /// cell that does not already have it: a 7 the frame never states, and the ink
    /// the reversal exchanges wherever the frame names none of its own — a glyph with
    /// no colour, a blank. The field is not this function's: its restatement is
    /// `paintedOver(fields:)`'s, which the frame goes through afterwards, and which
    /// reads what this one emits as the frame's own, naming no field.
    ///
    /// What a reset is follows the painters' own rule
    /// (`SGRState.restating(_:after:in:)`). Nothing is emitted where the output
    /// already has the state, so a frame that states its style itself — one the
    /// flatten behind a modal restyled with the same styling as the lines — comes
    /// back as it was.
    ///
    /// - Parameter style: The state its painters restate under each of the frame's
    ///   columns, a wide character's second included, with no field in it. A
    ///   column past the end restates what the last one did.
    /// - Returns: The frame, each cell in its painters' style under its own.
    package func restatingGroundStyle(_ style: [SGRState]) -> String {
        guard let first = style.first, style.contains(where: { !$0.isDefault }) else { return self }
        /// The painters' style under `column`.
        func base(_ column: Int) -> SGRState { style[Swift.min(column, style.count - 1)] }

        var result = ""
        result.reserveCapacity(utf8.count + 16)
        // What the output has in force: the splice resets in front of the frame.
        var output = SGRState()
        // Whether the output's field is a stated `ESC[49m` rather than none. A
        // restatement that has to switch an attribute off is spelled from a reset,
        // and the field after it has to say the same thing it said before.
        var statesTerminalField = false
        // What a render has in force: the painters' style at the frame's start and
        // after each of its resets, the frame's own sequences since applied over it.
        var rendered = first
        // The style `rendered` was restated from, and the frame's sequences since,
        // to restate them over the style under a cell whose painters restated
        // something else — which none of them does across one run today.
        var restatedFrom = first
        var sinceReset: [String] = []
        var column = 0

        for segment in ansiSegments() {
            switch segment {
            case .ansi(let sequence, isSGR: true):
                result += sequence
                if let statement = output.applyReportingBackground(sequence) {
                    statesTerminalField = statement == .terminalDefault
                }
                if sequence == "\u{1B}[0m" || sequence.hasPrefix("\u{1B}[0;") {
                    // A reset, after which the painters restate their style under
                    // the next cell; the collapsed spelling's rest follows that.
                    restatedFrom = base(column)
                    rendered = SGRState.restating(restatedFrom, after: sequence, in: rendered)
                    let rest = sequence.dropFirst(4)
                    sinceReset = sequence == "\u{1B}[0m" || rest == "0m" ? [] : ["\u{1B}[" + rest]
                } else {
                    rendered.apply(sequence)
                    sinceReset.append(sequence)
                }
            case .ansi(let sequence, isSGR: false):
                result += sequence
            case .visible(let character):
                if base(column) != restatedFrom {
                    restatedFrom = base(column)
                    rendered = restatedFrom
                    for sequence in sinceReset { rendered.apply(sequence) }
                }
                // Everything but the field, which is not this function's.
                var wanted = rendered
                wanted.setBackground(output.backgroundColour)
                if wanted != output {
                    let restatement = wanted.rendered(changingFrom: output)
                    result += restatement
                    if statesTerminalField, restatement.hasPrefix("\u{1B}[0") { result += "\u{1B}[49m" }
                    output = wanted
                }
                result.append(character)
                column += character.terminalWidth
            }
        }
        return result
    }
}
