//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // "Visibly" is doing the work, and it is a size, not a yes/no: the
        // stated tones sat anywhere from ΔL* 0.5 (Man Page) to 16.6 (Homebrew),
        // and honouring the ones at the bottom of that range was the bug. The
        // rule is the same either way — keep what the palette said when it can
        // be seen — so the test asks the question the same way the
        // implementation does.
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            let header = palette.appHeaderBackground.resolve(with: palette)
            guard
                SystemPalette.isVisiblySeparate(
                    header, from: page, separation: SystemPalette.planeSeparation)
            else { continue }
            #expect(
                palette.liftedBackground.resolve(with: palette) == header,
                "\(palette.id): a visible appHeaderBackground was overridden by the fallback")
        }
    }

    @Test("Every palette's plane is a visible step off its page")
    func planesAreVisible() {
        // The tab body, the header island: a large area, so a smaller step than
        // a field's reads clearly — and a *bigger* one reads as a panel, which
        // is what a whole-page step turned every tab body into.
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            let plane = palette.liftedBackground.resolve(with: palette)
            let raw = plane.lightnessDifference(from: page)
            #expect(
                raw >= SystemPalette.planeSeparation,
                "\(palette.id): the plane is ΔL* \(String(format: "%.1f", raw)) off the page")
        }
    }

    @Test("Every palette's field is a visible step off its page")
    func surfacesAreVisible() {
        // The bug this pins, reported against Novel and true of five others: a
        // field whose background is *technically* not the page colour but sits
        // ΔL* 0.5–5.9 from it, which the eye reads as no field at all. Measured
        // in perceived lightness, not contrast ratio — a ratio flattens at both
        // ends of the range and called Man Page's invisible tone 1.01 and
        // Green's obvious one 1.57, in the wrong order.
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            let field = palette.fieldBackground.resolve(with: palette)
            let raw = field.lightnessDifference(from: page)
            #expect(
                raw >= SystemPalette.wellSeparation,
                "\(palette.id): the field is ΔL* \(String(format: "%.1f", raw)) off the page")
        }
    }

    @Test("On a 256-colour terminal the field survives the cube")
    func fieldsSurviveQuantisation() {
        // Where the cube can round a step back onto the page — the failure the
        // first version of this rule was written for. The derivation is
        // depth-aware now (a truecolor terminal gets the step it asked for; the
        // cube's coarser one is only imposed where the cube is what paints),
        // so this has to ASK for the cube rather than assume it.
        withColorDepth(.palette256) {
            for palette in palettes {
                let page = palette.background.resolve(with: palette).downsampledToPalette256()
                let field = palette.fieldBackground.resolve(with: palette)
                    .downsampledToPalette256()
                let rendered = field.lightnessDifference(from: page)
                #expect(
                    rendered >= SystemPalette.wellSeparation / 2,
                    "\(palette.id): the field quantises to ΔL* \(String(format: "%.1f", rendered))")
            }
        }
    }

    @Test("A field inside another surface steps off THAT, not off the page")
    func fieldOnASurfaceIsSeparate() {
        // A `TextField` in a `TabView`'s body asked for "a surface on the page"
        // and got the tab's own colour — the two took the same step from the
        // same place — so the field vanished into the tab it sat in.
        for palette in palettes {
            let tab = palette.liftedBackground.resolve(with: palette)
            let field = palette.fieldBackground(on: tab).resolve(with: palette)
            let gap = String(format: "%.1f", field.lightnessDifference(from: tab))
            #expect(
                SystemPalette.isVisiblySeparate(
                    field, from: tab, separation: SystemPalette.wellSeparation),
                "\(palette.id): a field on the tab surface is ΔL* \(gap) off it")
        }
    }

    @Test("The ladder only ever climbs AWAY from the page")
    func nestedSurfacesNeverReturnToThePage() {
        // The bug this pins, and it was the same one seen from the other side:
        // asking "which way is away from the text?" afresh at each rung folds
        // the ladder back on itself. A dark palette's tab body steps lighter
        // (its page has no room to go darker), and a field inside that body,
        // asking again from there, steps darker — onto the page colour exactly,
        // on ten of the sixteen. It read as a hole punched through the tab.
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            let tab = palette.liftedBackground.resolve(with: palette)
            let field = palette.fieldBackground(on: tab).resolve(with: palette)
            let tabGap = tab.lightnessDifference(from: page)
            let fieldGap = field.lightnessDifference(from: page)
            let gaps = "field ΔL* \(String(format: "%.1f", fieldGap)), "
                + "tab ΔL* \(String(format: "%.1f", tabGap))"
            #expect(fieldGap > tabGap, "\(palette.id): the ladder folded back — \(gaps)")
            #expect(
                field != page, "\(palette.id): the field came out the page colour exactly")
        }
    }

    @Test("On the page, a field is still the palette's own field colour")
    func fieldOnThePageIsUnchanged() {
        // The generalisation must not quietly re-derive the ordinary case: a
        // palette that states a chrome tone still gets it for its fields.
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            #expect(
                palette.fieldBackground(on: page).resolve(with: palette)
                    == palette.fieldBackground.resolve(with: palette),
                "\(palette.id): the page case changed")
        }
    }

    @Test("The surface keeps the page's hue")
    func surfaceKeepsTheHue() {
        // A step toward black or white desaturates as it goes: the phosphor
        // palettes' near-black pages lifted that way came out GREY, so a green
        // terminal grew grey text fields. Scaling the page's own channels keeps
        // the ratios between them, which is what "the page, lit" means.
        for palette in palettes {
            let page = palette.background.resolve(with: palette)
            guard let (red, green, blue) = page.rgbComponents,
                let (fieldRed, fieldGreen, fieldBlue) = palette.fieldBackground
                    .resolve(with: palette).rgbComponents
            else {
                Issue.record("\(palette.id): unresolved colours")
                continue
            }
            // A grey page has no hue to keep, and a black one nothing to scale.
            let pageSpread = Int(max(red, green, blue)) - Int(min(red, green, blue))
            guard pageSpread >= 4 else { continue }
            let hue = Color.rgbToHSL(red: red, green: green, blue: blue).hue
            let fieldHue = Color.rgbToHSL(red: fieldRed, green: fieldGreen, blue: fieldBlue).hue
            let drift = min(abs(hue - fieldHue), 360 - abs(hue - fieldHue))
            #expect(drift <= 10, "\(palette.id): hue drifted \(Int(drift))° from the page")
        }
    }

    @Test("The lift survives the 256-colour cube")
    func liftSurvivesQuantisation() {
        // The step has to be big enough that downsampling does not round it
        // back onto the background — on a 256-colour terminal an invisible
        // lift is exactly as useless as no lift, and that is the terminal
        // least able to spare the affordance. (``surfacesAreVisible`` measures
        // how far; this one keeps the older, blunter question in the suite,
        // because "the same cube entry" is the failure that started it.)
        withColorDepth(.palette256) {
            for palette in palettes {
                let page = palette.background.resolve(with: palette).downsampledToPalette256()
                let lift = palette.liftedBackground.resolve(with: palette)
                    .downsampledToPalette256()
                #expect(lift != page, "\(palette.id): the lift quantises onto the page")
            }
        }
    }
}
