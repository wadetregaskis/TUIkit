//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+EstimatedRGB.swift
//
//  A colour's RGB as best known, for code that reads a colour as a value.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Estimated RGB

extension Color {

    /// This colour's RGB as best known, for code that reads a colour as a
    /// VALUE: a colour editor's channels and hex, the swatch nearest a colour, a
    /// gradient written to storage, an image palette's match candidates.
    ///
    /// - A terminal slot, `.ansi` or `.palette256` 0–15: the colour the terminal
    ///   reported for that slot, or xterm's value (`ANSIColor.xtermRGB`) while
    ///   it has reported none.
    /// - Every other colour: exactly `rgbComponents`. So the terminal's default
    ///   foreground and background are what it reported, or nil; `.terminalDefault`
    ///   and a semantic colour are nil.
    ///
    /// NOT for deciding how one colour looks beside another: a contrast pick, a
    /// floor, a blend. Those read `rgbComponents`. xterm's value is a guess at
    /// what the user's profile paints. An editor needs some number to show and
    /// change, but a rule that measures would be drawing on the guess.
    package var estimatedRGB: (red: UInt8, green: UInt8, blue: UInt8)? {
        switch value {
        case .ansi(let slot):
            return Self.estimatedRGB(of: slot)
        case .palette256(let index) where index < 16:
            // A slot's raw value is its index, so every index here is a slot.
            guard let slot = ANSIColor(rawValue: index) else { return rgbComponents }
            return Self.estimatedRGB(of: slot)
        case .rgb, .palette256, .terminalDefault, .terminalForeground, .terminalBackground, .semantic:
            return rgbComponents
        }
    }

    /// The colour the terminal reported for `slot`, else xterm's value for it.
    private static func estimatedRGB(of slot: ANSIColor) -> (red: UInt8, green: UInt8, blue: UInt8) {
        guard let reported = TerminalColors.current.slots?[Int(slot.rawValue)] else { return slot.xtermRGB }
        return (reported.red, reported.green, reported.blue)
    }
}
