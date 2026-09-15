//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSI16FollowsReportedSlotsTests.swift
//
//  `ASCIIPalette.ansi16` matches a pixel against each slot as the colour the terminal
//  reported for it, or xterm's value while it has reported none. It used to be a
//  `static let`, measured once at its first use, so a report that arrived later never
//  reached it. And a palette's search index was shared by every palette with the same
//  colours, though two such palettes measure their slots differently under two reports.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("The terminal's own sixteen follow the slots the terminal reported")
struct ANSI16FollowsReportedSlotsTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Terminal-compatibility.md), in slot order.
    private static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255), slots: TerminalColors.Slots(appleBasic))

    /// Nearer xterm's red (205, 0, 0) than its bright red, and nearer Apple Terminal's
    /// bright red (230, 0, 0) than its red (153, 0, 0).
    private static let pixel = RGBA(r: 220, g: 0, b: 0)

    private static func channels(_ entries: [ASCIIPalette.Entry]) -> [[UInt8]] {
        entries.map { [$0.rgba.r, $0.rgba.g, $0.rgba.b] }
    }

    /// The walk `nearestIndex(to:)` is held to, over the palette's own entries.
    private static func walked(_ palette: ASCIIPalette, _ pixel: RGBA) -> Int {
        let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
        var best = 0
        var bestDistance = Double.infinity
        for (index, entry) in palette.entries.enumerated() {
            let dl = target.l - entry.lightness, da = target.a - entry.a, db = target.b - entry.b
            let distance = dl * dl + da * da + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// The SGR codes a line sets, resets aside.
    private static func codes(_ lines: [String]) -> Set<Int> {
        var found = Set<Int>()
        var rest = Substring(lines.joined())
        while let open = rest.range(of: "\u{1B}[") {
            rest = rest[open.upperBound...]
            guard let close = rest.firstIndex(of: "m") else { break }
            for part in rest[rest.startIndex..<close].split(separator: ";") {
                if let code = Int(part), code != 0 { found.insert(code) }
            }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    @Test("ansi16 measures each slot as the report in force, and as xterm's value again once it is gone")
    func entriesFollowTheReport() {
        let xterm = ANSIColor.allCases.map { [$0.xtermRGB.red, $0.xtermRGB.green, $0.xtermRGB.blue] }
        let reported = Self.appleBasic.map { [$0.red, $0.green, $0.blue] }
        let slots = ANSIColor.allCases.map(Color.ansi)
        for (terminal, expected, code) in [
            (TerminalColors.unknown, xterm, "31"), (Self.appleTerminal, reported, "91"), (.unknown, xterm, "31"),
        ] {
            TerminalColors.withCurrent(terminal) {
                let sixteen = ASCIIPalette.ansi16
                #expect(sixteen.colors == slots, "the colours are the slots, whatever they measure as")
                #expect(Self.channels(sixteen.entries) == expected)
                #expect(sixteen.sgrParameters(at: sixteen.nearestIndex(to: Self.pixel), background: false) == code)
            }
        }
    }

    @Test("A picture drawn in the sixteen takes the slot nearest by the report, in glyphs and in pixels")
    func conversionFollowsTheReport() {
        let image = RGBAImage(width: 2, height: 2, pixels: Array(repeating: Self.pixel, count: 4))
        func glyphCodes() -> Set<Int> {
            // A true-colour request on a sixteen-colour terminal is drawn through `ansi16`,
            // and `.solid` puts the colour in the background family.
            let converter = ASCIIConverter(characterSet: .blocks(.solid), colorMode: .trueColor, dithering: .none)
            return ColorDepth.withCurrent(.basic16) { Self.codes(converter.convert(image, width: 2, height: 2).lines) }
        }
        func firstPixel() -> [UInt8] {
            let recoloured = ASCIIConverter(colorMode: .ansi16, dithering: .none).recoloured(image, width: 2, height: 2)
            return recoloured.pixels.first.map { [$0.r, $0.g, $0.b] } ?? []
        }
        for (terminal, code, painted) in [
            (TerminalColors.unknown, 41, [UInt8(205), 0, 0]), (Self.appleTerminal, 101, [230, 0, 0]),
            (.unknown, 41, [205, 0, 0]),
        ] {
            TerminalColors.withCurrent(terminal) {
                #expect(glyphCodes() == [code], "\(terminal.slots == nil ? "unreported" : "reported")")
                #expect(firstPixel() == painted, "\(terminal.slots == nil ? "unreported" : "reported")")
            }
        }
    }

    /// Eighteen entries, so the palette searches an index rather than walking, and two of
    /// them no other suite uses, so no other palette shares its colours.
    @Test("A palette whose slots measure differently is not searched through another's index")
    func searchIndexFollowsTheEntries() {
        let colours = ANSIColor.allCases.map(Color.ansi) + [.rgb(1, 2, 3), .rgb(3, 2, 1)]
        let unreported = TerminalColors.withCurrent(.unknown) { ASCIIPalette(colours) }
        #expect(unreported.consultedSearchIndex != nil, "the fixture must be large enough to be indexed")
        #expect(unreported.nearestIndex(to: Self.pixel) == 1)

        let reported = TerminalColors.withCurrent(Self.appleTerminal) { ASCIIPalette(colours) }
        #expect(reported == unreported, "the two compare equal by their colours, which is the trap")
        #expect(reported.nearestIndex(to: Self.pixel) == Self.walked(reported, Self.pixel))
        #expect(reported.nearestIndex(to: Self.pixel) == 9)
        // And the first is still answered by its own entries.
        #expect(unreported.nearestIndex(to: Self.pixel) == Self.walked(unreported, Self.pixel))
    }
}
