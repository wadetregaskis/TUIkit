//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCarriedColourTests.swift
//
//  `.terminalForeground` and `.terminalBackground`: the terminal's own default
//  colours, SGR 39 and 49, carrying the RGB they paint so a blend or a contrast
//  check can measure them. In its own slot one is the terminal's colour, whatever
//  RGB it carries; in the other slot no SGR names it, so it is spelled as that RGB.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Colours that carry the terminal's own foreground and background")
struct TerminalCarriedColourTests {

    /// One Dark's pair: ink #abb2bf on #282c34. Neither is a grey, so a quantised
    /// spelling cannot coincide with a named slot or the grey ramp by accident.
    private static let ink = Color(value: .terminalForeground(red: 171, green: 178, blue: 191))
    private static let paper = Color(value: .terminalBackground(red: 40, green: 44, blue: 52))

    private static let colourDepths: [ColorDepth] = [.truecolor, .palette256, .basic16]

    @Test("In its own slot, a carried colour is SGR 39 or 49 at every depth that has colour")
    func ownSlotIsTheDefault() {
        for depth in Self.colourDepths {
            #expect(Self.ink.foregroundCodes(depth: depth) == ["39"], "ink @\(depth)")
            #expect(Self.paper.backgroundCodes(depth: depth) == ["49"], "paper @\(depth)")
            #expect(Self.paper.backgroundEscape(depth: depth) == "\u{1B}[49m", "paper escape @\(depth)")
        }
    }

    @Test("At noColor, a carried colour emits nothing in either slot")
    func noColorEmitsNothing() {
        for colour in [Self.ink, Self.paper] {
            #expect(colour.foregroundCodes(depth: .noColor).isEmpty, "\(colour) fg")
            #expect(colour.backgroundCodes(depth: .noColor).isEmpty, "\(colour) bg")
            #expect(colour.backgroundEscape(depth: .noColor).isEmpty, "\(colour) escape")
        }
    }

    /// No SGR names the default foreground as a background, or the default
    /// background as a foreground, so the other slot gets the carried RGB, spelled
    /// the way an `.rgb` of the same components is spelled at that depth.
    @Test("In the other slot, a carried colour is its RGB, quantised for the depth")
    func otherSlotIsTheQuantisedRGB() {
        #expect(Self.ink.backgroundCodes(depth: .truecolor) == ["48", "2", "171", "178", "191"])
        #expect(Self.paper.foregroundCodes(depth: .truecolor) == ["38", "2", "40", "44", "52"])

        let inkIndex = Color.rgb(171, 178, 191).downsampledToPalette256()
        let paperIndex = Color.rgb(40, 44, 52).downsampledToPalette256()
        guard case .palette256(let inkCube) = inkIndex.value,
            case .palette256(let paperCube) = paperIndex.value
        else {
            Issue.record("the fixture: an RGB colour did not quantise to a 256-colour index")
            return
        }
        #expect(Self.ink.backgroundCodes(depth: .palette256) == ["48", "5", "\(inkCube)"])
        #expect(Self.paper.foregroundCodes(depth: .palette256) == ["38", "5", "\(paperCube)"])

        let inkSixteen = Self.ink.backgroundCodes(depth: .basic16)
        let paperSixteen = Self.paper.foregroundCodes(depth: .basic16)
        #expect(inkSixteen == Color.rgb(171, 178, 191).backgroundCodes(depth: .basic16))
        #expect(paperSixteen == Color.rgb(40, 44, 52).foregroundCodes(depth: .basic16))
        // A slot's own code, and not the default's, which is what the arm must avoid.
        #expect(inkSixteen.count == 1 && inkSixteen != ["49"], "got \(inkSixteen)")
        #expect(paperSixteen.count == 1 && paperSixteen != ["39"], "got \(paperSixteen)")
    }

    /// Downsampling does not know which slot a colour is for, so it cannot pick
    /// between 39 and a quantised RGB. The emitter does that, and downsampling
    /// leaves the carried case alone, alpha and all.
    @Test("Downsampling returns a carried colour unchanged")
    func downsamplingReturnsSelf() {
        var faded = Self.paper
        faded.alpha = 128
        for colour in [Self.ink, Self.paper, faded] {
            #expect(colour.downsampledToPalette256() == colour, "\(colour) to 256")
            #expect(colour.downsampledToANSI16() == colour, "\(colour) to 16")
            for depth in Self.colourDepths + [.noColor] {
                #expect(colour.downsampled(to: depth) == colour, "\(colour) to \(depth)")
            }
        }
    }

    @Test("A carried colour's components are the RGB it carries")
    func componentsAreTheCarriedRGB() {
        #expect(Self.ink.rgbComponents.map { [$0.red, $0.green, $0.blue] } == [171, 178, 191])
        #expect(Self.paper.rgbComponents.map { [$0.red, $0.green, $0.blue] } == [40, 44, 52])
        #expect(!Self.paper.isAchromatic)
        #expect(Color(value: .terminalBackground(red: 255, green: 255, blue: 255)).isAchromatic)
    }

    @Test("Blending a carried colour gives the blend of the RGB it carries")
    func blendsMeasureTheCarriedRGB() {
        let white = Color.rgb(255, 255, 255)
        #expect(Self.ink.opacity(0.5, over: white) == Color.rgb(171, 178, 191).opacity(0.5, over: white))
        #expect(Color.red.opacity(0.5, over: Self.paper) == Color.red.opacity(0.5, over: .rgb(40, 44, 52)))
        #expect(
            Self.ink.mix(with: Self.paper, by: 0.3)
                == Color.rgb(171, 178, 191).mix(with: .rgb(40, 44, 52), by: 0.3))
    }

    @Test("A carried colour is not equal to the RGB it carries, nor to its twin")
    func hashableKeepsThemDistinct() {
        let foreground = Color(value: .terminalForeground(red: 1, green: 2, blue: 3))
        let background = Color(value: .terminalBackground(red: 1, green: 2, blue: 3))
        let rgb = Color.rgb(1, 2, 3)
        #expect(foreground != rgb)
        #expect(background != rgb)
        #expect(foreground != background)
        #expect(Set([foreground, background, rgb]).count == 3)
    }

    /// Whether the terminal decides what a colour paints: the eight names and
    /// their bright twins, the default, 256-colour indices 0-15, and the carried
    /// cases. `.bright(.default)` is not a slot: its codes are 99 and 109, which
    /// are not SGR. The cube and grey ramp (16-255) are conventionally fixed.
    @Test("isTerminalDefined, over every case")
    func terminalDefinedOverEveryCase() {
        let eight = (0...7).compactMap { ANSIColor(rawValue: UInt8($0)) }
        #expect(eight.count == 8, "the fixture")
        for ansi in eight {
            #expect(Color(value: .standard(ansi)).isTerminalDefined, "standard \(ansi)")
            #expect(Color(value: .bright(ansi)).isTerminalDefined, "bright \(ansi)")
        }
        #expect(Color.default.isTerminalDefined)
        #expect(!Color(value: .bright(.default)).isTerminalDefined)
        for index in 0...255 {
            #expect(Color.palette(UInt8(index)).isTerminalDefined == (index < 16), "palette \(index)")
        }
        #expect(!Color.rgb(0, 0, 0).isTerminalDefined)
        #expect(!Color.rgb(229, 229, 229).isTerminalDefined)
        #expect(!Color.palette.foreground.isTerminalDefined)
        #expect(Self.ink.isTerminalDefined)
        #expect(Self.paper.isTerminalDefined)
    }

    /// The cases carry three bytes, like `.rgb`, so `Color` keeps its five bytes
    /// and no padding. `ColourAlphaStorageTests` explains why padding matters;
    /// this repeats the pin beside the cases that could break it.
    @Test("Color stays five bytes")
    func layoutIsUnchanged() {
        #expect(MemoryLayout<Color>.size == 5, "got \(MemoryLayout<Color>.size)")
        #expect(MemoryLayout<Color>.stride == 5, "got \(MemoryLayout<Color>.stride)")
    }
}
