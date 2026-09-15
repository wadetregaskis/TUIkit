//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Palette Environment Key

/// Environment key for the current palette.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue: any Palette = SystemPalette(.green)
}

extension EnvironmentValues {
    /// The current palette.
    ///
    /// Set a palette at the app level and it propagates to all child views:
    ///
    /// ```swift
    /// WindowGroup {
    ///     ContentView()
    /// }
    /// .environment(\.palette, SystemPalette(.green))
    /// ```
    ///
    /// Access the palette in `renderToBuffer(context:)`:
    ///
    /// ```swift
    /// let palette = context.environment.palette
    /// let fg = palette.foreground
    /// ```
    public var palette: any Palette {
        get { self[PaletteKey.self] }
        // Through `GroundedPalette.grounding`, which hands back every palette whose
        // root grounds are opaque, and none of whose stated roles is `Color.default`,
        // exactly as it was given. See there for what it does to the others, and why.
        set { self[PaletteKey.self] = GroundedPalette.grounding(newValue) }
    }
}

// MARK: - Root Grounds

/// A palette grounded on the terminal's own colours: its three ROOT grounds spent over
/// the terminal's page, and its roles spelled `Color.default` re-spelled as the
/// terminal's own background or foreground.
///
/// **The roots.** The page background, the app header's and the status bar's are
/// composite roots: nothing inside the app is behind them, only the terminal's own
/// background. That background is `.terminalBackground`, SGR 49 as a fill, which measures
/// as the RGB the terminal reported for it (OSC 11), and as nothing until it has. Each
/// root's alpha is spent over it with `spendingAlpha(over:)`:
/// - `.clear`, or any root at alpha 0, is the terminal's page, and the root emits 49.
/// - Over a reported page, a translucent root is RGB between its colour and that page.
/// - Over a page the terminal has not reported, no blend can mix, so a root keeps its
///   colour at an alpha of ½ or more and is the terminal's page below (§75 of
///   `Documentation/Opacity as composition.md`).
/// - A root spelled `Color.default` is the terminal's page too.
///
/// Before the terminal's page was a colour, spent meant the opaque spelling, so `.clear`
/// was solid black: §70.4.
///
/// **`Color.default` roles.** `Color.default` is 39 as ink and 49 as a fill, so it stands
/// for no one colour and never measures, and every rule that measures a role (a contrast
/// floor, a surface walk, a hover lift) saw nothing. A role's slot is known, though:
/// `overlayBackground` is a fill, so it becomes `.terminalBackground` with its alpha kept,
/// and every other stated role is an ink, so it becomes `.terminalForeground`, its alpha
/// spent over the grounded page.
///
/// Where either side of that spend has no RGB there is no dimmer colour to show, and the
/// ink is the terminal's foreground at full strength. The blend rule would make a tier
/// below ½ the page instead. The foreground slot would still draw it as 39, but a
/// contrast floor, a surface walk or a button's resting caps would read it as the page,
/// and a fade would drop its glyph (§76). An ink at alpha 0 is the page, as nothing of
/// anything is.
///
/// **The two derived surfaces.** `focusBackground` and `fieldBackground` default to
/// derivations from the other roles (`derivedFocusBackground()`,
/// `derivedFieldBackground()`). Where the base's value is its own derived default, it is
/// derived again from the grounded roles, so a field steps off the page the terminal
/// reported rather than off `.clear`'s black. A value the base states for itself is kept.
///
/// **Why here.** Every path that spells a colour asserts it is opaque, so a translucent
/// root trapped a debug build on its first frame (`RenderBackgroundCodes` spells all three
/// before any view has drawn), and the Theme page's colour pickers offer an alpha channel
/// on every role. So the roles are grounded ONCE, where a palette enters the environment:
/// every write to ``EnvironmentValues/palette`` comes through the setter, whether from
/// `.palette(_:)`, `.tint(_:)`, a theme or the render loop's own. The alternative was the
/// twenty-odd sites that paint a ground, a count §68 is the standing warning against
/// trusting.
///
/// `overlayBackground` is deliberately not a root, and keeps its alpha: the wash a modal
/// dims its page with has the page behind it, and §68.5 claims its field and resolves it
/// against that page. Spending it here would freeze every translucent wash opaque.
///
/// Every role is STORED, computed once when the palette is written, and every one has to
/// be: `Palette`'s protocol defaults are collapsing, so an omitted role silently
/// recomputes from this palette's other roles instead of taking the base's (the trap
/// `TintedPalette` documents from experience). Adding a role to ``Palette`` means adding
/// it here; `StyleCascadeCoverageTests` asserts all of them.
package struct GroundedPalette: DerivedPalette {
    package let base: any Palette

    /// The terminal's colours when the roles were grounded, which is all they were
    /// derived from besides the base.
    package let terminal: TerminalColors

    /// Grounded under the same terminal colours. Under different ones the roots and
    /// inks spend over a different page, so they are different palettes. The render
    /// cache also clears when the process's colours change; this comparison is what
    /// tells apart two groundings under different task-local pins.
    package func hasSameDerivation(as other: Self) -> Bool { terminal == other.terminal }

    /// `palette` as the environment should hold it.
    ///
    /// Unchanged unless a root ground is translucent or one of the fifteen stated roles
    /// is spelled `Color.default`, and no bundled palette has either. So the common case
    /// pays three alpha compares and fifteen reads at the WRITE and nothing on the hot
    /// reads, where a wrapper around every palette would have added a forwarding hop to
    /// every colour every view asks for. `focusBackground` and `fieldBackground` are not
    /// read here: their defaults compute (a blend and a surface walk), and this runs on
    /// every palette write, each frame's and each `.tint(_:)`'s included.
    ///
    /// Idempotent. A grounded palette's roots are opaque and none of its roles is
    /// `Color.default`, so it is handed straight back, and so is a `TintedPalette` built
    /// over one, unless its tint is itself `Color.default`.
    package static func grounding(_ palette: any Palette) -> any Palette {
        guard needsGrounding(palette) else { return palette }
        return Self(base: palette)
    }

    /// Whether a root of `palette` is translucent, or a stated role is `Color.default`.
    private static func needsGrounding(_ palette: any Palette) -> Bool {
        let background = palette.background
        let appHeader = palette.appHeaderBackground
        let statusBar = palette.statusBarBackground
        if !background.isOpaque || !appHeader.isOpaque || !statusBar.isOpaque { return true }
        return isDefault(background) || isDefault(appHeader) || isDefault(statusBar)
            || isDefault(palette.overlayBackground)
            || isDefault(palette.foreground) || isDefault(palette.foregroundSecondary)
            || isDefault(palette.foregroundTertiary) || isDefault(palette.foregroundQuaternary)
            || isDefault(palette.accent) || isDefault(palette.success)
            || isDefault(palette.warning) || isDefault(palette.error)
            || isDefault(palette.info) || isDefault(palette.border)
            || isDefault(palette.cursorColor)
    }

    /// Whether `colour` is spelled `Color.default`, at any alpha.
    private static func isDefault(_ colour: Color) -> Bool {
        if case .terminalDefault = colour.value { true } else { false }
    }

    /// `colour` spelled as `terminal` instead, alpha kept, if it is `Color.default`.
    private static func respelled(_ colour: Color, as terminal: Color) -> Color {
        isDefault(colour) ? terminal.carryingAlpha(of: colour) : colour
    }

    /// A root ground over the terminal's page.
    private static func grounded(root colour: Color) -> Color {
        respelled(colour, as: .terminalBackground).spendingAlpha(over: .terminalBackground)
    }

    /// An ink role over the grounded `page`: a `Color.default` ink is the terminal's
    /// foreground, and anything else is the base's own.
    private static func grounded(ink colour: Color, over page: Color) -> Color {
        guard isDefault(colour) else { return colour }
        let ink = Color.terminalForeground.carryingAlpha(of: colour)
        // Full strength where there is nothing to mix, rather than the heavier end:
        // see "`Color.default` roles" above.
        if ink.alpha != 0, ink.rgbComponents == nil || page.rgbComponents == nil {
            return ink.opaqueSpelling
        }
        return ink.spendingAlpha(over: page)
    }

    package init(base: any Palette) {
        self.base = base
        terminal = TerminalColors.current
        let page = Self.grounded(root: base.background)
        background = page
        statusBarBackground = Self.grounded(root: base.statusBarBackground)
        appHeaderBackground = Self.grounded(root: base.appHeaderBackground)
        overlayBackground = Self.respelled(base.overlayBackground, as: .terminalBackground)

        foreground = Self.grounded(ink: base.foreground, over: page)
        foregroundSecondary = Self.grounded(ink: base.foregroundSecondary, over: page)
        foregroundTertiary = Self.grounded(ink: base.foregroundTertiary, over: page)
        foregroundQuaternary = Self.grounded(ink: base.foregroundQuaternary, over: page)

        accent = Self.grounded(ink: base.accent, over: page)
        success = Self.grounded(ink: base.success, over: page)
        warning = Self.grounded(ink: base.warning, over: page)
        error = Self.grounded(ink: base.error, over: page)
        info = Self.grounded(ink: base.info, over: page)

        border = Self.grounded(ink: base.border, over: page)
        cursorColor = Self.grounded(ink: base.cursorColor, over: page)

        // The base's own values first, so every stored property is set before the two
        // derivations below read this palette's grounded roles. Neither derivation reads
        // `focusBackground` or `fieldBackground`, so the placeholders are never seen.
        let baseFocus = base.focusBackground
        let baseField = base.fieldBackground
        focusBackground = baseFocus
        fieldBackground = baseField
        if baseFocus == base.derivedFocusBackground() {
            focusBackground = derivedFocusBackground()
        }
        if baseField == base.derivedFieldBackground() {
            fieldBackground = derivedFieldBackground()
        }
    }

    package var id: String { base.id }
    package var name: String { base.name }

    package let background: Color
    package let statusBarBackground: Color
    package let appHeaderBackground: Color
    package let overlayBackground: Color

    package let foreground: Color
    package let foregroundSecondary: Color
    package let foregroundTertiary: Color
    package let foregroundQuaternary: Color

    package let accent: Color
    package let success: Color
    package let warning: Color
    package let error: Color
    package let info: Color

    package let border: Color
    package private(set) var focusBackground: Color
    package let cursorColor: Color
    package private(set) var fieldBackground: Color
}

// MARK: - PaletteManager Environment Key

/// Environment key for the palette manager.
private struct PaletteManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager? = nil
}

extension EnvironmentValues {
    /// The palette manager for cycling and setting palettes.
    ///
    /// ```swift
    /// context.environment.paletteManager?.cycleNext()
    /// context.environment.paletteManager?.setCurrent(SystemPalette(.amber))
    /// ```
    ///
    /// `nil` outside a running application. These are the app's own objects,
    /// created by `AppRunner` and published by `RenderLoop.buildEnvironment()`
    /// — so a bare `EnvironmentValues()` (a headless render, a test) has none,
    /// which is the truth. It used to hand out a SHARED instance instead, and
    /// every such render mutated the same object: two tests rendering sheets in
    /// parallel both registered their ESC item into it and read each other's
    /// back. The convention here is the one `focusManager` and
    /// `keyEventDispatcher` already follow — a runtime service is Optional, and
    /// absent means absent.
    public var paletteManager: ThemeManager? {
        get { self[PaletteManagerKey.self] }
        set { self[PaletteManagerKey.self] = newValue }
    }
}

// MARK: - Enclosing Surface

/// Environment key for the surface a subtree is drawn on.
private struct SurfaceBackgroundKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The colour of the surface the current subtree is painted on, when a
    /// container painted one — `nil` when that is just the page.
    ///
    /// A control that draws its own surface (a `TextField`'s well) has to know
    /// what is behind it, because "a step off the page" and "a step off *this*"
    /// are the same colour when the container is itself a step off the page:
    /// a field inside a `TabView`'s body drew the tab's own tone and vanished
    /// into it. Read it through ``Palette/fieldBackground(on:)`` rather than
    /// directly, so the derivation stays in one place.
    ///
    /// `package` rather than `internal` since this moved down a module: the
    /// controls that read it are the umbrella module's.
    ///
    /// A control deriving a well of its own reads it through
    /// ``Palette/fieldBackground(on:)``, so that derivation stays in one place.
    /// A control compositing translucent ink wants ``enclosingSurface``
    /// instead, which is this with the page substituted for `nil`.
    package var surfaceBackground: Color? {
        get { self[SurfaceBackgroundKey.self] }
        set { self[SurfaceBackgroundKey.self] = newValue }
    }

    /// The colour ink drawn here actually lands on — ``surfaceBackground``
    /// where a container painted one, and the page where none did.
    ///
    /// NOT a convenience spelling of the Optional: the two answer different
    /// questions and the `nil` is load-bearing in the other one. A control
    /// deriving a *well* must know that nothing was painted, because on the
    /// page it takes the palette's own stated tone and anywhere else it steps
    /// off what it finds (``Palette/fieldBackground(on:)``). A caller
    /// compositing translucent ink has no such distinction: it needs whatever
    /// is behind it, and "the page" is a perfectly good answer.
    ///
    /// This is the surface ``Color/opacity(_:over:)`` asks for — "the surface
    /// the colour actually draws on". Passing `palette.background` where a
    /// container painted a surface composites the ink over a colour that is
    /// not there, and the result is not the requested opacity of anything: a
    /// focused `Link`'s quiet end, 20% of the accent, came out at the exact
    /// luminance of the `TabView` body it sat on.
    package var enclosingSurface: Color {
        surfaceBackground ?? palette.background.resolve(with: palette)
    }
}
