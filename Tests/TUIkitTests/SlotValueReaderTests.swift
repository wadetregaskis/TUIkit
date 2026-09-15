//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SlotValueReaderTests.swift
//
//  The colour editors read a colour as a value: channels, a nearest swatch, a
//  stored gradient. A terminal slot reads as the colour the terminal reported
//  for it, and as xterm's value while it has reported none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Colour editors read a terminal slot as the colour the terminal reported for it")
struct SlotValueReaderTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported
    /// them on 2026-09-14, in slot order.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots([
            rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
            rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
            rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
            rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
        ]))

    @Test("The colour panel's channels read a slot as its report, else xterm's value")
    func panelChannels() {
        func red(of colour: Color) -> Double {
            ColorPickerPanel.channelValue(of: colour, mode: .rgb, index: 0)
        }
        TerminalColors.withCurrent(.unknown) {
            #expect(red(of: .ansi(.red)) == 205)
            #expect(red(of: .palette(9)) == 255)
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(red(of: .ansi(.red)) == 153)
            #expect(red(of: .palette(9)) == 230)
            #expect(red(of: .rgb(10, 20, 30)) == 10, "an RGB colour is its own channels")
        }
    }

    /// (220, 0, 0) lies nearer xterm's red (205) than its bright red (255), and
    /// nearer Apple Terminal's bright red (230) than its red (153).
    @Test("The nearest swatch measures slot swatches as their report, else xterm's value")
    func nearestSwatch() {
        let entries: [Color] = [.ansi(.red), .ansi(.brightRed)]
        let palette = SystemPalette(.green)
        TerminalColors.withCurrent(.unknown) {
            #expect(_SwatchGridCore.nearestIndex(of: .rgb(220, 0, 0), in: entries, palette: palette) == 0)
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(_SwatchGridCore.nearestIndex(of: .rgb(220, 0, 0), in: entries, palette: palette) == 1)
        }
    }

    @Test("A remembered gradient writes a slot stop as its report, else xterm's value")
    func rememberedGradient() {
        let gradient = Gradient(stops: [
            .init(color: .ansi(.red), location: 0),
            .init(color: .rgb(0, 0, 255), location: 1),
        ])
        TerminalColors.withCurrent(.unknown) {
            #expect(GradientEditorPanel.encodeRecents([gradient]) == "CD0000@0.000,0000FF@1.000")
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(GradientEditorPanel.encodeRecents([gradient]) == "990000@0.000,0000FF@1.000")
        }
    }
}
