//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Character+InkCoverage.swift
//
//  How much of a terminal cell a character's ink covers — the number that
//  turns "blend toward the background of what is behind" into "blend toward
//  the colour of what is behind".
//
//  Created by Wade Tregaskis
//  License: MIT

extension Character {

    /// The approximate fraction of a cell this character's ink covers (0...1).
    ///
    /// The average colour a cell displays is its ink and its field mixed by
    /// this fraction, and that average is what "behind" means to anything
    /// translucent drawn over the cell. The exact value is unknowable — it
    /// lives in the terminal's font rasteriser — but it does not need to be
    /// known equally well everywhere:
    ///
    /// - **Geometric glyphs are exact by construction.** A full block covers
    ///   the cell; halves, quadrants and eighths cover what their names say;
    ///   the shades ░▒▓ are ¼, ½ and ¾ by definition; a Braille pattern
    ///   covers its dot count. These are the glyphs used AS solid colour —
    ///   swatches, gauges, progress fills — which is exactly where treating a
    ///   cell as "all background" was most wrong.
    /// - **Everything else is an estimate**, and a coarse one is fine: for
    ///   ordinary text the ink is a small minority of the cell, so the
    ///   estimate's error is a small fraction of a small correction. The
    ///   default is 0.15, which is typical for Latin text; box-drawing lines
    ///   are thinner than text and get 0.1.
    ///
    /// One algorithm, varying confidence — an unrecognised character does not
    /// fall off a different blending cliff, it just gets the text-shaped
    /// estimate.
    ///
    /// Emoji are a knowing omission: they are colour bitmaps that ignore the
    /// foreground colour entirely, so no coverage number is meaningful for
    /// them and no colour arithmetic can fade them — the glyph threshold is
    /// the only mechanism a terminal offers there.
    package var inkCoverage: Double {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else { return 0.15 }
        switch scalar.value {
        case 0x20, 0xA0:  // space, no-break space
            return 0
        case 0x2500...0x257F:  // box drawing: lines thinner than text
            return 0.1
        case 0x2580, 0x2590:  // ▀ ▐ half blocks
            return 0.5
        case 0x2581...0x2588:  // ▁…█ lower eighths up to the full block
            return Double(scalar.value - 0x2580) / 8
        case 0x2589...0x258F:  // ▉…▏ left blocks, descending
            return Double(0x2590 - scalar.value) / 8
        case 0x2591:  // ░
            return 0.25
        case 0x2592:  // ▒
            return 0.5
        case 0x2593:  // ▓
            return 0.75
        case 0x2594, 0x2595:  // ▔ ▕ single eighths
            return 0.125
        case 0x2596...0x259F:  // quadrant combinations
            return Double(Self.quadrantCounts[Int(scalar.value - 0x2596)]) / 4
        case 0x25A0:  // ■ (sits inside the cell, unlike █)
            return 0.65
        case 0x25AC:  // ▬
            return 0.35
        case 0x25B2, 0x25BC, 0x25B6, 0x25C0:  // ▲▼▶◀
            return 0.4
        case 0x25CF:  // ●
            return 0.45
        case 0x25D0...0x25D3:  // ◐◑◒◓ half-filled discs
            return 0.3
        case 0x25E2...0x25E5:  // ◢◣◤◥ triangular halves
            return 0.5
        case 0x25A1...0x25FF:  // other geometric shapes: outlines and smalls
            return 0.2
        case 0x2800...0x28FF:  // Braille: the dots it raises
            return Double((scalar.value - 0x2800).nonzeroBitCount) * 0.0625
        default:
            return 0.15
        }
    }

    /// Filled quadrants of U+2596...U+259F, in code-point order:
    /// ▖ ▗ ▘ ▙ ▚ ▛ ▜ ▝ ▞ ▟
    private static let quadrantCounts: [Int] = [1, 1, 1, 3, 2, 3, 3, 1, 2, 3]
}
