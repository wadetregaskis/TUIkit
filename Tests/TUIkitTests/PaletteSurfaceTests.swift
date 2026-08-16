//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PaletteSurfaceTests.swift
//
//  A "subtle lift above the background" that collapses to the background is not
//  subtle, it is absent — and it fails silently, per palette, on exactly the
//  controls whose whole affordance is that surface.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@Suite("Palette surfaces")
struct PaletteSurfaceTests {

    /// Every palette the app can actually be in.
    private var palettes: [any Palette] { PaletteRegistry.all }

    @Test("No built-in palette's lifted surface is its own page colour")
    func liftIsNeverThePage() {
        // `appHeaderBackground` defaults to `background`, so a palette that
        // never overrode it handed every surface caller the page colour: a
        // TextField drew a background identical to what was already behind it,
        // and a tab island had no island. Four of the sixteen were in that
        // state — Green (the default), Novel, Red Sands and Solid Colors.
        for palette in palettes {
            let page = palette.background.resolve(with: palette).rgbComponents
            let lift = palette.liftedBackground.resolve(with: palette).rgbComponents
            #expect(page != nil && lift != nil, "\(palette.id): unresolved colours")
            #expect(lift! != page!, "\(palette.id): the lift collapsed onto the page")
        }
    }

    @Test("A field is visible against the page on every palette")
    func fieldsAreVisible() {
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            let field = palette.fieldBackground.resolve(with: palette)
            #expect(field != page, "\(palette.id): the field surface is the page colour")
        }
    }

    @Test("A palette whose stated tone is VISIBLY distinct keeps it")
    func statedToneWins() {
        // The derivation is a FALLBACK. A palette with a real opinion about its
        // chrome tone must still drive the surfaces, or the ten Terminal.app
        // recreations would stop looking like Terminal.app.
        //
        // "Visibly" is doing work: four palettes state a tone a hair off the
        // page that collapses onto one 256-cube entry, and honouring those was
        // the bug. The rule is the same either way — keep what the palette said
        // when it can be seen — so the test asks the question the same way the
        // implementation does.
        for palette in palettes {
            let page = palette.background.resolve(with: palette).downsampledToPalette256()
            let header = palette.appHeaderBackground.resolve(with: palette)
            guard header.downsampledToPalette256() != page else { continue }
            #expect(
                palette.liftedBackground.resolve(with: palette) == header,
                "\(palette.id): a visible appHeaderBackground was overridden by the fallback")
        }
    }

    @Test("The lift survives the 256-colour cube")
    func liftSurvivesQuantisation() {
        // The step has to be big enough that downsampling does not round it
        // back onto the background — on a 256-colour terminal an invisible
        // lift is exactly as useless as no lift, and that is the terminal
        // least able to spare the affordance.
        for palette in palettes {
            let page = palette.background.resolve(with: palette).downsampledToPalette256()
            let lift = palette.liftedBackground.resolve(with: palette).downsampledToPalette256()
            #expect(lift != page, "\(palette.id): the lift quantises onto the page")
        }
    }
}
