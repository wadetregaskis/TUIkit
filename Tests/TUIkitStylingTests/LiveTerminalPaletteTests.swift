//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveTerminalPaletteTests.swift
//
//  The one shipped palette that names no colour of its own: its grounds are `.clear`,
//  its text tiers are `Color.default`, and its accent, status roles and border are the
//  terminal's own sixteen slots. So what it draws is whatever the user's terminal
//  profile paints, and until the terminal reports those colours there is nothing about
//  it to measure. What the environment then STORES — the grounded palette a view
//  actually draws with — is pinned in `LiveTerminalPaletteRenderTests`, which is where
//  grounding lives.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("The palette whose colours the terminal decides")
struct LiveTerminalPaletteTests {

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

    /// Apple Terminal "Basic" as it reports itself: black on white, and its sixteen.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots(appleBasic))

    /// The palette as the registry hands it out.
    private func live() throws -> any Palette {
        try #require(
            PaletteRegistry.palette(withId: "terminal.live"),
            "the registry has no palette that follows the terminal's own colours")
    }

    // MARK: - What it states

    @Test("Its grounds are the terminal's page and its text the terminal's foreground")
    func groundsAndTextAreTheTerminals() throws {
        let palette = try live()
        // `.clear` rather than `Color.default`: a ground at alpha 0 IS the terminal's
        // page, whatever colour that is, and grounding spends it there — where
        // `Color.default` as a root would be re-spelled to the same thing anyway.
        #expect(palette.background == .clear)
        #expect(palette.statusBarBackground == .clear)
        #expect(palette.appHeaderBackground == .clear)
        // The modal wash is not a root — it keeps its alpha over the page behind it —
        // so it is stated as the terminal's own colour rather than as a clear ground.
        #expect(palette.overlayBackground == .default)
        #expect(palette.foreground == .default)
        // The three dimmer tiers, which grounding spends over the page it grounded on:
        // plain 39 while the terminal has said nothing, a real dimming once it has.
        #expect(palette.foregroundSecondary == Color.default.opacity(0.75))
        #expect(palette.foregroundTertiary == Color.default.opacity(0.55))
        #expect(palette.foregroundQuaternary == Color.default.opacity(0.38))
    }

    @Test("The accent, the status roles and the border are the terminal's slots")
    func accentAndStatusRolesAreSlots() throws {
        let palette = try live()
        #expect(palette.accent == .ansi(.blue))
        #expect(palette.success == .ansi(.green))
        #expect(palette.warning == .ansi(.yellow))
        #expect(palette.error == .ansi(.red))
        #expect(palette.info == .ansi(.cyan))
        #expect(palette.border == .ansi(.brightBlack))
        // Not stated, so `Palette`'s own default: the accent.
        #expect(palette.cursorColor == palette.accent)
    }

    /// Every role is a colour the terminal decides. The grounds are the one spelling
    /// that is not `isTerminalDefined` — `.clear` is black at alpha 0 — and grounding
    /// turns each into `.terminalBackground`, which is (see the render suite).
    @Test("Nothing it states is a colour of its own")
    func nothingStatedIsAColourOfItsOwn() throws {
        let palette = try live()
        let roles: [(String, Color)] = [
            ("overlayBackground", palette.overlayBackground),
            ("foreground", palette.foreground),
            ("foregroundSecondary", palette.foregroundSecondary),
            ("foregroundTertiary", palette.foregroundTertiary),
            ("foregroundQuaternary", palette.foregroundQuaternary),
            ("accent", palette.accent), ("success", palette.success),
            ("warning", palette.warning), ("error", palette.error), ("info", palette.info),
            ("border", palette.border), ("cursorColor", palette.cursorColor),
        ]
        for (role, colour) in roles {
            #expect(colour.isTerminalDefined, "\(role) is \(colour)")
        }
        for (role, ground) in [
            ("background", palette.background), ("statusBarBackground", palette.statusBarBackground),
            ("appHeaderBackground", palette.appHeaderBackground),
        ] {
            #expect(ground.alpha == 0, "\(role) is \(ground), not a ground the terminal keeps")
        }
    }

    // MARK: - What it emits

    /// A slot is emitted as a slot at every depth, and the terminal's own foreground as
    /// 39 — reported or not. The report says what a slot PAINTS; re-spelling it as that
    /// RGB would stop following the user's profile the moment they changed it.
    @Test("Its slots emit slots and its ink 39, at every depth, reported or not")
    func slotsAndDefaultsEmitAsThemselves() throws {
        let palette = try live()
        for terminal in [TerminalColors.unknown, Self.appleTerminal] {
            TerminalColors.withCurrent(terminal) {
                for depth in [ColorDepth.truecolor, .palette256, .basic16] {
                    #expect(palette.accent.foregroundCodes(depth: depth) == ["34"], "\(depth)")
                    #expect(palette.success.foregroundCodes(depth: depth) == ["32"], "\(depth)")
                    #expect(palette.warning.foregroundCodes(depth: depth) == ["33"], "\(depth)")
                    #expect(palette.error.foregroundCodes(depth: depth) == ["31"], "\(depth)")
                    #expect(palette.info.foregroundCodes(depth: depth) == ["36"], "\(depth)")
                    #expect(palette.border.foregroundCodes(depth: depth) == ["90"], "\(depth)")
                    #expect(palette.foreground.foregroundCodes(depth: depth) == ["39"], "\(depth)")
                    #expect(palette.overlayBackground.backgroundCodes(depth: depth) == ["49"], "\(depth)")
                }
            }
        }
    }

    // MARK: - Measuring it

    @Test("While the terminal has said nothing, none of its colours can be measured")
    func nothingMeasuresWhileUnreported() throws {
        let palette = try live()
        TerminalColors.withCurrent(.unknown) {
            for (role, colour) in [
                ("foreground", palette.foreground), ("accent", palette.accent),
                ("success", palette.success), ("warning", palette.warning),
                ("error", palette.error), ("info", palette.info),
                ("border", palette.border), ("overlayBackground", palette.overlayBackground),
            ] {
                #expect(colour.rgbComponents == nil, "\(role) measured as \(colour)")
            }
            // So no tint of the accent over the page can be checked for a visible step:
            // the face rests where it is and a hover shows nothing (Opacity §82).
            #expect(!palette.accentTintIsMeasurable)
            #expect(palette.hoveredControlFace == palette.restingControlFace)
        }
    }

    /// A reported slot measures as what the TERMINAL paints, not as xterm's table: on
    /// Apple Terminal "Basic" fifteen of the sixteen differ from it.
    @Test("Once the terminal reports its colours, each of them measures as reported")
    func reportedSlotsMeasureAsReported() throws {
        let palette = try live()
        try TerminalColors.withCurrent(Self.appleTerminal) {
            let accent = try #require(palette.accent.rgbComponents)
            #expect([accent.red, accent.green, accent.blue] == [0, 0, 179])
            let error = try #require(palette.error.rgbComponents)
            #expect([error.red, error.green, error.blue] == [153, 0, 0])
            let border = try #require(palette.border.rgbComponents)
            #expect([border.red, border.green, border.blue] == [102, 102, 102])
            #expect(palette.accentTintIsMeasurable)
        }
    }

    // MARK: - The registry

    @Test("The registry ends with it, and the palettes that state their colours lead")
    func registryHoldsItLast() throws {
        let palette = try live()
        let stated = PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
        #expect(PaletteRegistry.all.count == 17)
        #expect(PaletteRegistry.all.count == stated.count + 1)
        #expect(PaletteRegistry.all.last?.id == palette.id)
        #expect(PaletteRegistry.all.prefix(stated.count).map(\.id) == stated.map(\.id))
        #expect(PaletteRegistry.palette(withName: "Terminal")?.id == "terminal.live")
        // The ids stay unique across the whole registry.
        let ids = PaletteRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
