//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NamedColorTests.swift
//
//  SwiftUI's named colours — the eight that the ANSI vocabulary does not
//  already carry.
//
//  The values are Apple's system palette, sampled from AppKit rather than
//  guessed, so the tests pin the exact bytes: a "close enough" orange would
//  make ported SwiftUI code look subtly wrong and nothing would catch it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("SwiftUI named colours")
struct NamedColorTests {

    /// Sampled from `NSColor.system*` in the light (aqua) appearance, converted
    /// to sRGB. Pinning them means a later edit cannot quietly drift.
    @Test("the eight names carry Apple's system values")
    func systemValues() {
        let expected: [(String, Color, (UInt8, UInt8, UInt8))] = [
            ("gray", .gray, (0x8E, 0x8E, 0x93)),
            ("orange", .orange, (0xFF, 0x95, 0x00)),
            ("pink", .pink, (0xFF, 0x2D, 0x55)),
            ("purple", .purple, (0xAF, 0x52, 0xDE)),
            ("brown", .brown, (0xA2, 0x84, 0x5E)),
            ("mint", .mint, (0x00, 0xC7, 0xBE)),
            ("teal", .teal, (0x59, 0xAD, 0xC4)),
            ("indigo", .indigo, (0x58, 0x56, 0xD6)),
        ]
        for (name, color, rgb) in expected {
            let components = color.rgbComponents
            #expect(components?.red == rgb.0, "\(name) red")
            #expect(components?.green == rgb.1, "\(name) green")
            #expect(components?.blue == rgb.2, "\(name) blue")
        }
    }

    /// They are true-colour values, not palette slots — which is what lets them
    /// be Apple's exact bytes, and what makes them downsample rather than
    /// follow the user's theme.
    @Test("the named colours are concrete RGB, not semantic")
    func areConcrete() {
        for color in [Color.gray, .orange, .pink, .purple, .brown, .mint, .teal, .indigo] {
            #expect(color.rgbComponents != nil, "must resolve without a palette")
        }
    }

    /// The deliberate divergence, pinned so nobody "fixes" it later: SwiftUI's
    /// orange is Apple's, the picker's Named-colours tab lists CSS's, and the
    /// two are different colours that share a word.
    @Test("SwiftUI's orange is not the CSS orange")
    func notCSS() {
        #expect(Color.orange.rgbComponents?.green == 0x95, "Apple's #FF9500")
        #expect(Color.orange.rgbComponents?.green != 0xA5, "not CSS's #FFA500")
    }

    /// The ANSI names stay ANSI. Re-pointing `.red` at Apple's `#FF3B30` would
    /// gain a nominal match and break every themed app on screen, because in a
    /// terminal those names mean the slots a theme defines — they resolve to the
    /// standard xterm values, not to Apple's palette.
    @Test("the ANSI names are untouched")
    func ansiNamesUnchanged() {
        // xterm's red, not Apple's #FF3B30.
        #expect(Color.red.rgbComponents?.red == 205)
        #expect(Color.red.rgbComponents?.green == 0)
        #expect(Color.green.rgbComponents?.green == 205)
        #expect(Color.blue.rgbComponents?.blue == 238)
        // And none of them accidentally became a system colour.
        for color in [Color.red, .green, .blue, .yellow] {
            #expect(
                color.rgbComponents.map { [$0.red, $0.green, $0.blue] }
                    != [0xFF, 0x3B, 0x30],
                "an ANSI slot must not be Apple's system red")
        }
    }

    /// Every named colour has to survive the trip down to a 16-colour terminal,
    /// because that is where a wrong one is least recoverable. Downsampling
    /// LANDS on the ANSI set — so doing it twice changes nothing, which is the
    /// property that says it really landed rather than merely moved.
    @Test("each downsamples onto the ANSI set and stays there")
    func downsamples() {
        for color in [Color.gray, .orange, .pink, .purple, .brown, .mint, .teal, .indigo] {
            let once = color.downsampledToANSI16()
            let twice = once.downsampledToANSI16()
            #expect(
                once.rgbComponents.map { [$0.red, $0.green, $0.blue] }
                    == twice.rgbComponents.map { [$0.red, $0.green, $0.blue] },
                "downsampling is idempotent once it has landed")
        }
    }

    @Test("distinct names are distinct colours")
    func allDistinct() {
        let all: [Color] = [.gray, .orange, .pink, .purple, .brown, .mint, .teal, .indigo]
        let components = all.compactMap { $0.rgbComponents.map { [$0.red, $0.green, $0.blue] } }
        #expect(Set(components.map { "\($0)" }).count == all.count)
    }
}
