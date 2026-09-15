//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSISlotPinTests.swift
//
//  The terminal's sixteen colour slots and `Color.default`, pinned everywhere
//  this module reads one: the codes at every depth, the RGB each measures as,
//  downsampling, the nearest of the sixteen to each of xterm's own triples, and
//  which of them count as grey. Changing how a slot is stored must leave every
//  one of these alone. The image module's spellings are pinned in
//  ANSISlotPaletteEntryTests, and SGRState's and the colour rewrite's in
//  ANSISlotSGRStateTests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("The sixteen terminal slots and the default, as they measure and emit")
struct ANSISlotPinTests {

    struct Slot: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        /// The slot's number: its 256-colour index and its OSC 4 index.
        let index: UInt8
        let foreground: String
        let background: String
        /// xterm's conventional value for the slot, which is what it measures as.
        let xterm: [UInt8]

        var testDescription: String { name }
    }

    static let slots: [Slot] = [
        Slot(name: "black", color: .ansi(.black), index: 0, foreground: "30", background: "40", xterm: [0, 0, 0]),
        Slot(name: "red", color: .ansi(.red), index: 1, foreground: "31", background: "41", xterm: [205, 0, 0]),
        Slot(name: "green", color: .ansi(.green), index: 2, foreground: "32", background: "42", xterm: [0, 205, 0]),
        Slot(name: "yellow", color: .ansi(.yellow), index: 3, foreground: "33", background: "43", xterm: [205, 205, 0]),
        Slot(name: "blue", color: .ansi(.blue), index: 4, foreground: "34", background: "44", xterm: [0, 0, 238]),
        Slot(name: "magenta", color: .ansi(.magenta), index: 5, foreground: "35", background: "45", xterm: [205, 0, 205]),
        Slot(name: "cyan", color: .ansi(.cyan), index: 6, foreground: "36", background: "46", xterm: [0, 205, 205]),
        Slot(name: "white", color: .ansi(.white), index: 7, foreground: "37", background: "47", xterm: [229, 229, 229]),
        Slot(
            name: "brightBlack", color: .ansi(.brightBlack), index: 8, foreground: "90", background: "100",
            xterm: [127, 127, 127]),
        Slot(name: "brightRed", color: .ansi(.brightRed), index: 9, foreground: "91", background: "101", xterm: [255, 0, 0]),
        Slot(
            name: "brightGreen", color: .ansi(.brightGreen), index: 10, foreground: "92", background: "102",
            xterm: [0, 255, 0]),
        Slot(
            name: "brightYellow", color: .ansi(.brightYellow), index: 11, foreground: "93", background: "103",
            xterm: [255, 255, 0]),
        Slot(
            name: "brightBlue", color: .ansi(.brightBlue), index: 12, foreground: "94", background: "104",
            xterm: [92, 92, 255]),
        Slot(
            name: "brightMagenta", color: .ansi(.brightMagenta), index: 13, foreground: "95", background: "105",
            xterm: [255, 0, 255]),
        Slot(
            name: "brightCyan", color: .ansi(.brightCyan), index: 14, foreground: "96", background: "106",
            xterm: [0, 255, 255]),
        Slot(
            name: "brightWhite", color: .ansi(.brightWhite), index: 15, foreground: "97", background: "107",
            xterm: [255, 255, 255]),
    ]

    private static let colourDepths: [ColorDepth] = [.truecolor, .palette256, .basic16]

    @Test("A slot is its own code at every depth that has colour, and nothing at noColor", arguments: slots)
    func slotCodes(_ slot: Slot) {
        for depth in Self.colourDepths {
            #expect(slot.color.foregroundCodes(depth: depth) == [slot.foreground], "fg @\(depth)")
            #expect(slot.color.backgroundCodes(depth: depth) == [slot.background], "bg @\(depth)")
            #expect(slot.color.backgroundEscape(depth: depth) == "\u{1B}[\(slot.background)m", "escape @\(depth)")
        }
        #expect(slot.color.foregroundCodes(depth: .noColor).isEmpty)
        #expect(slot.color.backgroundCodes(depth: .noColor).isEmpty)
        #expect(slot.color.backgroundEscape(depth: .noColor).isEmpty)
    }

    /// Spelled by index, a slot keeps its 256-colour form where the terminal has
    /// one, and becomes the named slot at sixteen colours.
    @Test("A 256-colour index below 16 is the same slot at sixteen colours", arguments: slots)
    func indexCodes(_ slot: Slot) {
        let indexed = Color.palette(slot.index)
        for depth in [ColorDepth.truecolor, .palette256] {
            #expect(indexed.foregroundCodes(depth: depth) == ["38", "5", "\(slot.index)"], "fg @\(depth)")
            #expect(indexed.backgroundCodes(depth: depth) == ["48", "5", "\(slot.index)"], "bg @\(depth)")
        }
        #expect(indexed.foregroundCodes(depth: .basic16) == [slot.foreground])
        #expect(indexed.backgroundCodes(depth: .basic16) == [slot.background])
    }

    @Test("The default is 39 or 49 at every depth that has colour, and nothing at noColor")
    func defaultCodes() {
        for depth in Self.colourDepths {
            #expect(Color.default.foregroundCodes(depth: depth) == ["39"], "fg @\(depth)")
            #expect(Color.default.backgroundCodes(depth: depth) == ["49"], "bg @\(depth)")
            #expect(Color.default.backgroundEscape(depth: depth) == "\u{1B}[49m", "escape @\(depth)")
        }
        #expect(Color.default.foregroundCodes(depth: .noColor).isEmpty)
        #expect(Color.default.backgroundCodes(depth: .noColor).isEmpty)
    }

    /// A slot the terminal has not reported measures as nothing (UnreportedANSISlotTests
    /// pins what it measures as once reported). xterm's value is still the table, and
    /// what a value reader gets.
    @Test("An unreported slot measures as nothing, and reads as xterm's value, by name and by index",
        arguments: slots)
    func unreportedSlotReadsAsXterm(_ slot: Slot) {
        TerminalColors.withCurrent(.unknown) {
            #expect(slot.color.rgbComponents == nil)
            #expect(Color.palette(slot.index).rgbComponents == nil)
            #expect(slot.color.estimatedRGB.map { [$0.red, $0.green, $0.blue] } == slot.xterm)
            #expect(Color.palette(slot.index).estimatedRGB.map { [$0.red, $0.green, $0.blue] } == slot.xterm)
        }
        let table = Color.palette256ToRGB(slot.index)
        #expect([table.red, table.green, table.blue] == slot.xterm)
    }

    /// The default is whatever the terminal paints in the slot it is drawn in:
    /// its foreground as ink and its background as a fill. No single RGB is both,
    /// so it measures as nothing, and that stays true once the terminal has
    /// reported both colours. It is not white, and not any other guess.
    @Test("The default measures as nothing, whatever the terminal reported, and is still not white")
    func defaultIsUnmeasurable() {
        let reported = TerminalColors(
            foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
            background: TerminalColors.RGB(red: 40, green: 44, blue: 52))
        for (name, colours) in [("unknown", TerminalColors.unknown), ("reported", reported)] {
            TerminalColors.withCurrent(colours) {
                #expect(Color.default.rgbComponents == nil, "\(name)")
                #expect(Color.default.relativeLuminance == nil, "\(name)")
                #expect(Color.default.perceivedLightness == nil, "\(name)")
                #expect(!Color.default.isAchromatic, "\(name)")
            }
        }
        #expect(Color.default != Color.ansi(.white))
    }

    @Test("A slot downsamples to itself at every depth, alpha included", arguments: slots)
    func slotDownsamplesToItself(_ slot: Slot) {
        var faded = slot.color
        faded.alpha = 128
        for colour in [slot.color, faded] {
            #expect(colour.downsampledToPalette256() == colour, "to 256, alpha \(colour.alpha)")
            #expect(colour.downsampledToANSI16() == colour, "to 16, alpha \(colour.alpha)")
            for depth in Self.colourDepths + [.noColor] {
                #expect(colour.downsampled(to: depth) == colour, "to \(depth), alpha \(colour.alpha)")
            }
        }
    }

    @Test("A 256-colour index below 16 downsamples to its named slot at sixteen colours", arguments: slots)
    func indexDownsamplesToItsSlot(_ slot: Slot) {
        let indexed = Color.palette(slot.index)
        #expect(indexed.downsampledToPalette256() == indexed)
        #expect(indexed.downsampledToANSI16() == slot.color)
        var faded = indexed
        faded.alpha = 128
        var fadedSlot = slot.color
        fadedSlot.alpha = 128
        #expect(faded.downsampledToANSI16() == fadedSlot, "carrying its alpha")
    }

    @Test("The default downsamples to itself")
    func defaultDownsamplesToItself() {
        #expect(Color.default.downsampledToPalette256() == Color.default)
        #expect(Color.default.downsampledToANSI16() == Color.default)
        for depth in Self.colourDepths + [.noColor] {
            #expect(Color.default.downsampled(to: depth) == Color.default, "to \(depth)")
        }
    }

    /// The sixteen-colour quantiser's table is xterm's, in slot order, so each of
    /// xterm's own triples lands on its own slot. The sixteen triples are all
    /// different, so no tie decides it.
    @Test("An RGB equal to a slot's xterm value quantises to that slot at sixteen colours", arguments: slots)
    func xtermTripleQuantisesToItsSlot(_ slot: Slot) {
        let triple = Color.rgb(slot.xterm[0], slot.xterm[1], slot.xterm[2])
        #expect(triple.downsampledToANSI16() == slot.color)
        #expect(triple.foregroundCodes(depth: .basic16) == [slot.foreground])
        #expect(triple.backgroundCodes(depth: .basic16) == [slot.background])
    }

    /// Black and white and their bright twins are the greys among the sixteen,
    /// decided by which slot it is, and the same whether named or indexed.
    @Test("Exactly slots 0, 7, 8 and 15 are achromatic, by name and by index", arguments: slots)
    func achromaticSlots(_ slot: Slot) {
        let grey = [0, 7, 8, 15].contains(slot.index)
        #expect(slot.color.isAchromatic == grey)
        #expect(Color.palette(slot.index).isAchromatic == grey)
        for depth in Self.colourDepths + [.noColor] {
            #expect(slot.color.hasHue(depth: depth) == !grey, "@\(depth)")
        }
    }

    @Test("The default is not achromatic")
    func defaultIsNotAchromatic() {
        #expect(!Color.default.isAchromatic)
    }

    @Test("Every slot and the default are terminal-defined, and are seventeen different colours")
    func terminalDefinedAndDistinct() {
        for slot in Self.slots {
            #expect(slot.color.isTerminalDefined, "\(slot.name)")
            #expect(Color.palette(slot.index).isTerminalDefined, "palette \(slot.index)")
            #expect(Color.palette(slot.index) != slot.color, "an index and a name are two spellings")
        }
        #expect(Color.default.isTerminalDefined)
        #expect(Set(Self.slots.map(\.color) + [Color.default]).count == 17)
        #expect(Self.slots.map(\.index) == Array(0...15))
    }
}
