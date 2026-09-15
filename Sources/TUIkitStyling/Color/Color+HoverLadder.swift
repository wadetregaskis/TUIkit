//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+HoverLadder.swift
//
//  How a colour the terminal decides answers the pointer: one rung up a ladder of
//  names, never a step in RGB.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Hover ladder

extension Color {

    /// This terminal-defined ink lifted one rung for a hover over `page`, or itself
    /// where no rung will do.
    ///
    /// The ladder is a standard slot, its bright twin, then the terminal's default
    /// foreground, SGR 39. A bright slot starts on the second rung. A 256-colour
    /// index below 16 is the same slot spelled by index, and climbs by index. The
    /// default foreground is the top: `Color.default` and the carried
    /// `.terminalForeground` are both 39 as ink, so neither has a rung. The terminal's
    /// page drawn as ink climbs straight to 39.
    ///
    /// Which rung:
    /// - Where the ink, the rung or the page has no RGB, the first rung the terminal
    ///   is told differently. It paints a slot and its twin as the user's profile
    ///   keeps them, so nothing can be checked, only asked for.
    /// - Where all three measure, the first rung that is visibly different (a
    ///   different 256-colour entry, the test the RGB lift uses) and no harder to
    ///   read against the page. 39 measures as the foreground the terminal reported.
    ///
    /// Never RGB. A slot is a name the user's profile keeps a colour under, and a
    /// lift in RGB would re-spell it as a triple the profile does not.
    ///
    /// The result carries this colour's alpha, as every re-spelling does.
    package func hoverLadderLift(over page: Color) -> Color {
        let pageRGB = page.rgbComponents
        let inkRGB = Self.inkRGB(of: self)
        for rung in hoverRungs {
            if let inkRGB, let pageRGB, let rungRGB = Self.inkRGB(of: rung) {
                let from = Color.rgb(inkRGB.red, inkRGB.green, inkRGB.blue)
                let to = Color.rgb(rungRGB.red, rungRGB.green, rungRGB.blue)
                let ground = Color.rgb(pageRGB.red, pageRGB.green, pageRGB.blue)
                guard to.downsampledToPalette256() != from.downsampledToPalette256(),
                    to.contrastRatio(against: ground) >= from.contrastRatio(against: ground)
                else { continue }
            } else {
                // Compared as the terminal is told: opaque, at 24-bit, where every
                // spelling keeps its own code.
                guard Self.inkCodes(of: rung) != Self.inkCodes(of: self) else { continue }
            }
            return rung.carryingAlpha(of: self)
        }
        return self
    }

    /// The rungs above this ink, nearest first. Ends in `Color.default`, which is
    /// no rung for an ink that is already 39.
    private var hoverRungs: [Color] {
        switch value {
        case .ansi(let slot) where !slot.isBright:
            return [Color(value: .ansi(slot.brightTwin)), .default]
        case .palette256(let index) where index < 8:
            // 0-7 are the standard slots by index; `| 8` is the twin's index.
            return [Color(value: .palette256(index | 8)), .default]
        case .ansi, .palette256, .terminalDefault, .terminalForeground, .terminalBackground, .rgb, .semantic:
            return [.default]
        }
    }

    /// What `colour` measures as when it is drawn as ink. `Color.default` measures
    /// as nothing on its own, because as a fill it is the background; as ink it is
    /// the terminal's foreground, which is measured once the terminal reports it.
    private static func inkRGB(of colour: Color) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard case .terminalDefault = colour.value else { return colour.rgbComponents }
        return TerminalColors.current.foreground.map { (red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// The SGR parameters `colour` is spelled with as a foreground at 24-bit.
    private static func inkCodes(of colour: Color) -> [String] {
        Color(value: colour.value).foregroundCodes(depth: .truecolor)
    }
}
