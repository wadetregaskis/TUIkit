//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReferenceSGRModel.swift
//
//  A second, independent SGR model, written for the tests that grade the first
//  one. `SGRState` nets escapes and `collapsingAdjacentSGR` rewrites them, and
//  a test that checked either against `SGRState` would be asking the code
//  whether it agrees with itself.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The styling a terminal is in, parsed by hand from the parameters.
struct ReferenceStyle: Equatable {
    var attributes: Set<Int> = []
    var foreground: [Int]?
    var background: [Int]?

    /// Codes this model does not understand. Kept, and kept VISIBLE on every
    /// cell including a blank one: unknown means it might be `ESC[53m`
    /// (overline), which draws on an empty cell as surely as an underline does.
    var passthrough: [Int] = []

    /// The field a row builder puts back after every reset, for a row that has
    /// not reached the terminal yet (`FrameDiffWriter` puts the page back) —
    /// `nil` for bytes that go to the terminal as they are, where a reset leaves
    /// the terminal's own field, as `ESC[49m` does.
    var fieldAfterReset: [Int]?

    /// The attributes that put ink on a cell holding nothing but a space, and
    /// so are the only ones a blank cell can show — together with the
    /// background, and with the foreground they colour.
    ///
    /// This is the SPECIFICATION the row builder and the cell diff are held to.
    /// It is spelled out here, in the test's own terms, so an implementation
    /// that dropped anything else — a background, an underline — fails rather
    /// than passes.
    static let inking: Set<Int> = [4, 5, 6, 7, 9]

    /// Which codes switch which attributes off. Spelled out as data rather than
    /// as `case` after `case` so the netting below stays readable.
    private static let attributeOff: [Int: Set<Int>] = [
        21: [1], 22: [1, 2], 23: [3], 24: [4], 25: [5, 6], 27: [7], 28: [8], 29: [9],
    ]

    mutating func apply(_ sequence: String) {
        guard sequence.hasSuffix("m") else { return }
        let body = sequence.dropFirst(2).dropLast()
        let codes =
            body.isEmpty
            ? [0]
            : body.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                let restored = fieldAfterReset
                self = Self()
                fieldAfterReset = restored
                background = restored
            case 1...9: attributes.insert(code)
            case 21...29 where Self.attributeOff[code] != nil:
                attributes.subtract(Self.attributeOff[code] ?? [])
            case 30...37, 90...97: foreground = [code]
            case 39: foreground = nil
            case 40...47, 100...107: background = [code]
            case 49: background = nil
            case 38, 48:
                let span = index + 1 < codes.count && codes[index + 1] == 5 ? 3 : 5
                let parameters = Array(codes[index..<min(codes.count, index + span)])
                if code == 38 { foreground = parameters } else { background = parameters }
                index += span
                continue
            default:
                passthrough.append(code)
            }
            index += 1
        }
    }

    /// What a viewer sees in a cell holding `character` under this styling.
    ///
    /// Comparable, and deliberately lossy for a space: a space has no glyph, so
    /// bold, italic, conceal and the foreground colour have nothing to act on.
    func appearance(of character: Character) -> String {
        guard character == " " else {
            return
                "\(character)|\(attributes.sorted())|\(foreground ?? [])|\(background ?? [])|\(passthrough)"
        }
        let ink = attributes.intersection(Self.inking)
        return
            " |\(ink.sorted())|\(ink.isEmpty ? [] : foreground ?? [])|\(background ?? [])|\(passthrough)"
    }
}
