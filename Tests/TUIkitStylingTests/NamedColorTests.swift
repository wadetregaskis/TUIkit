//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NamedColorTests.swift
//
//  SwiftUI's fifteen named colours, and `magenta`, which SwiftUI does not have.
//
//  The values are Apple's system palette in the light appearance, measured
//  rather than guessed, so the tests pin the exact bytes: a "close enough" red
//  would make ported SwiftUI code look subtly wrong and nothing would catch it.
//  They are colours, not the terminal's slots, which are spelled
//  `Color.ansi(_:)` (ColorANSIFactoryTests).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("SwiftUI named colours")
struct NamedColorTests {

    /// One name, and the RGB it must be.
    struct Named: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        let rgb: [UInt8]
        var testDescription: String { name }
    }

    /// SwiftUI's fifteen, resolved with `Color.resolve(in:)` in the light
    /// appearance on macOS 15.7 (`white`, `black`: the same in both).
    static let swiftUI: [Named] = [
        Named(name: "black", color: .black, rgb: [0x00, 0x00, 0x00]),
        Named(name: "white", color: .white, rgb: [0xFF, 0xFF, 0xFF]),
        Named(name: "red", color: .red, rgb: [0xFF, 0x3B, 0x30]),
        Named(name: "orange", color: .orange, rgb: [0xFF, 0x95, 0x00]),
        Named(name: "yellow", color: .yellow, rgb: [0xFF, 0xCC, 0x00]),
        Named(name: "green", color: .green, rgb: [0x28, 0xCD, 0x41]),
        Named(name: "mint", color: .mint, rgb: [0x00, 0xC7, 0xBE]),
        Named(name: "teal", color: .teal, rgb: [0x59, 0xAD, 0xC4]),
        Named(name: "cyan", color: .cyan, rgb: [0x55, 0xBE, 0xF0]),
        Named(name: "blue", color: .blue, rgb: [0x00, 0x7A, 0xFF]),
        Named(name: "indigo", color: .indigo, rgb: [0x58, 0x56, 0xD6]),
        Named(name: "purple", color: .purple, rgb: [0xAF, 0x52, 0xDE]),
        Named(name: "pink", color: .pink, rgb: [0xFF, 0x2D, 0x55]),
        Named(name: "brown", color: .brown, rgb: [0xA2, 0x84, 0x5E]),
        Named(name: "gray", color: .gray, rgb: [0x8E, 0x8E, 0x93]),
    ]

    /// TUIkit's own: SwiftUI has no magenta, and a TUI app ported from ANSI
    /// habits reaches for one. Full-strength #FF00FF.
    static let magenta = Named(name: "magenta", color: .magenta, rgb: [0xFF, 0x00, 0xFF])

    static let all = swiftUI + [magenta]

    @Test("Each name is its fixed RGB, and emits it at truecolor", arguments: all)
    func bytes(_ named: Named) {
        #expect(named.color.value == .rgb(red: named.rgb[0], green: named.rgb[1], blue: named.rgb[2]))
        #expect(named.color.isOpaque)
        #expect(named.color.rgbComponents.map { [$0.red, $0.green, $0.blue] } == named.rgb)
        let channels = named.rgb.map { "\($0)" }
        #expect(named.color.foregroundCodes(depth: .truecolor) == ["38", "2"] + channels)
        #expect(named.color.backgroundCodes(depth: .truecolor) == ["48", "2"] + channels)
    }

    /// The name is a colour, not a slot: nothing a terminal profile keeps
    /// repaints it, and bold does not brighten it above sixteen colours.
    @Test("A named colour is not terminal-defined", arguments: all)
    func notTerminalDefined(_ named: Named) {
        #expect(!named.color.isTerminalDefined)
        #expect(!ANSIColor.allCases.map(Color.ansi).contains(named.color))
    }

    @Test("Red is Apple's red, not the terminal's")
    func redIsApples() {
        #expect(Color.red.foregroundCodes(depth: .truecolor) == ["38", "2", "255", "59", "48"])
        #expect(Color.red != .ansi(.red))
    }

    /// At sixteen colours a named colour becomes the nearest slot by xterm's
    /// table, which for red, blue, white and magenta is the bright one.
    @Test("At sixteen colours each name lands on its nearest slot")
    func sixteenColours() {
        let expected: [(String, Color, String)] = [
            ("black", .black, "30"), ("red", .red, "91"), ("green", .green, "32"),
            ("yellow", .yellow, "33"), ("blue", .blue, "94"), ("cyan", .cyan, "36"),
            ("white", .white, "97"), ("magenta", .magenta, "95"),
        ]
        for (name, color, code) in expected {
            #expect(color.foregroundCodes(depth: .basic16) == [code], "\(name)")
        }
    }

    @Test("clear is black at zero opacity, as in SwiftUI")
    func clearIsTransparentBlack() {
        #expect(Color.clear == Color.black.opacity(0))
    }

    /// The deliberate divergence, pinned so nobody "fixes" it later: SwiftUI's
    /// orange is Apple's, the picker's Named-colours tab lists CSS's, and the
    /// two are different colours that share a word.
    @Test("SwiftUI's orange is not the CSS orange")
    func notCSS() {
        #expect(Color.orange.rgbComponents?.green == 0x95, "Apple's #FF9500")
        #expect(Color.orange.rgbComponents?.green != 0xA5, "not CSS's #FFA500")
    }

    /// Every named colour has to survive the trip down to a 16-colour terminal,
    /// because that is where a wrong one is least recoverable. Downsampling
    /// LANDS on the ANSI set — so doing it twice changes nothing, which is the
    /// property that says it really landed rather than merely moved.
    @Test("each downsamples onto the ANSI set and stays there", arguments: all)
    func downsamples(_ named: Named) {
        let once = named.color.downsampledToANSI16()
        #expect(once.isTerminalDefined)
        #expect(once.downsampledToANSI16() == once, "downsampling is idempotent once it has landed")
    }

    @Test("distinct names are distinct colours")
    func allDistinct() {
        #expect(Set(Self.all.map(\.color)).count == Self.all.count)
    }
}
