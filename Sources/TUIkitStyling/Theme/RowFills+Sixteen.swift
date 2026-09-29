//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowFills+Sixteen.swift
//
//  A row's fills on a 16-colour terminal: slots of the table the terminal reports,
//  with reverse video where sixteen colours are too few.
//
//  Created by Wade Tregaskis
//  License: MIT

extension RowFills {
    /// Five 16-colour picks, (S, F dim, F top, B dim, B top): slots, -1 for reverse
    /// video.
    typealias Picks = (Int, Int, Int, Int, Int)

    /// xterm's sixteen slots, 0xRRGGBB: what a terminal paints until it reports its
    /// own, and one of the two tables the shipped palettes carry picks for.
    static let xtermTable: [UInt32] = ANSIColor.allCases.map { slot in
        let (red, green, blue) = slot.xtermRGB
        return UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    /// Apple Terminal's sixteen, as its OSC 4 replies reported them (455.1, "Basic",
    /// 2026-09-14; `Documentation/Terminal-compatibility.md`): the other table the
    /// shipped palettes carry picks for.
    static let appleTable: [UInt32] = [
        0x000000, 0x990000, 0x00A600, 0x999900, 0x0000B3, 0xB300B3, 0x00A6B3, 0xBFBFBF,
        0x666666, 0xE60000, 0x00D900, 0xE6E600, 0x0000FF, 0xE600E6, 0x00E6E6, 0xE6E6E6,
    ]

    /// The sixteen slots the terminal paints: the ones it reported, else xterm's —
    /// the table ``Color/downsampledToANSI16()`` matches against.
    static func reportedTable() -> [UInt32] {
        guard let slots = TerminalColors.current.slots else { return xtermTable }
        return (0..<TerminalColors.Slots.count).map { index in
            let slot = slots[index]
            return UInt32(slot.red) << 16 | UInt32(slot.green) << 8 | UInt32(slot.blue)
        }
    }

    /// Slot picks as fills: `.ansi` slots, with a reversed end noted and filled with
    /// its breath's other end.
    static func fills(_ picks: Picks) -> RowFills {
        func slot(_ index: Int) -> Color? {
            index >= 0 ? ANSIColor(rawValue: UInt8(index)).map(Color.ansi) : nil
        }
        let (selection, focusDim, focusTop, emphasisDim, emphasisTop) = picks
        func breath(_ dim: Int, _ top: Int) -> (dim: Color, top: Color, reversed: BreathEnd?) {
            let (dimFill, topFill) = (slot(dim), slot(top))
            let reversed: BreathEnd? = dimFill == nil ? .dim : topFill == nil ? .top : nil
            // A breath has at most one reversed end: both reversed would not breathe.
            let either = dimFill ?? topFill ?? .ansi(.white)
            return (dimFill ?? either, topFill ?? either, reversed)
        }
        let focus = breath(focusDim, focusTop)
        let emphasis = breath(emphasisDim, emphasisTop)
        return RowFills(
            selection: slot(selection) ?? .ansi(.white), focusDim: focus.dim, focusBright: focus.top,
            emphasisDim: emphasis.dim, emphasisBright: emphasis.top, reversedFocusEnd: focus.reversed,
            reversedEmphasisEnd: emphasis.reversed)
    }

    /// The rule's 16-colour fills for `key`, placed toward `look` — or toward a shipped
    /// palette's own truecolour fills, or a stated wash, where the key carries one.
    static func sixteen(_ key: RuleKey, rule: RowFillRule, look: RowFillRule.Look) -> RowFills {
        func swatch(_ packed: UInt32) -> RowFillRule.Swatch {
            rule.swatch(UInt8(packed >> 16 & 0xFF), UInt8(packed >> 8 & 0xFF), UInt8(packed & 0xFF))
        }
        var target = look
        if let shipped = key.shippedTarget, shipped.count == 5 {
            target.selection = swatch(shipped[0])
            target.focus = (swatch(shipped[1]), swatch(shipped[2]))
            target.emphasis = (swatch(shipped[3]), swatch(shipped[4]))
        }
        let wash = key.statedWash
        if let wash, let (dimRed, dimGreen, dimBlue) = wash[0].rgbComponents,
            let (topRed, topGreen, topBlue) = wash[1].rgbComponents
        {
            // A stated wash is what F's slots are chosen nearest.
            target.focus = (rule.swatch(dimRed, dimGreen, dimBlue), rule.swatch(topRed, topGreen, topBlue))
        }
        let slots = rule.sixteen(toward: target, table: (key.table ?? xtermTable).map(swatch))
        var fills = Self.fills(
            (
                slots.selection, slots.focusDim ?? -1, slots.focusTop ?? -1, slots.emphasisDim ?? -1,
                slots.emphasisTop ?? -1
            ))
        if let wash, wash[0].rgbComponents == nil || wash[1].rgbComponents == nil {
            // A wash with no RGB is drawn as it is stated: there is nothing to check.
            fills = RowFills(
                selection: fills.selection, focusDim: wash[0], focusBright: wash[1], emphasisDim: fills.emphasisDim,
                emphasisBright: fills.emphasisBright, reversedEmphasisEnd: fills.reversedEmphasisEnd)
        }
        return fills
    }
}

extension RowFills.Entry {
    /// This shipped palette's 16-colour fills on `table`, where it carries picks for
    /// that table (xterm's or Apple Terminal's), else `nil`: the rule places them.
    func fills(on table: [UInt32]) -> RowFills? {
        if table == RowFills.xtermTable { return RowFills.fills(sixteen.xterm) }
        if table == RowFills.appleTable { return RowFills.fills(sixteen.apple) }
        return nil
    }
}
