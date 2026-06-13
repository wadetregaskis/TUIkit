//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalProfilePaletteTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Terminal.app profile palettes")
struct TerminalProfilePaletteTests {

    @Test("Defining colours match the decoded Terminal.app values")
    func definingColours() {
        let homebrew = TerminalProfilePalette(.homebrew)
        #expect(homebrew.background == .rgb(0, 0, 0))
        #expect(homebrew.foreground == .rgb(40, 254, 20))
        #expect(homebrew.cursorColor == .rgb(56, 254, 39))

        let novel = TerminalProfilePalette(.novel)
        #expect(novel.background == .rgb(223, 219, 195))
        #expect(novel.foreground == .rgb(77, 47, 45))

        let basic = TerminalProfilePalette(.basic)
        #expect(basic.background == .rgb(255, 255, 255))
        #expect(basic.foreground == .rgb(0, 0, 0))

        let ocean = TerminalProfilePalette(.ocean)
        #expect(ocean.background == .rgb(43, 102, 201))
    }

    @Test("Accent is the profile's signature emphasis colour where one exists")
    func signatureAccents() {
        // Bold text colour is the signature for these.
        #expect(TerminalProfilePalette(.grass).accent == .rgb(255, 176, 59))      // amber
        #expect(TerminalProfilePalette(.homebrew).accent == .rgb(0, 249, 0))       // green
        #expect(TerminalProfilePalette(.redSands).accent == .rgb(230, 199, 43))    // gold
        #expect(TerminalProfilePalette(.novel).accent == .rgb(147, 58, 33))        // brick
        // Bold is white/black (== fg or neutral), so the selection colour wins.
        #expect(TerminalProfilePalette(.ocean).accent == .rgb(41, 134, 255))       // bright blue
        #expect(TerminalProfilePalette(.basic).accent == .rgb(164, 205, 255))      // selection blue
        #expect(TerminalProfilePalette(.silverAerogel).accent == .rgb(120, 122, 156))  // periwinkle
        // Fully monochrome: the most background-distinct candidate (white bold).
        #expect(TerminalProfilePalette(.pro).accent == .rgb(255, 255, 255))
    }

    @Test("focusBackground adopts the profile's selection colour")
    func focusBackgroundIsSelection() {
        #expect(TerminalProfilePalette(.homebrew).focusBackground == .rgb(12, 46, 238))
        #expect(TerminalProfilePalette(.grass).focusBackground == .rgb(182, 73, 38))
        #expect(TerminalProfilePalette(.redSands).focusBackground == .rgb(61, 25, 22))
        // Solid Colors ships no selection colour → a derived (still resolved) tint.
        #expect(TerminalProfilePalette(.solidColors).focusBackground.rgbComponents != nil)
    }

    @Test("Every semantic role resolves to a concrete RGB colour")
    func allRolesResolve() {
        for profile in TerminalProfilePalette.Profile.allCases {
            let palette = TerminalProfilePalette(profile)
            let roles: [(String, Color)] = [
                ("background", palette.background),
                ("statusBarBackground", palette.statusBarBackground),
                ("appHeaderBackground", palette.appHeaderBackground),
                ("overlayBackground", palette.overlayBackground),
                ("foreground", palette.foreground),
                ("foregroundSecondary", palette.foregroundSecondary),
                ("foregroundTertiary", palette.foregroundTertiary),
                ("foregroundQuaternary", palette.foregroundQuaternary),
                ("accent", palette.accent),
                ("success", palette.success),
                ("warning", palette.warning),
                ("error", palette.error),
                ("info", palette.info),
                ("border", palette.border),
                ("focusBackground", palette.focusBackground),
                ("cursorColor", palette.cursorColor),
            ]
            for (role, color) in roles {
                #expect(color.rgbComponents != nil, "\(profile.displayName).\(role) is unresolved")
            }
        }
    }

    @Test("Foreground stays readable against the background for every profile")
    func foregroundContrast() {
        func luma(_ color: Color) -> Double {
            guard let (r, g, b) = color.rgbComponents else { return 0 }
            return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        }
        for profile in TerminalProfilePalette.Profile.allCases {
            let palette = TerminalProfilePalette(profile)
            let contrast = abs(luma(palette.foreground) - luma(palette.background))
            #expect(contrast >= 60, "\(profile.displayName) foreground/background contrast \(contrast) too low")
        }
    }

    @Test("Registry exposes the phosphor presets plus the 10 Terminal profiles")
    func registry() {
        #expect(PaletteRegistry.phosphorPresets.count == 6)
        #expect(PaletteRegistry.terminalProfiles.count == 10)
        #expect(PaletteRegistry.all.count == 16)
        // Phosphor presets come first, then the Terminal profiles.
        #expect(PaletteRegistry.all.prefix(6).allSatisfy { !$0.id.hasPrefix("terminal.") })
        #expect(PaletteRegistry.all.suffix(10).allSatisfy { $0.id.hasPrefix("terminal.") })

        // IDs are unique and names match the Terminal display names.
        let ids = PaletteRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(PaletteRegistry.palette(withName: "Man Page")?.id == "terminal.manPage")
        #expect(PaletteRegistry.palette(withName: "Homebrew")?.id == "terminal.homebrew")
    }
}
