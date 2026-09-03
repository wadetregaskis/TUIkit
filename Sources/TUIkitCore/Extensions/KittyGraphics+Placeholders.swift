//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyGraphics+Placeholders.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drawing an image as text

extension KittyGraphics {

    /// The largest image, in cells, that placeholders can address on either
    /// axis — the length of `rowColumnDiacritics`.
    ///
    /// A hard limit of the protocol rather than a policy: row and column are
    /// carried as one combining mark each, drawn from a fixed table, so cell
    /// 297 of a row has nothing to name it with. A terminal wider than this is
    /// possible (a very wide monitor, a small font), and an image needing more
    /// cells than this must fall back to the glyph renderer rather than be
    /// drawn truncated.
    public static var maximumCellExtent: Int { rowColumnDiacritics.count }

    /// The `rows` lines of placeholder cells that draw image `id`, already
    /// carrying the foreground that names it.
    ///
    /// This is the output the renderer puts in a ``FrameBuffer``, and it is
    /// ordinary text: `columns` cells wide by `strippedLength`,
    /// clipped by whatever clips cells, scrolled by whatever scrolls them.
    ///
    /// ## Every cell names itself
    ///
    /// The protocol allows a run-length form — a cell with no diacritics
    /// continues the previous one — and it works (measured: 67 bytes a row
    /// instead of 111). TUIkit does not use it, deliberately.
    ///
    /// A diffing writer does not write rows, it writes *runs*: the four cells
    /// that changed, after a cursor jump, in whatever order the diff produced.
    /// A cell that says "the one after the last one" means nothing when the
    /// last one was written a frame ago and somewhere else. Spelling row and
    /// column into every cell costs a third of a row's bytes — a row that is
    /// only rewritten when it changes — and buys the property that an image
    /// cell is correct wherever it lands.
    /// ``Unicode/Scalar/terminalImagePlaceholder`` records the other half of
    /// that decision: such a row declines the cell-span diff outright.
    ///
    /// - Returns: the rows, or `[]` for a request the protocol cannot express
    ///   — a non-positive size, an id outside ``maximumImageID``, or an extent
    ///   past ``maximumCellExtent``.
    public static func placeholderRows(id: ImageID, columns: Int, rows: Int) -> [String] {
        guard id > 0, id <= maximumImageID,
            columns > 0, rows > 0,
            columns <= maximumCellExtent, rows <= maximumCellExtent
        else { return [] }

        // The id, in the foreground colour. A direct-colour triple rather than
        // the 256-colour form (both are read as numbers, and both were
        // measured to work) because one spelling carries the whole 24-bit
        // range, and one spelling is one thing to get right.
        let prefix = "\u{1B}[38;2;\((id >> 16) & 0xFF);\((id >> 8) & 0xFF);\(id & 0xFF)m"

        return (0..<rows).map { row in
            var line = prefix
            // Placeholder (4 bytes) plus THREE marks per cell, and the last
            // of the marks is U+1D244 — four bytes, not three. The reset is
            // five.
            line.reserveCapacity(prefix.utf8.count + columns * 14 + 5)
            let rowMark = diacritic(row)
            for column in 0..<columns {
                line.unicodeScalars.append(.terminalImagePlaceholder)
                line.unicodeScalars.append(rowMark)
                line.unicodeScalars.append(diacritic(column))
                // The third mark: the id's most significant byte, which for
                // every id this type will issue is ZERO — ``maximumImageID``
                // caps them at 24 bits precisely so the foreground can carry
                // the whole of one.
                //
                // The protocol says a cell may omit it, and TUIkit did, and
                // that was the bug. **iTerm2 draws nothing without it**
                // (measured 2026-09-03, `placeholder_spelling_probe.py`: two
                // marks blank, three marks draw, on both the 256-colour and
                // the 24-bit foreground spelling) — an omitted mark and an
                // explicit zero are not the same statement to every decoder,
                // and a terminal that carries a sentinel for "absent" and ORs
                // it into the id looks up an image nobody transmitted. It
                // then acknowledges every command and paints an empty
                // rectangle, which is exactly what iTerm2 was doing and why
                // the handshake could not catch it.
                //
                // kitty and Ghostty compute `(0 << 24) | fg` either way, so
                // they see no change at all. The cost is two bytes a cell.
                line.unicodeScalars.append(diacritic(0))
            }
            // Foreground only. The row's background is the caller's business:
            // a transparent image composites over whatever that background is,
            // so resetting the lot here would flatten every picture with alpha
            // onto the terminal's default rather than onto the page.
            line += "\u{1B}[39m"
            return line
        }
    }

    /// The combining mark that means `index`.
    ///
    /// Falls back to the first entry rather than trapping: the callers already
    /// bound the index by ``maximumCellExtent``, so reaching the fallback means
    /// a bound was lost, and a picture with one wrong stripe is a better
    /// failure than a crash inside a render pass.
    static func diacritic(_ index: Int) -> Unicode.Scalar {
        guard index >= 0, index < rowColumnDiacritics.count,
            let scalar = Unicode.Scalar(rowColumnDiacritics[index])
        else { return "\u{0305}" }
        return scalar
    }

    /// Kitty's row/column diacritics, verbatim from `gen/rowcolumn-diacritics.txt`
    /// in the kitty repository: the combining marks of canonical combining
    /// class 230 in Unicode 6.0.0 that neither decompose nor fuse with a base.
    ///
    /// The Nth entry means N, so this table's ORDER is the protocol and cannot
    /// be sorted, deduplicated or extended — a terminal reads position, not
    /// codepoint. `Tools/TerminalProbes/placement_probe.py` carries the same
    /// table and draws a hue ramp with it, which is the only way to SEE a
    /// disagreement: a wrong entry tears one stripe out of a picture and
    /// changes nothing else.
    static let rowColumnDiacritics: [UInt32] = [
        0x00305, 0x0030D, 0x0030E, 0x00310, 0x00312, 0x0033D, 0x0033E, 0x0033F, 0x00346, 0x0034A,
        0x0034B, 0x0034C, 0x00350, 0x00351, 0x00352, 0x00357, 0x0035B, 0x00363, 0x00364, 0x00365,
        0x00366, 0x00367, 0x00368, 0x00369, 0x0036A, 0x0036B, 0x0036C, 0x0036D, 0x0036E, 0x0036F,
        0x00483, 0x00484, 0x00485, 0x00486, 0x00487, 0x00592, 0x00593, 0x00594, 0x00595, 0x00597,
        0x00598, 0x00599, 0x0059C, 0x0059D, 0x0059E, 0x0059F, 0x005A0, 0x005A1, 0x005A8, 0x005A9,
        0x005AB, 0x005AC, 0x005AF, 0x005C4, 0x00610, 0x00611, 0x00612, 0x00613, 0x00614, 0x00615,
        0x00616, 0x00617, 0x00657, 0x00658, 0x00659, 0x0065A, 0x0065B, 0x0065D, 0x0065E, 0x006D6,
        0x006D7, 0x006D8, 0x006D9, 0x006DA, 0x006DB, 0x006DC, 0x006DF, 0x006E0, 0x006E1, 0x006E2,
        0x006E4, 0x006E7, 0x006E8, 0x006EB, 0x006EC, 0x00730, 0x00732, 0x00733, 0x00735, 0x00736,
        0x0073A, 0x0073D, 0x0073F, 0x00740, 0x00741, 0x00743, 0x00745, 0x00747, 0x00749, 0x0074A,
        0x007EB, 0x007EC, 0x007ED, 0x007EE, 0x007EF, 0x007F0, 0x007F1, 0x007F3, 0x00816, 0x00817,
        0x00818, 0x00819, 0x0081B, 0x0081C, 0x0081D, 0x0081E, 0x0081F, 0x00820, 0x00821, 0x00822,
        0x00823, 0x00825, 0x00826, 0x00827, 0x00829, 0x0082A, 0x0082B, 0x0082C, 0x0082D, 0x00951,
        0x00953, 0x00954, 0x00F82, 0x00F83, 0x00F86, 0x00F87, 0x0135D, 0x0135E, 0x0135F, 0x017DD,
        0x0193A, 0x01A17, 0x01A75, 0x01A76, 0x01A77, 0x01A78, 0x01A79, 0x01A7A, 0x01A7B, 0x01A7C,
        0x01B6B, 0x01B6D, 0x01B6E, 0x01B6F, 0x01B70, 0x01B71, 0x01B72, 0x01B73, 0x01CD0, 0x01CD1,
        0x01CD2, 0x01CDA, 0x01CDB, 0x01CE0, 0x01DC0, 0x01DC1, 0x01DC3, 0x01DC4, 0x01DC5, 0x01DC6,
        0x01DC7, 0x01DC8, 0x01DC9, 0x01DCB, 0x01DCC, 0x01DD1, 0x01DD2, 0x01DD3, 0x01DD4, 0x01DD5,
        0x01DD6, 0x01DD7, 0x01DD8, 0x01DD9, 0x01DDA, 0x01DDB, 0x01DDC, 0x01DDD, 0x01DDE, 0x01DDF,
        0x01DE0, 0x01DE1, 0x01DE2, 0x01DE3, 0x01DE4, 0x01DE5, 0x01DE6, 0x01DFE, 0x020D0, 0x020D1,
        0x020D4, 0x020D5, 0x020D6, 0x020D7, 0x020DB, 0x020DC, 0x020E1, 0x020E7, 0x020E9, 0x020F0,
        0x02CEF, 0x02CF0, 0x02CF1, 0x02DE0, 0x02DE1, 0x02DE2, 0x02DE3, 0x02DE4, 0x02DE5, 0x02DE6,
        0x02DE7, 0x02DE8, 0x02DE9, 0x02DEA, 0x02DEB, 0x02DEC, 0x02DED, 0x02DEE, 0x02DEF, 0x02DF0,
        0x02DF1, 0x02DF2, 0x02DF3, 0x02DF4, 0x02DF5, 0x02DF6, 0x02DF7, 0x02DF8, 0x02DF9, 0x02DFA,
        0x02DFB, 0x02DFC, 0x02DFD, 0x02DFE, 0x02DFF, 0x0A66F, 0x0A67C, 0x0A67D, 0x0A6F0, 0x0A6F1,
        0x0A8E0, 0x0A8E1, 0x0A8E2, 0x0A8E3, 0x0A8E4, 0x0A8E5, 0x0A8E6, 0x0A8E7, 0x0A8E8, 0x0A8E9,
        0x0A8EA, 0x0A8EB, 0x0A8EC, 0x0A8ED, 0x0A8EE, 0x0A8EF, 0x0A8F0, 0x0A8F1, 0x0AAB0, 0x0AAB2,
        0x0AAB3, 0x0AAB7, 0x0AAB8, 0x0AABE, 0x0AABF, 0x0AAC1, 0x0FE20, 0x0FE21, 0x0FE22, 0x0FE23,
        0x0FE24, 0x0FE25, 0x0FE26, 0x10A0F, 0x10A38, 0x1D185, 0x1D186, 0x1D187, 0x1D188, 0x1D189,
        0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242, 0x1D243, 0x1D244,
    ]
}
