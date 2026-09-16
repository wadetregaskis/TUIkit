//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroundedPaletteTerminalTests.swift
//
//  A palette's grounds and `Color.default` roles, grounded on the terminal's own
//  colours as the environment stores the palette: a translucent root is spent over
//  the terminal's page, and a `Color.default` role is re-spelled as the terminal's
//  own background or foreground.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A palette whose every role is stated and can be re-spelled, one role at a time.
///
/// `focusBackground` and `fieldBackground` are left to their derived defaults, because
/// grounding re-derives exactly those.
private struct RolePalette: Palette {
    var id = "roles"
    var name = "Roles"
    var background = Color.rgb(10, 10, 20)
    var statusBarBackground = Color.rgb(20, 10, 10)
    var appHeaderBackground = Color.rgb(10, 20, 10)
    var overlayBackground = Color.rgb(30, 30, 30)
    var foreground = Color.rgb(230, 230, 240)
    var foregroundSecondary = Color.rgb(200, 200, 210)
    var foregroundTertiary = Color.rgb(160, 160, 170)
    var foregroundQuaternary = Color.rgb(120, 120, 130)
    var accent = Color.rgb(0, 180, 200)
    var success = Color.rgb(40, 200, 40)
    var warning = Color.rgb(220, 200, 40)
    var error = Color.rgb(220, 40, 40)
    var info = Color.rgb(40, 120, 220)
    var border = Color.rgb(120, 120, 130)
    var cursorColor = Color.rgb(250, 250, 0)

    /// The fifteen roles a palette states, as opposed to the two it derives.
    static let statedRoles = [
        "background", "statusBarBackground", "appHeaderBackground", "overlayBackground",
        "foreground", "foregroundSecondary", "foregroundTertiary", "foregroundQuaternary",
        "accent", "success", "warning", "error", "info", "border", "cursorColor",
    ]

    /// The three grounds nothing inside the app is behind.
    static let roots: Set<String> = ["background", "statusBarBackground", "appHeaderBackground"]

    // One flat case per stated role, plus the miss: splitting the table to satisfy the
    // count would hide which role is which. Key paths would not be Sendable arguments.
    // swiftlint:disable cyclomatic_complexity
    /// This palette with `role` spelled `colour`.
    func with(_ role: String, _ colour: Color) -> Self {
        var copy = self
        switch role {
        case "background": copy.background = colour
        case "statusBarBackground": copy.statusBarBackground = colour
        case "appHeaderBackground": copy.appHeaderBackground = colour
        case "overlayBackground": copy.overlayBackground = colour
        case "foreground": copy.foreground = colour
        case "foregroundSecondary": copy.foregroundSecondary = colour
        case "foregroundTertiary": copy.foregroundTertiary = colour
        case "foregroundQuaternary": copy.foregroundQuaternary = colour
        case "accent": copy.accent = colour
        case "success": copy.success = colour
        case "warning": copy.warning = colour
        case "error": copy.error = colour
        case "info": copy.info = colour
        case "border": copy.border = colour
        case "cursorColor": copy.cursorColor = colour
        default: Issue.record("no role \(role)")
        }
        return copy
    }
    // swiftlint:enable cyclomatic_complexity

    /// `role` as `palette` answers it.
    static func read(_ role: String, from palette: any Palette) -> Color {
        switch role {
        case "background": palette.background
        case "statusBarBackground": palette.statusBarBackground
        case "appHeaderBackground": palette.appHeaderBackground
        case "overlayBackground": palette.overlayBackground
        case "foreground": palette.foreground
        case "foregroundSecondary": palette.foregroundSecondary
        case "foregroundTertiary": palette.foregroundTertiary
        case "foregroundQuaternary": palette.foregroundQuaternary
        case "accent": palette.accent
        case "success": palette.success
        case "warning": palette.warning
        case "error": palette.error
        case "info": palette.info
        case "border": palette.border
        default: palette.cursorColor
        }
    }
}

@MainActor
@Suite("A palette grounded on the terminal's own colours")
struct GroundedPaletteTerminalTests {

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    private static let page = Color(value: .terminalBackground)
    private static let ink = Color(value: .terminalForeground)

    /// `palette` as the environment stores it.
    private func stored(_ palette: any Palette) -> any Palette {
        var environment = EnvironmentValues()
        environment.palette = palette
        return environment.palette
    }

    /// The three root grounds of `palette`, in the order the root spells them.
    private func roots(_ palette: any Palette) -> [Color] {
        [palette.background, palette.appHeaderBackground, palette.statusBarBackground]
    }

    // MARK: - Roots, while the terminal has said nothing

    @Test("A clear page is the terminal's own, and the root spells it as 49")
    func clearRootIsTheTerminalsPage() {
        TerminalColors.withCurrent(.unknown) {
            let palette = RolePalette()
                .with("background", .clear)
                .with("appHeaderBackground", .clear)
                .with("statusBarBackground", .clear)
            let seen = stored(palette)
            #expect(roots(seen) == [Self.page, Self.page, Self.page])
            let codes = ColorDepth.withCurrent(.truecolor) { RenderBackgroundCodes(palette: seen) }
            for code in [codes.content, codes.appHeader, codes.statusBar] {
                #expect(code == "\u{1B}[49m", "\(code.debugDescription)")
            }
        }
    }

    @Test("A root below half is the terminal's page, and at half or more its own colour")
    func partialRootSnapsWhileUnreported() {
        TerminalColors.withCurrent(.unknown) {
            let quarter = stored(RolePalette().with("background", Color.rgb(10, 10, 20).opacity(64.0 / 255)))
            #expect(quarter.background == Self.page)
            let codes = ColorDepth.withCurrent(.truecolor) { RenderBackgroundCodes(palette: quarter) }
            #expect(codes.content == "\u{1B}[49m", "\(codes.content.debugDescription)")

            // TranslucentGroundTests' ground: alpha 128, which keeps the colour.
            let half = stored(RolePalette().with("background", Color.rgb(10, 10, 20).opacity(0.5)))
            #expect(half.background == .rgb(10, 10, 20))
        }
    }

    @Test("A root spelled Color.default is the terminal's page")
    func defaultRootIsTheTerminalsPage() {
        TerminalColors.withCurrent(.unknown) {
            #expect(stored(RolePalette().with("background", .default)).background == Self.page)
        }
    }

    // MARK: - Roots, once the terminal has reported its page

    @Test("A half-translucent root is spent over the reported page")
    func partialRootSpendsOverTheReportedPage() {
        TerminalColors.withCurrent(Self.reported) {
            let seen = stored(RolePalette().with("background", Color.rgb(10, 10, 20).opacity(0.5)))
            #expect(seen.background == .rgb(25, 27, 36))
            let quarter = stored(RolePalette().with("background", Color.rgb(10, 10, 20).opacity(64.0 / 255)))
            #expect(quarter.background == .rgb(32, 35, 44))
            let clear = stored(RolePalette().with("background", .clear))
            #expect(clear.background == Self.page)
        }
    }

    // MARK: - Every stated role spelled Color.default

    @Test("Each stated role spelled Color.default becomes the terminal's own", arguments: RolePalette.statedRoles)
    func defaultRoleIsRespelled(role: String) {
        TerminalColors.withCurrent(.unknown) {
            let seen = stored(RolePalette().with(role, .default))
            let expected = RolePalette.roots.contains(role) || role == "overlayBackground" ? Self.page : Self.ink
            #expect(RolePalette.read(role, from: seen) == expected, "\(role)")
            // Nothing else moves: every other stated role is the palette's own.
            for other in RolePalette.statedRoles where other != role {
                #expect(
                    RolePalette.read(other, from: seen) == RolePalette.read(other, from: RolePalette()),
                    "\(other) moved when \(role) was Color.default")
            }
        }
    }

    @Test("The overlay wash spelled Color.default keeps its alpha")
    func defaultOverlayKeepsItsAlpha() {
        TerminalColors.withCurrent(.unknown) {
            let seen = stored(RolePalette().with("overlayBackground", Color.default.opacity(0.5)))
            #expect(seen.overlayBackground == Self.page.opacity(0.5))
        }
    }

    // MARK: - Text tiers spelled Color.default

    /// A page the terminal decides, with the four text tiers `Color.default` at the
    /// opacities a terminal-coloured palette uses.
    private static let defaultTiers = RolePalette()
        .with("background", .clear)
        .with("foreground", .default)
        .with("foregroundSecondary", Color.default.opacity(0.75))
        .with("foregroundTertiary", Color.default.opacity(0.55))
        .with("foregroundQuaternary", Color.default.opacity(0.38))

    private func tiers(_ palette: any Palette) -> [Color] {
        [palette.foreground, palette.foregroundSecondary, palette.foregroundTertiary, palette.foregroundQuaternary]
    }

    @Test("Text tiers are the terminal's foreground at full strength while it has said nothing")
    func defaultTiersArePlainWhileUnreported() {
        TerminalColors.withCurrent(.unknown) {
            #expect(tiers(stored(Self.defaultTiers)) == [Self.ink, Self.ink, Self.ink, Self.ink])
            // Over an RGB page too: the terminal's foreground has no RGB to mix.
            let rgbPage = Self.defaultTiers.with("background", .rgb(10, 10, 20))
            #expect(tiers(stored(rgbPage)) == [Self.ink, Self.ink, Self.ink, Self.ink])
        }
    }

    @Test("Text tiers are spent over the reported page")
    func defaultTiersSpendOverTheReportedPage() {
        TerminalColors.withCurrent(Self.reported) {
            #expect(
                tiers(stored(Self.defaultTiers)) == [
                    Self.ink, .rgb(138, 144, 156), .rgb(112, 118, 128), .rgb(90, 95, 105),
                ])
        }
    }

    @Test("An ink spelled Color.default at alpha 0 is the page")
    func defaultInkAtZeroIsThePage() {
        TerminalColors.withCurrent(.unknown) {
            let seen = stored(Self.defaultTiers.with("border", Color.default.opacity(0)))
            #expect(seen.border == Self.page)
        }
    }

    // MARK: - The two derived surfaces

    @Test("Focus and field are derived from the grounded page, unless stated")
    func derivedSurfacesFollowTheGround() {
        TerminalColors.withCurrent(.unknown) {
            let seen = stored(RolePalette().with("background", .clear).with("appHeaderBackground", .clear))
            // Over a page with no RGB there is no step to take: both are the page.
            #expect(seen.focusBackground == Self.page)
            #expect(seen.fieldBackground == Self.page)
        }
        TerminalColors.withCurrent(Self.reported) {
            let seen = stored(RolePalette().with("background", .clear).with("appHeaderBackground", .clear))
            #expect(seen.focusBackground == seen.derivedFocusBackground())
            #expect(seen.fieldBackground == seen.derivedFieldBackground())
            if case .rgb = seen.fieldBackground.value {} else {
                Issue.record("field \(seen.fieldBackground) is not a step off the reported page")
            }
            #expect(seen.fieldBackground.rgbComponents.map { [$0.red, $0.green, $0.blue] } != [40, 44, 52])
        }
    }

    @Test("A stated field and focus are kept")
    func statedSurfacesAreKept() {
        struct Stated: Palette {
            let id = "stated"
            let name = "Stated"
            let background = Color.clear
            let foreground = Color.rgb(230, 230, 240)
            let accent = Color.rgb(0, 180, 200)
            let success = Color.rgb(40, 200, 40)
            let warning = Color.rgb(220, 200, 40)
            let error = Color.rgb(220, 40, 40)
            let info = Color.rgb(40, 120, 220)
            let border = Color.rgb(120, 120, 130)
            let focusBackground = Color.rgb(1, 2, 3)
            let fieldBackground = Color.rgb(4, 5, 6)
        }
        TerminalColors.withCurrent(Self.reported) {
            let seen = stored(Stated())
            #expect(seen.focusBackground == .rgb(1, 2, 3))
            #expect(seen.fieldBackground == .rgb(4, 5, 6))
        }
    }

    // MARK: - The derivation

    @Test("Grounding a grounded palette, or a tint over one, changes nothing")
    func groundingIsIdempotent() {
        TerminalColors.withCurrent(.unknown) {
            let once = stored(Self.defaultTiers)
            let twice = stored(once)
            #expect((twice as? GroundedPalette)?.base is RolePalette, "grounded twice: \(type(of: twice))")
            #expect(stored(TintedPalette(base: once, tint: .rgb(200, 100, 50))) is TintedPalette)
        }
    }

    @Test("A tint spelled Color.default over a grounded palette is the terminal's foreground")
    func defaultTintIsGrounded() {
        TerminalColors.withCurrent(.unknown) {
            let tinted = stored(TintedPalette(base: stored(Self.defaultTiers), tint: .default))
            #expect(tinted.accent == Self.ink)
            #expect(tinted.background == Self.page)
        }
    }

    @Test("Groundings under two answers are different palettes, and under one the same")
    func groundingsCompareTheTerminal() {
        let unknown = TerminalColors.withCurrent(.unknown) { stored(Self.defaultTiers) }
        let reported = TerminalColors.withCurrent(Self.reported) { stored(Self.defaultTiers) }
        let again = TerminalColors.withCurrent(Self.reported) { stored(Self.defaultTiers) }
        #expect(!unknown.isSamePalette(as: reported))
        #expect(reported.isSamePalette(as: again))
    }

    /// Every palette that STATES its own colours: its grounds are opaque and no role of
    /// it is `Color.default`, so there is nothing to ground. A palette that states none
    /// of its own is grounded, which is the point of grounding, and is pinned with
    /// itself rather than here.
    @Test("Every palette that states its own colours is stored as it was given")
    func statedPalettesAreUntouched() {
        for terminal in [TerminalColors.unknown, Self.reported] {
            TerminalColors.withCurrent(terminal) {
                for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
                    #expect(!(stored(palette) is GroundedPalette), "\(palette.id)")
                }
            }
        }
    }
}
