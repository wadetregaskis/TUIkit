//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+FieldLeftToPainter.swift
//
//  Which cells of a line — content a painter is about to fill under — leave
//  their field to the painter. A painter with a TRANSLUCENT field claims its
//  alpha for the field alone, and the field is its own only where the content
//  states none: elsewhere the content's own field is in the line in its place,
//  with the painter's beneath it (`OpacityRegion.fieldUnderContent`,
//  `Opacity as composition.md` §105).
//
//  Created by Wade Tregaskis
//  License: MIT

extension String {
    /// For each of the first `width` columns of this line, whether it leaves the
    /// cell's field to a painter that fills under it: nothing about the background
    /// said since the line's last reset — no colour, no `ESC[49m` — and not
    /// reversed, since a reversed cell shows its foreground slot as its field and
    /// the painter's colour, in the background slot, as its ink. A column past the
    /// end of the line is one the painter pads, and leaves it too; a wide glyph's
    /// second column answers as its first.
    ///
    /// Reads each sequence once, as the painters' own persistent fill restates its
    /// colour after every reset: the field it lets through is a stated 49 (the
    /// terminal's own) and every colour, and it paints the field of every cell a
    /// reset put back on none.
    ///
    /// A COMPOSITOR reads a stated 49 otherwise (`fillingStatedTerminalField`): it
    /// fills the cells of the line it lays on a base wherever they name no colour,
    /// a stated 49 among them (`String.paintedOver(background:)`), so there a 49
    /// leaves the field to what is under it as much as a cell that says nothing.
    /// Read as the content's own, a stated 49 under a translucent
    /// `.listRowBackground` — which composites its content over its fill — had a
    /// claim beneath it, and showed the fill's opaque spelling in a row of the fill
    /// at its alpha.
    ///
    /// - Parameters:
    ///   - width: How many columns to answer for.
    ///   - fillingStatedTerminalField: Whether the painter fills a stated 49, as a
    ///     compositor does.
    /// - Returns: One entry per column, `true` where the painter's field shows.
    package func columnsLeavingFieldToPainter(width: Int, fillingStatedTerminalField: Bool = false) -> [Bool] {
        var result = [Bool](repeating: true, count: max(0, width))
        guard width > 0, !isEmpty else { return result }
        var state = SGRState()
        var stated = false
        var column = 0
        forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                guard isSGR else { return true }
                if let statement = state.applyReportingBackground(sequence) {
                    stated = statement != .reset
                }
            case .visible(let character):
                guard column < width else { return false }
                let cells = character.terminalWidth
                // A zero-width scalar belongs to the cell before it.
                guard cells > 0 else { return true }
                let leaves = !(fillingStatedTerminalField ? state.namesBackground : stated) && !state.reversesVideo
                for cell in column..<min(width, column + cells) { result[cell] = leaves }
                column += cells
            }
            return true
        }
        return result
    }
}
