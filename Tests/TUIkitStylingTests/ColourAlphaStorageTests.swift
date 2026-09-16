//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColourAlphaStorageTests.swift
//
//  `Color.alpha` is stored, so every function that derives a Color FROM a Color
//  has to carry it. This is that check written as a table rather than as one test
//  per function, so a derivation added later fails here instead of silently
//  dropping the alpha.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// A palette to resolve semantic colours against.
private struct AlphaTestPalette: Palette {
    let id = "alpha-test"
    let name = "Alpha test"
    let background = Color.black
    let foreground = Color.white
    let accent = Color.cyan
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.gray
}

/// A palette whose own slots are faded — the second tier of
/// `Documentation/Opacity as composition.md` §16.1. `Palette` is a public protocol
/// of plain `var …: Color { get }` members and nothing normalises what a
/// conformance returns, so this is a thing an app can write.
private struct FadedSlotPalette: Palette {
    let id = "faded-slot"
    let name = "Faded slot"
    let background = Color.black
    let foreground = Color.white
    var accent = Color.cyan.opacity(0.5)
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.gray
}

@Suite("Colour alpha storage")
struct ColourAlphaStorageTests {

    /// Padding-free, because `viewValueHash` hashes the raw bytes of every view
    /// struct and views hold `Color`s. A `Double` alpha would align the struct to
    /// eight and introduce padding, whose contents are undefined — making the
    /// render memo's key non-deterministic for two identical views.
    @Test("Color stays padding-free")
    func layoutHasNoPadding() {
        #expect(MemoryLayout<Color>.size == 5, "got \(MemoryLayout<Color>.size)")
        #expect(
            MemoryLayout<Color>.size == MemoryLayout<Color>.stride,
            "stride \(MemoryLayout<Color>.stride) means padding")
    }

    /// A colour at `alpha`, until the public `opacity:` spellings land.
    private func translucent(_ base: Color = .rgb(200, 100, 50), _ alpha: UInt8 = 128) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    @Test("A fresh colour is opaque")
    func freshColoursAreOpaque() {
        #expect(Color.red.isOpaque)
        #expect(Color.rgb(1, 2, 3).isOpaque)
        #expect(Color.hsl(180, 50, 50).isOpaque)
        #expect(Color.palette256(42).isOpaque)
    }

    /// **The table.** Every `Color` → `Color` derivation in the styling module,
    /// asked to carry a non-opaque alpha through.
    ///
    /// Written as one test over a list rather than one test per function on
    /// purpose: the failure mode this guards against is a NEW derivation that
    /// forgets, and a per-function suite cannot fail for a function nobody added
    /// to it. There is no one place a derivation lives, so this names a shape
    /// rather than a mark: a colour rebuilt from `self`'s channels through a
    /// factory (`.rgb`, `.hsl`, `.palette`) starts at 255, and must end in
    /// `carryingAlpha(of:)` and get a row here. (This comment used to name a
    /// `// MARK: - Color Derivations` that never existed, which is how
    /// `lighter(by:)` and `darker(by:)` went without one.)
    @Test("Every derivation carries the alpha")
    func derivationsCarryAlpha() {
        let faded = translucent()
        #expect(faded.alpha == 128, "the fixture: got \(faded.alpha)")

        let derivations: [(name: String, derived: Color)] = [
            ("downsampledToPalette256", faded.downsampledToPalette256()),
            ("downsampledToANSI16", faded.downsampledToANSI16()),
            ("downsampled(to: .palette256)", faded.downsampled(to: .palette256)),
            ("downsampled(to: .basic16)", faded.downsampled(to: .basic16)),
            ("lerp(_:_:phase:)", Color.lerp(faded, faded, phase: 0.5)),
            ("mix(with:by:)", faded.mix(with: faded, by: 0.5)),
            ("ensuringContrast", faded.ensuringContrast(atLeast: 3, against: .black)),
            // A lightness step, rebuilt through `Color.hsl`, which builds at 255. The
            // base must be concrete: a semantic one leaves `adjusted(by:)` by its guard
            // as `self`, and would pass with the carry deleted.
            ("lighter(by:)", faded.lighter(by: 0.2)),
            ("darker(by:)", faded.darker(by: 0.2)),
        ]
        for (name, derived) in derivations {
            #expect(derived.alpha == 128, "\(name) dropped the alpha: got \(derived.alpha)")
        }
    }

    /// **The derivation the table above cannot hold**, because it returns
    /// `[Color]` rather than `Color` — and the one that was actually broken.
    ///
    /// `quantisedRamp` repairs a ramp whose 256-colour downsample is not monotonic
    /// by retiring a palette entry and re-deriving every sample that had chosen it.
    /// That re-derivation built a bare `.palette256(...)`, so the entries the repair
    /// touched came back OPAQUE while their untouched neighbours kept their alpha.
    /// One translucent gradient therefore rendered differently per entry at
    /// 256-colour depth and correctly at truecolor, with no diagnostic — an opaque
    /// colour never trips the emitter's assertion.
    ///
    /// The fixture is not arbitrary and must not be tidied. It was found by
    /// brute-forcing ramps until one actually reached the repair: a near-black
    /// ramp of 16 entries, where the 240-entry palette is sparse enough to
    /// quantise non-monotonically. The obvious-looking fixture (a mid-tone ramp
    /// across the cube) never reaches the repair at all, so the test passed with
    /// the fix removed — verified, which is the only reason this comment exists.
    ///
    /// It loses TWO of sixteen entries rather than all of them, which is the
    /// diagnostic shape: a whole-ramp loss could be any bug, while a partial one
    /// is specifically the repair.
    @Test("A quantised ramp carries alpha through the monotonicity repair")
    func quantisedRampCarriesAlpha() {
        var from = Color.rgb(0, 0, 0)
        var to = Color.rgb(24, 12, 24)
        from.alpha = 128
        to.alpha = 128
        let ramp = Color.quantisedRamp(
            Gradient(colors: [from, to]), count: 16, depth: .palette256)
        #expect(ramp.count == 16, "the fixture produced a ramp: \(ramp.count)")
        let opaque = ramp.enumerated().filter { $0.element.alpha != 128 }
        #expect(
            opaque.isEmpty,
            "entries \(opaque.map(\.offset)) came back at \(opaque.map(\.element.alpha))")
    }

    /// **`opacity(_:)` multiplies, and the case that proves it must.**
    ///
    /// Measured against real SwiftUI on macOS, resolving through
    /// `Color.resolve(in:)`:
    ///
    /// ```
    /// Color.red.opacity(0.5)                 alpha=0.5
    /// Color.red.opacity(0.5).opacity(0.5)    alpha=0.25
    /// Color.red.opacity(0.25).opacity(0.5)   alpha=0.125
    /// Color.clear.opacity(1.0)               alpha=0.0
    /// ```
    ///
    /// The last line is the one that matters rather than merely differs. Replacing
    /// the alpha makes `Color.clear.opacity(1)` fully opaque — which turns `.clear`
    /// into the solid black its underlying value happens to be, in code that reads
    /// like a no-op. Nothing times anything is nothing.
    ///
    /// Exact equality is not available: alpha is stored as a `UInt8`, so 0.5 is
    /// 128 and two halvings land on 64 rather than on 63.75. The tolerance is one
    /// channel unit, not a fudge factor.
    @Test("opacity(_:) multiplies the alpha rather than replacing it")
    func opacityMultiplies() {
        #expect(Color.red.opacity(0.5).alpha == 128, "got \(Color.red.opacity(0.5).alpha)")
        #expect(
            Color.red.opacity(0.5).opacity(0.5).alpha == 64,
            "0.5 x 0.5: got \(Color.red.opacity(0.5).opacity(0.5).alpha)")
        #expect(
            Color.red.opacity(0.25).opacity(0.5).alpha == 32,
            "0.25 x 0.5: got \(Color.red.opacity(0.25).opacity(0.5).alpha)")
        // A factor of 1 is the identity in both directions.
        #expect(Color.red.opacity(1).alpha == 255, "an opaque colour stays opaque")
        #expect(
            Color.red.opacity(0.5).opacity(1).alpha == 128,
            "and a translucent one is not promoted")
        // The clincher.
        #expect(
            Color.clear.opacity(1).alpha == 0,
            "clear stays clear: got \(Color.clear.opacity(1).alpha)")
        #expect(Color.clear.opacity(0.5).alpha == 0, "and at any factor")
    }

    /// Out-of-range and NaN factors, which a caller is allowed to hand this and
    /// which `UInt8(_: Double)` would trap on.
    @Test("An out-of-range or NaN opacity is clamped rather than trapping")
    func opacityClamps() {
        #expect(Color.red.opacity(2).alpha == 255, "above the range")
        #expect(Color.red.opacity(-1).alpha == 0, "below it")
        #expect(Color.red.opacity(.nan).alpha == 0, "and a NaN reads as nothing")
    }

    /// **A fully transparent colour still paints, on an unmigrated path** — and
    /// this test exists to keep that written down rather than to bless it.
    ///
    /// The emitters deliberately do NOT check alpha; the reasoning and the numbers
    /// are at the call site. In short: the check is real work on the framework's
    /// hottest function, worth `textwall` +3.3% / `fanout` +3.0% measured, and it
    /// would be a permanent tax on every page to protect paths that have not been
    /// migrated. The place it is free is the paint site, once per view.
    ///
    /// So an unmigrated path renders `.clear` as the solid black its underlying
    /// value is — SwiftUI's underlying value too. That is a gap in a NEW API rather
    /// than a regression (`Color.clear` did not exist before this branch), it is
    /// loud in every debug build, and §16 lists the entry points that close it.
    @Test("The emitters spell a transparent colour rather than skipping it")
    func transparentStillPaintsOnUnmigratedPaths() {
        // Read through `opaqueSpelling`, which is what every MIGRATED paint site
        // does — the assertion fires on the bare colour, and a test is not exempt.
        #expect(
            Color.clear.opaqueSpelling.foregroundCodes(depth: .truecolor) == ["38", "2", "0", "0", "0"],
            "black, because that is what `.clear`'s value is")
        // The migrated route: the alpha goes on a region and never reaches here.
        #expect(Color.clear.opaqueSpelling.isOpaque, "the spelling carries no alpha")
        #expect(Color.clear.alpha == 0, "while the colour itself still does")
    }

    /// The one that would otherwise be silent AND fatal: a semantic colour
    /// resolves through the palette, and the alpha belongs to the value the
    /// caller wrote, not to the palette's answer.
    @Test("Resolving a semantic colour keeps the alpha the caller asked for")
    func resolveKeepsAlpha() {
        let accent = translucent(.accentColor)
        let resolved = accent.resolve(with: AlphaTestPalette())
        #expect(resolved.alpha == 128, "got \(resolved.alpha)")
        #expect(resolved.value != accent.value, "…and it really did resolve")
    }

    /// Interpolating between two alphas interpolates the alpha too — which is
    /// what makes a `withAnimation` fade of a colour's opacity work, since both
    /// colour animators go through `lerp`.
    @Test("Interpolation treats alpha as a fourth channel")
    func interpolationBlendsAlpha() {
        let clearish = translucent(.rgb(255, 0, 0), 0)
        let solid = Color.rgb(255, 0, 0)
        #expect(Color.lerp(clearish, solid, phase: 0.5).alpha == 128)
        #expect(Color.lerp(clearish, solid, phase: 0).alpha == 0)
        #expect(Color.lerp(clearish, solid, phase: 1).alpha == 255)
    }

    /// `opacity(_:over:)` CONSUMES the alpha — it composites over a known
    /// surface, so its result is a plain opaque colour. Stated as a test because
    /// the alternative reading (carry it) would double-apply the fade.
    @Test("opacity(_:over:) consumes the alpha it applies")
    func compositingConsumesAlpha() {
        let result = translucent(.rgb(255, 0, 0)).opacity(0.5, over: .black)
        #expect(result.isOpaque, "got \(result.alpha)")
    }
}

// MARK: - A theme's own translucency

/// Resolving a semantic colour composes two alphas: the theme slot's and the
/// reference's. Discarding either is a silently wrong colour.
@Suite("A faded palette slot")
struct FadedPaletteSlotTests {

    private let palette = FadedSlotPalette()

    @Test("A faded slot survives being resolved")
    func slotAlphaSurvives() {
        // `carryingAlpha(of: self)` used to end `resolve(with:)`, which replaced the
        // slot's alpha with the REFERENCE's — and a bare `.palette.accent` is
        // opaque, so the theme's fade was discarded and the colour rendered solid.
        let resolved = Color.Semantic.accent.resolve(with: palette)
        #expect(resolved.alpha == 128, "got \(resolved.alpha)")
    }

    @Test("A reference's alpha multiplies with the slot's")
    func alphasCompose() {
        // Half of a half. The same multiplication `Color.opacity(_:)` performs, and
        // for the same reason: the theme's translucency and the call site's are two
        // statements about one paint, and it is subject to both.
        let resolved = Color.Semantic.accent.opacity(0.5).resolve(with: palette)
        #expect(resolved.alpha == 64, "got \(resolved.alpha)")
    }

    @Test("An opaque slot leaves a reference's own alpha exactly alone")
    func opaqueSlotIsExact() {
        // The rounding matters: multiplying on the 0…255 integers has to give back
        // 128 and not 127, or every hop through an opaque slot would fade a colour
        // slightly. 255 × 128 / 255 is exact only if the arithmetic says so.
        #expect(Color.Semantic.error.opacity(0.5).resolve(with: palette).alpha == 128)
        #expect(Color.Semantic.error.resolve(with: palette).isOpaque)
    }

    @Test("A concrete colour is returned untouched, not squared")
    func concreteIsUntouched() {
        // The first version of this fix composed `self`'s alpha at the exit, which
        // ran for the non-semantic case too and squared it — 128 became 64 for a
        // colour that had never been near a palette.
        var faded = Color.rgb(200, 100, 50)
        faded.alpha = 128
        #expect(faded.resolve(with: palette).alpha == 128, "got \(faded.resolve(with: palette).alpha)")
        #expect(Color.red.resolve(with: palette).isOpaque)
    }

    @Test("A reference cycle still terminates, and keeps what it accumulated")
    func cycleKeepsAlpha() {
        // A slot pointing at its own role (a colour picker editing the role it is
        // displaying) is broken after a bounded number of hops. The fallback grey
        // takes the alpha accumulated along the way rather than dropping it, so a
        // faded cyclic reference stays faded instead of turning solid.
        struct CyclicPalette: Palette {
            let id = "cyclic"
            let name = "Cyclic"
            let background = Color.black
            let foreground = Color.white
            let accent = Color(value: .semantic(.accent))
            let success = Color.green
            let warning = Color.yellow
            let error = Color.red
            let info = Color.blue
            let border = Color.gray
        }
        let resolved = Color.Semantic.accent.opacity(0.5).resolve(with: CyclicPalette())
        if case .semantic = resolved.value {
            Issue.record("resolution must never hand a semantic colour to the renderer")
        }
        #expect(resolved.alpha == 128, "got \(resolved.alpha)")
    }
}

// MARK: - Every palette derivation, and which of three things it does

/// A palette whose every slot is half-faded — the input that tells the three
/// kinds of ``Palette`` derivation apart.
private struct FadedEverythingPalette: Palette {
    let id = "faded-everything"
    let name = "Faded everything"
    let background = Color.rgb(10, 10, 20).opacity(0.5)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let accent = Color.rgb(0, 180, 200).opacity(0.5)
    let success = Color.green.opacity(0.5)
    let warning = Color.yellow.opacity(0.5)
    let error = Color.red.opacity(0.5)
    let info = Color.blue.opacity(0.5)
    let border = Color.gray.opacity(0.5)
}

/// **What every `Palette` derivation does with a faded slot's alpha, written down.**
///
/// `Palette` is a public protocol of plain `var …: Color { get }` members and
/// nothing normalises what a custom one returns, so one faded slot reaches every
/// derived colour in the theme. Before this there was no record of what happened
/// to it — and the answers turned out to be three different things, only two of
/// which anyone had decided:
///
/// - **carries** — a re-*spelling*. The same ink written differently (a
///   pass-through default, a contrast floor, a hover lift), so the alpha travels
///   with it and the composite that knows the real backdrop spends it.
/// - **spends** — a *composite* over a ground the palette states (`opacity(_:over:)`).
///   The alpha is consumed here, by design, and the result is opaque. §21 records
///   why the pulse pairs must both do this.
/// - **drops** — neither. A lightness step taken through `Color.rgb(…)` in
///   ``Palette/scaled(_:by:)``, which could not carry what it never read: a
///   three-tuple has no fourth element.
///
/// The suite exists because the third category was invisible: an opaque colour
/// never trips the emitter's assertion, so a faded theme's chrome came out solid
/// with no diagnostic at all — exactly §20's failure, one level further out.
/// Pinning all three means a derivation that changes category fails here instead.
///
/// **The third category is now empty** (§39): `scaled` ends in `carryingAlpha(of:)`,
/// so a surface derived from a translucent page is translucent. The category stays
/// described here because it is what made the question askable, and because a new
/// derivation that rebuilds a colour from `rgbComponents` lands in it by default.
@Suite("Palette derivations and a faded slot")
struct FadedPaletteDerivationTests {

    private let palette = FadedEverythingPalette()

    /// The re-spellings. Each of these must come back at the slot's own alpha.
    @Test("A re-spelling carries the slot's alpha")
    func respellingsCarry() {
        let rows: [(name: String, derived: Color)] = [
            ("statusBarBackground", palette.statusBarBackground),
            ("appHeaderBackground", palette.appHeaderBackground),
            ("overlayBackground", palette.overlayBackground),
            ("foregroundSecondary", palette.foregroundSecondary),
            ("foregroundTertiary", palette.foregroundTertiary),
            ("foregroundQuaternary", palette.foregroundQuaternary),
            ("cursorColor", palette.cursorColor),
            ("readableText(on:)", palette.readableText(on: palette.accent)),
            // The one that was neither: a lerp toward an opaque extreme brought a
            // 128 back as 184, so the pointer alone half-restored a faded tint.
            ("hoveredForeground(foreground)", palette.hoveredForeground(palette.foreground)),
            ("hoveredForeground(accent)", palette.hoveredForeground(palette.accent)),
            // The four surface steps. They were the open item — recorded as dropping
            // the alpha, with this suite's own note saying to move them here if the
            // question was ever answered by carrying it. It was (§39): a surface
            // derived from a translucent page is translucent, one wash all the way
            // down, because a user who fades the page has said what they want and any
            // other answer overrides it.
            ("fieldBackground", palette.fieldBackground),
            ("fieldBackground(on:)", palette.fieldBackground(on: palette.background)),
            ("liftedBackground", palette.liftedBackground),
            ("lifted(from:)", palette.lifted(from: palette.background)),
        ]
        for (name, derived) in rows {
            #expect(derived.alpha == 128, "\(name) came back at \(derived.alpha), not 128")
        }
    }

    /// The composites. Each SPENDS the alpha against a ground the palette states,
    /// so an opaque result is the correct answer and not a leak.
    @Test("A composite over a stated ground spends the alpha")
    func compositesSpend() {
        let rows: [(name: String, derived: Color)] = [
            ("focusBackground", palette.focusBackground),
            ("restingControlFace", palette.restingControlFace),
            ("hoveredControlFace", palette.hoveredControlFace),
            ("accentPulse.dim", palette.accentPulse().dim),
            ("accentPulse.bright", palette.accentPulse().bright),
            ("accentFillPulse.dim", palette.accentFillPulse().dim),
            ("accentFillPulse.bright", palette.accentFillPulse().bright),
        ]
        for (name, derived) in rows {
            #expect(derived.alpha == .max, "\(name) kept alpha \(derived.alpha)")
        }
    }

    /// **The defect found underneath the open question, which is not the same thing.**
    ///
    /// `scaled(_:by:)` has one branch that must MIX rather than scale — a pure black
    /// page, where there is no hue to preserve and no product but zero — and it
    /// detected that case with `scaled == base`. `Color` is `Hashable` over its value
    /// AND its alpha, so that comparison answered "different" for two colours that are
    /// the same colour, and the branch was unreachable for:
    ///
    /// - a page at `.rgb(0, 0, 0).opacity(0.5)`, because the rebuilt colour is opaque;
    /// - a page at `.black`, because the rebuilt one is `.rgb` — the CASE
    ///   differs at full opacity, so this half was never about alpha at all.
    ///
    /// In both, every surface came back as the page colour: a field, a tab body and a
    /// well all invisible, which `surface(steppedFrom:separation:)`'s own note calls
    /// "the same as drawing none". Asked of the CHANNELS instead, both step.
    @Test("A black page steps whatever its alpha and whatever its spelling")
    func blackPagesStillStep() {
        // The black slot measures as black only once the terminal has reported its
        // sixteen, so they are reported here: every one black, since only slot 0 is read.
        let reported = TerminalColors(slots: TerminalColors.Slots(repeating: TerminalColors.RGB(red: 0, green: 0, blue: 0)))
        TerminalColors.withCurrent(reported) {
            for (name, page) in [
                ("faded rgb black", Color.rgb(0, 0, 0).opacity(0.5)),
                ("the black slot", Color.ansi(.black)),
                ("opaque rgb black", Color.rgb(0, 0, 0)),
            ] {
                let palette = BlackPagePalette(background: page)
                for (which, surface) in [
                    ("fieldBackground", palette.fieldBackground),
                    ("liftedBackground", palette.liftedBackground),
                    ("lifted(from:)", palette.lifted(from: page)),
                ] {
                    #expect(
                        surface.rgbComponents.map { $0 != (0, 0, 0) } ?? false,
                        "\(name) \(which) came back as the page: \(surface)")
                }
            }
        }
    }
}

/// A palette whose page is black, in the three spellings that reach
/// ``Palette/scaled(_:by:)``'s mixing branch differently.
private struct BlackPagePalette: Palette {
    let id = "black-page"
    let name = "Black page"
    let background: Color
    let foreground = Color.rgb(230, 230, 240)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.gray
}
