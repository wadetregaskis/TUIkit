//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPaletteTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUIkitImage
import TUIkitStyling

@Suite("Image palettes")
struct ASCIIPaletteTests {

    // MARK: - Generated palettes

    @Test("A shade ramp runs black to white and is evenly spaced to the EYE")
    func shadesAreEvenlyPerceived() {
        let ramp = ASCIIPalette.shades(5)
        #expect(ramp.colors.count == 5)
        let values = ramp.colors.map { $0.rgbComponents!.red }
        #expect(values.first == 0)
        #expect(values.last == 255)
        #expect(values == values.sorted())
        // Evenly spaced in bytes would be 0, 64, 128, 191, 255. Evenly spaced
        // in perceived lightness puts the middle step well BELOW the byte
        // midpoint, which is the whole point — three of five bytes-even greys
        // land in the bright half where the eye can least tell them apart.
        #expect(values[2] < 128, "middle grey is \(values[2]); a byte-even ramp would say 128")
        let lightness = ramp.colors.map {
            Color.oklab(red: $0.rgbComponents!.red, green: $0.rgbComponents!.green,
                        blue: $0.rgbComponents!.blue).l
        }
        for step in 1..<lightness.count - 1 {
            let before = lightness[step] - lightness[step - 1]
            let after = lightness[step + 1] - lightness[step]
            #expect(abs(before - after) < 0.02, "uneven step at \(step): \(before) vs \(after)")
        }
    }

    @Test("Degenerate shade counts still make a palette")
    func degenerateShades() {
        #expect(ASCIIPalette.shades(1).colors == [.black])
        #expect(ASCIIPalette.shades(0).colors == [.black])
        #expect(ASCIIPalette.shades(-3).colors == [.black])
        #expect(ASCIIPalette([]).colors == [.black, .white])
    }

    @Test("A sampled palette spreads over the gamut instead of clustering")
    func sampledSpreads() {
        let sampled = ASCIIPalette.sampled(8)
        #expect(sampled.colors.count == 8)
        // Every entry is a 256-palette index, which is the constraint that
        // makes them render exactly on any 256-colour terminal.
        for colour in sampled.colors {
            guard case .palette256 = colour.value else {
                Issue.record("expected a palette index, got \(colour)")
                continue
            }
        }
        // No two the same, and no two nearly the same: farthest-point sampling
        // is chosen over "every k-th index" precisely to avoid that.
        #expect(Set(sampled.colors).count == 8)
        let labs = sampled.colors.map {
            let rgb = $0.rgbComponents!
            return Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        for (index, lhs) in labs.enumerated() {
            for rhs in labs[(index + 1)...] {
                #expect(ASCIIPalette.distanceSquared(lhs, rhs) > 0.01, "two entries sit on top of each other")
            }
        }
    }

    @Test("More colours asked for than the source has is not an error")
    func sampledSaturates() {
        #expect(ASCIIPalette.sampled(10_000).colors.count == 240)
        #expect(ASCIIPalette.sampled(1).colors.count == 1)
    }

    // MARK: - Mapping

    /// The rule the mapper rests on: for a palette that is a ramp, nearest in
    /// OKLab IS nearest in lightness, because the entries' a and b are equal
    /// and drop out. So `.shades(_:)` needs no special case.
    @Test("A grey ramp maps by lightness, and a coloured pixel finds its tone")
    func greyRampMapsByLightness() {
        let ramp = ASCIIPalette.shades(3)  // black, mid, white
        let mid = ramp.rgba(at: 1).r
        #expect(ramp.nearestIndex(to: RGBA(r: 0, g: 0, b: 0)) == 0)
        #expect(ramp.nearestIndex(to: RGBA(r: 255, g: 255, b: 255)) == 2)
        // A saturated colour has no grey of its own; it lands on the grey of
        // its own lightness, which is what makes a three-grey render read as a
        // photograph rather than as noise.
        let chosen = ramp.rgba(at: ramp.nearestIndex(to: RGBA(r: 255, g: 0, b: 0))).r
        #expect(chosen == mid || chosen == 0, "bright red landed on \(chosen)")
    }

    /// The case nearest-colour cannot serve, and the reason `.toneRamp` exists.
    @Test("A tone ramp spends every colour; nearest-colour need not")
    func toneRampSpendsEveryColour() {
        let colours: [Color] = [.black, .rgb(102, 255, 102), .rgb(229, 229, 229)]
        let greys = stride(from: 0, through: 255, by: 8).map {
            RGBA(r: UInt8($0), g: UInt8($0), b: UInt8($0))
        }
        // By nearest colour the middle entry is never reached: it sits at OKLab
        // L 0.887 against the last entry's 0.922, so every grey is closer to one
        // of the ends. Three colours asked for, two delivered.
        let nearest = ASCIIPalette(colours)
        #expect(!greys.map(nearest.nearestIndex(to:)).contains(1))
        // By rank all three are, in order, a third of the range each.
        let ramp = ASCIIPalette(colours).asToneRamp()
        let picked = greys.map(ramp.nearestIndex(to:))
        #expect(Set(picked) == [0, 1, 2])
        #expect(picked == picked.sorted(), "a darker pixel took a lighter entry")
        #expect(ramp.nearestIndex(to: RGBA(r: 0, g: 0, b: 0)) == 0)
        #expect(ramp.nearestIndex(to: RGBA(r: 255, g: 255, b: 255)) == 2)
    }

    @Test("A tone ramp orders itself, whatever order it was written in")
    func toneRampSortsItself() {
        let scrambled = ASCIIPalette([.white, .black, .rgb(128, 128, 128)]).asToneRamp()
        #expect(scrambled.rgba(at: scrambled.nearestIndex(to: RGBA(r: 0, g: 0, b: 0))).r == 0)
        #expect(scrambled.rgba(at: scrambled.nearestIndex(to: RGBA(r: 255, g: 255, b: 255))).r == 229)
    }

    @Test("The mapping is part of what a palette IS")
    func mappingIsPartOfIdentity() {
        // A render cache keyed on the colour mode has to notice this change, or
        // switching the demo's mapping would serve the old image forever.
        #expect(ASCIIPalette([.black, .white]) != ASCIIPalette([.black, .white]).asToneRamp())
        #expect(ASCIIPalette([.black, .white]).asToneRamp().downsampled(to: .basic16).mapping == .toneRamp)
        #expect(ASCIIPalette([.black, .white]).asToneRamp()
            .resolved(with: SystemPalette.green).mapping == .toneRamp)
    }

    @Test("A palette of hues keeps them apart")
    func huesStayApart() {
        let palette = ASCIIPalette([.rgb(200, 0, 0), .rgb(0, 160, 0), .rgb(0, 0, 200)])
        #expect(palette.nearestIndex(to: RGBA(r: 255, g: 40, b: 40)) == 0)
        #expect(palette.nearestIndex(to: RGBA(r: 30, g: 200, b: 60)) == 1)
        #expect(palette.nearestIndex(to: RGBA(r: 40, g: 40, b: 255)) == 2)
    }

    @Test("A semantic colour has no colour until the theme says so")
    func semanticResolves() {
        let unresolved = ASCIIPalette([.black, .palette.accent])
        // Unresolved, the accent stands in as mid-grey — what `Color.resolve`
        // itself falls back to — so an unresolved palette renders flat rather
        // than differently wrong.
        #expect(unresolved.rgba(at: 1) == RGBA(r: 128, g: 128, b: 128))
        let resolved = unresolved.resolved(with: SystemPalette.green)
        #expect(resolved.rgba(at: 1) != RGBA(r: 128, g: 128, b: 128))
        // And the colours it names still compare as written, so a cache keyed
        // on the mode sees a theme change.
        #expect(resolved != unresolved)
    }

    // MARK: - Degrading

    @Test("A chosen palette survives a downgrade where a fidelity mode cannot")
    func paletteDegrades() {
        let palette = ASCIIPalette([.rgb(200, 30, 30), .rgb(30, 30, 200)])
        let mode = ASCIIColorMode.palette(palette)
        // `.trueColor` has to be abandoned on a 16-colour terminal; a palette
        // keeps its intent and loses only accuracy.
        #expect(ASCIIColorMode.trueColor.effective(for: .basic16) == .mono)
        guard case .palette(let at16) = mode.effective(for: .basic16) else {
            Issue.record("the palette did not survive")
            return
        }
        #expect(at16.colors.count == 2)
        for colour in at16.colors {
            switch colour.value {
            case .standard, .bright: break
            default: Issue.record("\(colour) is not one of the 16")
            }
        }
        guard case .palette(let at256) = mode.effective(for: .palette256) else {
            Issue.record("the palette did not survive to 256")
            return
        }
        for colour in at256.colors {
            guard case .palette256 = colour.value else {
                Issue.record("\(colour) is not a 256-palette index")
                continue
            }
        }
        // No colour at all is still no colour at all.
        #expect(mode.effective(for: .noColor) == .mono)
    }

    @Test("The escape says the colour in the form the terminal understands")
    func escapesMatchTheForm() {
        let rgb = ASCIIPalette([.rgb(10, 20, 30)])
        #expect(rgb.sgrParameters(at: 0, background: false) == "38;2;10;20;30")
        #expect(rgb.sgrParameters(at: 0, background: true) == "48;2;10;20;30")
        let indexed = ASCIIPalette([.palette(123)])
        #expect(indexed.sgrParameters(at: 0, background: false) == "38;5;123")
        let basic = ASCIIPalette([.red, .brightBlue])
        #expect(basic.sgrParameters(at: 0, background: false) == "31")
        #expect(basic.sgrParameters(at: 1, background: true) == "104")
    }

    // MARK: - Through the converter

    /// A gradient, so there is real tonal structure to preserve or destroy.
    private func gradient(width: Int = 24, height: Int = 12) -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8(clamping: (x * 255) / max(1, width - 1))
                pixels.append(RGBA(r: value, g: value / 2, b: UInt8(clamping: (y * 255) / max(1, height - 1))))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    @Test("A palette render draws in the palette's colours and nothing else")
    func paletteRenderUsesOnlyItsColours() {
        let palette = ASCIIPalette([.rgb(200, 30, 30), .rgb(30, 200, 30), .rgb(30, 30, 200)])
        let converter = ASCIIConverter(
            characterSet: .blocks(.solid), colorMode: .palette(palette))
        let lines = ColorDepth.withCurrent(.truecolor) {
            converter.convert(gradient(), width: 12, height: 6)
        }
        #expect(!lines.isEmpty)
        let emitted = Set(
            lines.joined().components(separatedBy: "\u{1B}[").compactMap { chunk -> String? in
                guard let end = chunk.firstIndex(of: "m") else { return nil }
                return String(chunk[chunk.startIndex..<end])
            })
        let allowed: Set<String> = [
            "0", "38;2;200;30;30", "38;2;30;200;30", "38;2;30;30;200",
            "48;2;200;30;30", "48;2;30;200;30", "48;2;30;30;200",
        ]
        #expect(emitted.subtracting(allowed).isEmpty, "off-palette colours: \(emitted.subtracting(allowed))")
        // And it used more than one of them — a render that collapsed to a
        // single colour would satisfy the check above and be useless.
        #expect(emitted.subtracting(["0"]).count >= 2)
    }

    @Test("A palette render on a 256-colour terminal says so in indices")
    func paletteRenderDowngrades() {
        let converter = ASCIIConverter(
            characterSet: .blocks(.solid), colorMode: .palette(ASCIIPalette([.rgb(200, 30, 30), .rgb(30, 30, 200)])))
        let lines = ColorDepth.withCurrent(.palette256) {
            converter.convert(gradient(), width: 8, height: 4)
        }
        // `.blocks(.solid)` paints whole cells, so it says its colours as
        // BACKGROUNDS — the form is what matters here, not which channel.
        #expect(lines.joined().contains("\u{1B}[48;5;"))
        #expect(!lines.joined().contains(";2;"), "truecolor escapes on a 256-colour terminal")
    }
}
