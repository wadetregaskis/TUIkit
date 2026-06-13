//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PaletteRegistryTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Palette Registry Tests")
struct PaletteRegistryTests {

    @Test("Registry contains all predefined palettes")
    func registryCount() {
        // 6 phosphor presets + 10 Terminal.app profiles = 16.
        #expect(PaletteRegistry.phosphorPresets.count == 6)
        #expect(PaletteRegistry.terminalProfiles.count == 10)
        #expect(PaletteRegistry.all.count == 16)
    }

    @Test("Registry cycling order follows color spectrum")
    func registryCyclingOrder() {
        // Phosphor presets lead the cycle, in spectrum order.
        #expect(PaletteRegistry.all[0].id == "green")
        #expect(PaletteRegistry.all[1].id == "amber")
        #expect(PaletteRegistry.all[2].id == "red")
        #expect(PaletteRegistry.all[3].id == "violet")
        #expect(PaletteRegistry.all[4].id == "blue")
        #expect(PaletteRegistry.all[5].id == "white")
        // Terminal.app profiles follow.
        #expect(PaletteRegistry.all[6].id == "terminal.basic")
    }

    @Test("Registry finds palette by ID")
    func findById() {
        let palette = PaletteRegistry.palette(withId: "amber")
        #expect(palette != nil)
        #expect(palette?.name == "Amber")
    }

    @Test("Registry returns nil for unknown ID")
    func unknownId() {
        let palette = PaletteRegistry.palette(withId: "nonexistent")
        #expect(palette == nil)
    }

    @Test("Registry finds palette by name")
    func findByName() {
        let palette = PaletteRegistry.palette(withName: "Red")
        #expect(palette != nil)
        #expect(palette?.id == "red")
    }

    @Test("Registry returns nil for unknown name")
    func unknownName() {
        let palette = PaletteRegistry.palette(withName: "Nonexistent")
        #expect(palette == nil)
    }
}
