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
        // root grounds are opaque exactly as it was given. See there for why one whose
        // grounds are translucent cannot be stored as stated.
        set { self[PaletteKey.self] = GroundedPalette.grounding(newValue) }
    }
}

// MARK: - Root Grounds

/// A palette whose three ROOT grounds reach the renderer already spent.
///
/// The page background, the app header's and the status bar's are composite roots:
/// nothing inside the app is behind them — only the terminal's own background, whose
/// colour the framework does not know. A translucent one has nothing to be composited
/// over. Every path that spells a colour asserts it is opaque, so such a palette trapped
/// a debug build on its first frame (`RenderBackgroundCodes` spells all three before any
/// view has drawn) and in release drew the grounds at full strength anyway, claiming
/// nothing. The Theme page's colour pickers offer an alpha channel on every role, so
/// this was one arrow key away.
///
/// Spent HERE, once, where a palette enters the environment — every write to
/// ``EnvironmentValues/palette`` comes through the setter, `.palette(_:)`, `.tint(_:)`,
/// a theme and the render loop's own alike — rather than at the twenty-odd sites that
/// paint a ground, a count §68 of `Documentation/Opacity as composition.md` is the
/// standing warning against trusting. With no colour to spend against, spent means the
/// opaque spelling: precisely what release already drew, without the trap. §70.4 records
/// what a terminal that reports its own background would let this do instead.
///
/// `overlayBackground` is deliberately not a root, and keeps its alpha: the wash a modal
/// dims its page with has the page behind it, and §68.5 claims its field and resolves it
/// against that page. Spending it here would freeze every translucent wash opaque.
///
/// Every other role FORWARDS, and has to: `Palette`'s protocol defaults are collapsing, so
/// an omitted role silently recomputes from this palette's other roles instead of taking
/// the base's (the trap `TintedPalette` documents from experience). Adding a role to
/// ``Palette`` means adding a line here; `StyleCascadeCoverageTests` asserts all of them.
package struct GroundedPalette: DerivedPalette {
    package let base: any Palette

    /// A grounding has no fields of its own, so two of the same base are one palette.
    package func hasSameDerivation(as other: Self) -> Bool { true }

    /// `palette` as the environment should hold it.
    ///
    /// Unchanged unless a root ground is translucent, which no bundled palette's is: the
    /// common case pays three alpha compares at the rare WRITE and nothing on the hot
    /// reads, where a wrapper around every palette would have added a forwarding hop to
    /// every colour every view asks for. Idempotent — a grounded palette's grounds are
    /// opaque, so it is handed straight back, and so is a `TintedPalette` built over one.
    package static func grounding(_ palette: any Palette) -> any Palette {
        guard palette.background.alpha != .max
            || palette.appHeaderBackground.alpha != .max
            || palette.statusBarBackground.alpha != .max
        else { return palette }
        return Self(base: palette)
    }

    package init(base: any Palette) {
        self.base = base
    }

    package var id: String { base.id }
    package var name: String { base.name }

    package var background: Color { base.background.opaqueSpelling }
    package var statusBarBackground: Color { base.statusBarBackground.opaqueSpelling }
    package var appHeaderBackground: Color { base.appHeaderBackground.opaqueSpelling }
    package var overlayBackground: Color { base.overlayBackground }

    package var foreground: Color { base.foreground }
    package var foregroundSecondary: Color { base.foregroundSecondary }
    package var foregroundTertiary: Color { base.foregroundTertiary }
    package var foregroundQuaternary: Color { base.foregroundQuaternary }

    package var accent: Color { base.accent }
    package var success: Color { base.success }
    package var warning: Color { base.warning }
    package var error: Color { base.error }
    package var info: Color { base.info }

    package var border: Color { base.border }
    package var focusBackground: Color { base.focusBackground }
    package var cursorColor: Color { base.cursorColor }
    package var fieldBackground: Color { base.fieldBackground }
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
