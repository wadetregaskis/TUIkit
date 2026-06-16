//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SwatchPalettes.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// Curated colour sets shown as swatch grids in ``ColorPickerPanel`` (and usable
/// anywhere a fixed palette is handy). Plain-colour sets are `[Color]`; named
/// sets are `[(name, Color)]` so a picker can show the colour's name.
enum SwatchPalettes {
    /// A 32-step black→white greyscale ramp, evenly spaced across 0…255.
    static let greyscale: [Color] = (0..<32).map { step in
        let value = UInt8((Double(step) * 255 / 31).rounded())
        return .rgb(value, value, value)
    }

    /// The 216 "web-safe" colours: every combination of the six channel levels
    /// 0, 51, 102, 153, 204, 255 (00/33/66/99/CC/FF). Correct by construction —
    /// this *is* the web-safe palette. Ordered red-major so each red level forms
    /// a contiguous block.
    static let webSafe: [Color] = {
        let levels: [UInt8] = [0, 51, 102, 153, 204, 255]
        var colors: [Color] = []
        colors.reserveCapacity(216)
        for red in levels {
            for green in levels {
                for blue in levels {
                    colors.append(.rgb(red, green, blue))
                }
            }
        }
        return colors
    }()

    /// The CSS / HTML named colours (CSS Color Module Level 4 — the 148 named
    /// keywords, including `rebeccapurple`). Synonyms that name the same value
    /// (e.g. `gray`/`grey`, `aqua`/`cyan`, `fuchsia`/`magenta`) are collapsed to
    /// one swatch, and the set is sorted into a spectrum — chromatic colours by
    /// hue then lightness, the neutrals by lightness — so the grid reads cleanly.
    static let cssNamed: [(name: String, color: Color)] = spectrumSorted(deduplicated(cssNamedRaw))

    /// The 48 crayons of macOS's "Crayons" colour picker, in its 8×6 arrangement
    /// (six tint→shade colour columns, then the two-wide neutral ramp). Selection
    /// and values match Apple's selector — note it has "Sea Foam", not "Mandarin".
    static let crayons: [(name: String, color: Color)] = crayonsRaw.map { ($0.0, .hex($0.1)) }

    // MARK: - Helpers

    /// Drops later entries whose colour value already appeared (synonyms).
    private static func deduplicated(_ raw: [(String, UInt32)]) -> [(name: String, color: Color, hex: UInt32)] {
        var seen = Set<UInt32>()
        var result: [(name: String, color: Color, hex: UInt32)] = []
        for (name, hex) in raw where seen.insert(hex).inserted {
            result.append((name, .hex(hex), hex))
        }
        return result
    }

    /// Sorts into a spectrum: chromatic colours by hue then lightness, neutrals
    /// (near-zero saturation) gathered after them and ordered light→dark.
    private static func spectrumSorted(
        _ entries: [(name: String, color: Color, hex: UInt32)]
    ) -> [(name: String, color: Color)] {
        func hsl(_ hex: UInt32) -> (hue: Double, saturation: Double, lightness: Double) {
            Color.rgbToHSL(
                red: UInt8((hex >> 16) & 0xFF),
                green: UInt8((hex >> 8) & 0xFF),
                blue: UInt8(hex & 0xFF))
        }
        return entries
            .map { (entry: $0, hsl: hsl($0.hex)) }
            .sorted { a, b in
                let greyA = a.hsl.saturation < 6
                let greyB = b.hsl.saturation < 6
                if greyA != greyB { return !greyA }                 // chromatic first
                if greyA { return a.hsl.lightness > b.hsl.lightness } // neutrals light→dark
                if a.hsl.hue != b.hsl.hue { return a.hsl.hue < b.hsl.hue }
                return a.hsl.lightness < b.hsl.lightness
            }
            .map { ($0.entry.name, $0.entry.color) }
    }

    // MARK: - Raw data

    /// The 148 CSS named colours (name, 0xRRGGBB). Order here is irrelevant —
    /// ``cssNamed`` deduplicates and re-sorts.
    private static let cssNamedRaw: [(String, UInt32)] = [
        ("aliceblue", 0xF0F8FF), ("antiquewhite", 0xFAEBD7), ("aqua", 0x00FFFF),
        ("aquamarine", 0x7FFFD4), ("azure", 0xF0FFFF), ("beige", 0xF5F5DC),
        ("bisque", 0xFFE4C4), ("black", 0x000000), ("blanchedalmond", 0xFFEBCD),
        ("blue", 0x0000FF), ("blueviolet", 0x8A2BE2), ("brown", 0xA52A2A),
        ("burlywood", 0xDEB887), ("cadetblue", 0x5F9EA0), ("chartreuse", 0x7FFF00),
        ("chocolate", 0xD2691E), ("coral", 0xFF7F50), ("cornflowerblue", 0x6495ED),
        ("cornsilk", 0xFFF8DC), ("crimson", 0xDC143C), ("cyan", 0x00FFFF),
        ("darkblue", 0x00008B), ("darkcyan", 0x008B8B), ("darkgoldenrod", 0xB8860B),
        ("darkgray", 0xA9A9A9), ("darkgreen", 0x006400), ("darkgrey", 0xA9A9A9),
        ("darkkhaki", 0xBDB76B), ("darkmagenta", 0x8B008B), ("darkolivegreen", 0x556B2F),
        ("darkorange", 0xFF8C00), ("darkorchid", 0x9932CC), ("darkred", 0x8B0000),
        ("darksalmon", 0xE9967A), ("darkseagreen", 0x8FBC8F), ("darkslateblue", 0x483D8B),
        ("darkslategray", 0x2F4F4F), ("darkslategrey", 0x2F4F4F), ("darkturquoise", 0x00CED1),
        ("darkviolet", 0x9400D3), ("deeppink", 0xFF1493), ("deepskyblue", 0x00BFFF),
        ("dimgray", 0x696969), ("dimgrey", 0x696969), ("dodgerblue", 0x1E90FF),
        ("firebrick", 0xB22222), ("floralwhite", 0xFFFAF0), ("forestgreen", 0x228B22),
        ("fuchsia", 0xFF00FF), ("gainsboro", 0xDCDCDC), ("ghostwhite", 0xF8F8FF),
        ("goldenrod", 0xDAA520), ("gold", 0xFFD700), ("gray", 0x808080),
        ("green", 0x008000), ("greenyellow", 0xADFF2F), ("grey", 0x808080),
        ("honeydew", 0xF0FFF0), ("hotpink", 0xFF69B4), ("indianred", 0xCD5C5C),
        ("indigo", 0x4B0082), ("ivory", 0xFFFFF0), ("khaki", 0xF0E68C),
        ("lavenderblush", 0xFFF0F5), ("lavender", 0xE6E6FA), ("lawngreen", 0x7CFC00),
        ("lemonchiffon", 0xFFFACD), ("lightblue", 0xADD8E6), ("lightcoral", 0xF08080),
        ("lightcyan", 0xE0FFFF), ("lightgoldenrodyellow", 0xFAFAD2), ("lightgray", 0xD3D3D3),
        ("lightgreen", 0x90EE90), ("lightgrey", 0xD3D3D3), ("lightpink", 0xFFB6C1),
        ("lightsalmon", 0xFFA07A), ("lightseagreen", 0x20B2AA), ("lightskyblue", 0x87CEFA),
        ("lightslategray", 0x778899), ("lightslategrey", 0x778899), ("lightsteelblue", 0xB0C4DE),
        ("lightyellow", 0xFFFFE0), ("lime", 0x00FF00), ("limegreen", 0x32CD32),
        ("linen", 0xFAF0E6), ("magenta", 0xFF00FF), ("maroon", 0x800000),
        ("mediumaquamarine", 0x66CDAA), ("mediumblue", 0x0000CD), ("mediumorchid", 0xBA55D3),
        ("mediumpurple", 0x9370DB), ("mediumseagreen", 0x3CB371), ("mediumslateblue", 0x7B68EE),
        ("mediumspringgreen", 0x00FA9A), ("mediumturquoise", 0x48D1CC), ("mediumvioletred", 0xC71585),
        ("midnightblue", 0x191970), ("mintcream", 0xF5FFFA), ("mistyrose", 0xFFE4E1),
        ("moccasin", 0xFFE4B5), ("navajowhite", 0xFFDEAD), ("navy", 0x000080),
        ("oldlace", 0xFDF5E6), ("olive", 0x808000), ("olivedrab", 0x6B8E23),
        ("orange", 0xFFA500), ("orangered", 0xFF4500), ("orchid", 0xDA70D6),
        ("palegoldenrod", 0xEEE8AA), ("palegreen", 0x98FB98), ("paleturquoise", 0xAFEEEE),
        ("palevioletred", 0xDB7093), ("papayawhip", 0xFFEFD5), ("peachpuff", 0xFFDAB9),
        ("peru", 0xCD853F), ("pink", 0xFFC0CB), ("plum", 0xDDA0DD),
        ("powderblue", 0xB0E0E6), ("purple", 0x800080), ("rebeccapurple", 0x663399),
        ("red", 0xFF0000), ("rosybrown", 0xBC8F8F), ("royalblue", 0x4169E1),
        ("saddlebrown", 0x8B4513), ("salmon", 0xFA8072), ("sandybrown", 0xF4A460),
        ("seagreen", 0x2E8B57), ("seashell", 0xFFF5EE), ("sienna", 0xA0522D),
        ("silver", 0xC0C0C0), ("skyblue", 0x87CEEB), ("slateblue", 0x6A5ACD),
        ("slategray", 0x708090), ("slategrey", 0x708090), ("snow", 0xFFFAFA),
        ("springgreen", 0x00FF7F), ("steelblue", 0x4682B4), ("tan", 0xD2B48C),
        ("teal", 0x008080), ("thistle", 0xD8BFD8), ("tomato", 0xFF6347),
        ("turquoise", 0x40E0D0), ("violet", 0xEE82EE), ("wheat", 0xF5DEB3),
        ("white", 0xFFFFFF), ("whitesmoke", 0xF5F5F5), ("yellow", 0xFFFF00),
        ("yellowgreen", 0x9ACD32),
    ]

    /// macOS Crayons, row-major in the selector's 8×6 grid: columns 1–6 are the
    /// six colour columns (tint at top → shade at bottom), columns 7–8 the
    /// neutral ramp (Licorice→Snow paired down each row).
    private static let crayonsRaw: [(String, UInt32)] = [
        // Row 1
        ("Cantaloupe", 0xFFCC66), ("Honeydew", 0xCCFF66), ("Spindrift", 0x66FFCC),
        ("Sky", 0x66CCFF), ("Lavender", 0xCC66FF), ("Carnation", 0xFF66FF),
        ("Licorice", 0x000000), ("Snow", 0xFFFFFF),
        // Row 2
        ("Salmon", 0xFF6666), ("Banana", 0xFFFF66), ("Flora", 0x66FF66),
        ("Ice", 0x66FFFF), ("Orchid", 0x6666FF), ("Bubblegum", 0xFF66CC),
        ("Lead", 0x191919), ("Mercury", 0xE6E6E6),
        // Row 3
        ("Tangerine", 0xFF8000), ("Lime", 0x80FF00), ("Sea Foam", 0x00FF80),
        ("Aqua", 0x0080FF), ("Grape", 0x8000FF), ("Strawberry", 0xFF0080),
        ("Tungsten", 0x333333), ("Silver", 0xCCCCCC),
        // Row 4
        ("Maraschino", 0xFF0000), ("Lemon", 0xFFFF00), ("Spring", 0x00FF00),
        ("Turquoise", 0x00FFFF), ("Blueberry", 0x0000FF), ("Magenta", 0xFF00FF),
        ("Iron", 0x4C4C4C), ("Magnesium", 0xB3B3B3),
        // Row 5
        ("Mocha", 0x804000), ("Fern", 0x408000), ("Moss", 0x008040),
        ("Ocean", 0x004080), ("Eggplant", 0x400080), ("Maroon", 0x800040),
        ("Steel", 0x666666), ("Aluminum", 0x999999),
        // Row 6
        ("Cayenne", 0x800000), ("Asparagus", 0x808000), ("Clover", 0x008000),
        ("Teal", 0x008080), ("Midnight", 0x000080), ("Plum", 0x800080),
        ("Tin", 0x7F7F7F), ("Nickel", 0x808080),
    ]
}
