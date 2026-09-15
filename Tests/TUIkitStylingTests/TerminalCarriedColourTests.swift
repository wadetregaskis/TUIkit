//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalCarriedColourTests.swift
//
//  `.terminalForeground` and `.terminalBackground`: the terminal's own default
//  colours, SGR 39 and 49. In its own slot one is the terminal's colour, whatever
//  the terminal said. It measures as the RGB the terminal reported through OSC 10
//  or 11 (`TerminalColors.current`), or as nothing. In the other slot no SGR names
//  it, so it is spelled as that reported RGB, or, while the terminal has said
//  nothing, as the other slot's own default.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Colours that are the terminal's own foreground and background")
struct TerminalCarriedColourTests {

    private static let ink = Color(value: .terminalForeground)
    private static let paper = Color(value: .terminalBackground)

    /// One Dark's pair: ink #abb2bf on #282c34. Neither is a grey, so a quantised
    /// spelling cannot coincide with a named slot or the grey ramp by accident.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    private static let terminals: [(name: String, colours: TerminalColors)] = [
        ("unknown", .unknown), ("reported", reported),
    ]

    private static let colourDepths: [ColorDepth] = [.truecolor, .palette256, .basic16]

    @Test("In its own slot, a carried colour is SGR 39 or 49 at every depth that has colour, reported or not")
    func ownSlotIsTheDefault() {
        for terminal in Self.terminals {
            TerminalColors.withCurrent(terminal.colours) {
                for depth in Self.colourDepths {
                    #expect(Self.ink.foregroundCodes(depth: depth) == ["39"], "ink @\(depth), \(terminal.name)")
                    #expect(Self.paper.backgroundCodes(depth: depth) == ["49"], "paper @\(depth), \(terminal.name)")
                    #expect(
                        Self.paper.backgroundEscape(depth: depth) == "\u{1B}[49m",
                        "paper escape @\(depth), \(terminal.name)")
                }
            }
        }
    }

    @Test("At noColor, a carried colour emits nothing in either slot, reported or not")
    func noColorEmitsNothing() {
        for terminal in Self.terminals {
            TerminalColors.withCurrent(terminal.colours) {
                for colour in [Self.ink, Self.paper] {
                    #expect(colour.foregroundCodes(depth: .noColor).isEmpty, "\(colour) fg, \(terminal.name)")
                    #expect(colour.backgroundCodes(depth: .noColor).isEmpty, "\(colour) bg, \(terminal.name)")
                    #expect(colour.backgroundEscape(depth: .noColor).isEmpty, "\(colour) escape, \(terminal.name)")
                }
            }
        }
    }

    /// No SGR names the default foreground as a background, or the default
    /// background as a foreground, so once the terminal has reported the colour,
    /// the other slot gets that RGB, spelled the way an `.rgb` of the same
    /// components is spelled at that depth.
    @Test("Once reported, a carried colour in the other slot is the reported RGB, quantised for the depth")
    func otherSlotIsTheReportedRGB() {
        TerminalColors.withCurrent(Self.reported) {
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
    }

    /// With nothing reported there is no RGB to spell, and no guess is made: the
    /// other slot gets its own default, so a colour that stands for the page and
    /// is drawn as ink comes out as 39.
    @Test("While unknown, a carried colour in the other slot is that slot's own default")
    func otherSlotIsItsOwnDefaultWhileUnknown() {
        TerminalColors.withCurrent(.unknown) {
            for depth in Self.colourDepths {
                #expect(Self.ink.backgroundCodes(depth: depth) == ["49"], "ink as bg @\(depth)")
                #expect(Self.ink.backgroundEscape(depth: depth) == "\u{1B}[49m", "ink as bg escape @\(depth)")
                #expect(Self.paper.foregroundCodes(depth: depth) == ["39"], "paper as fg @\(depth)")
            }
        }
    }

    /// Downsampling does not know which slot a colour is for, so it cannot pick
    /// between the default and a quantised RGB. The emitter does that, and
    /// downsampling leaves the carried case alone, alpha and all.
    @Test("Downsampling returns a carried colour unchanged")
    func downsamplingReturnsSelf() {
        var faded = Self.paper
        faded.alpha = 128
        for terminal in Self.terminals {
            TerminalColors.withCurrent(terminal.colours) {
                for colour in [Self.ink, Self.paper, faded] {
                    #expect(colour.downsampledToPalette256() == colour, "\(colour) to 256, \(terminal.name)")
                    #expect(colour.downsampledToANSI16() == colour, "\(colour) to 16, \(terminal.name)")
                    for depth in Self.colourDepths + [.noColor] {
                        #expect(colour.downsampled(to: depth) == colour, "\(colour) to \(depth), \(terminal.name)")
                    }
                }
            }
        }
    }

    @Test("A carried colour measures as the reported RGB, and as nothing while unknown")
    func componentsAreTheReportedRGB() {
        TerminalColors.withCurrent(Self.reported) {
            #expect(Self.ink.rgbComponents.map { [$0.red, $0.green, $0.blue] } == [171, 178, 191])
            #expect(Self.paper.rgbComponents.map { [$0.red, $0.green, $0.blue] } == [40, 44, 52])
            #expect(!Self.paper.isAchromatic)
        }
        let whitePage = TerminalColors(background: TerminalColors.RGB(red: 255, green: 255, blue: 255))
        TerminalColors.withCurrent(whitePage) {
            #expect(Self.paper.isAchromatic)
            #expect(Self.ink.rgbComponents == nil, "only the background was reported")
            #expect(!Self.ink.isAchromatic, "an unmeasurable colour is not a grey")
        }
        TerminalColors.withCurrent(.unknown) {
            #expect(Self.ink.rgbComponents == nil)
            #expect(Self.paper.rgbComponents == nil)
            #expect(!Self.ink.isAchromatic)
            #expect(!Self.paper.isAchromatic)
        }
    }

    @Test("Once reported, blending a carried colour gives the blend of the reported RGB")
    func blendsMeasureTheReportedRGB() {
        TerminalColors.withCurrent(Self.reported) {
            let white = Color.rgb(255, 255, 255)
            #expect(Self.ink.opacity(0.5, over: white) == Color.rgb(171, 178, 191).opacity(0.5, over: white))
            #expect(Color.red.opacity(0.5, over: Self.paper) == Color.red.opacity(0.5, over: .rgb(40, 44, 52)))
            #expect(
                Self.ink.mix(with: Self.paper, by: 0.3)
                    == Color.rgb(171, 178, 191).mix(with: .rgb(40, 44, 52), by: 0.3))
        }
    }

    @Test("A carried colour is not equal to any RGB, nor to its twin")
    func hashableKeepsThemDistinct() {
        let reportedInk = Color.rgb(171, 178, 191)
        TerminalColors.withCurrent(Self.reported) {
            #expect(Self.ink != reportedInk, "not even to the RGB it measures as")
            #expect(Self.paper != Color.rgb(40, 44, 52))
            #expect(Self.ink != Self.paper)
            #expect(Set([Self.ink, Self.paper, reportedInk]).count == 3)
        }
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

    /// Dropping the payloads leaves `.rgb`'s three bytes as the largest, so
    /// `Color` keeps its five bytes and no padding. `ColourAlphaStorageTests`
    /// explains why padding matters; this repeats the pin beside the cases.
    @Test("Color stays five bytes")
    func layoutIsUnchanged() {
        #expect(MemoryLayout<Color>.size == 5, "got \(MemoryLayout<Color>.size)")
        #expect(MemoryLayout<Color>.stride == 5, "got \(MemoryLayout<Color>.stride)")
    }
}
