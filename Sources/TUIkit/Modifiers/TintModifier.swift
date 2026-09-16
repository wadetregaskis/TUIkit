//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TintModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - Tinted palette

/// A ``Palette`` that delegates to a base palette but overrides ``accent`` with
/// a tint colour. Applying `.tint(_:)` installs one for the subtree, so every
/// `palette.accent` read — button caps and focus pulse, a toggle's ON mark, a
/// slider/stepper's arrows, a radio's selected dot, focus highlights, accent-
/// coloured text — follows the tint, with no per-control wiring.
///
/// `accent` is the only role this CHANGES — but every other role still has to
/// be written out, and that is the whole hazard of the type. A `Palette` role
/// left without a witness here does not fall through to `base`; it falls to
/// `Palette`'s protocol extension, whose defaults are *collapsing* — they
/// recompute the role from this palette's OTHER roles. So an omission silently
/// discards whatever the base stated for it and substitutes a derived colour.
/// That is not hypothetical: `fieldBackground` was missing, and every tinted
/// subtree drew its text fields on a surface stepped off `background` instead
/// of on the one the base palette named.
///
/// Adding a role to ``Palette`` therefore means adding a line here.
/// `StyleCascadeCoverageTests` asserts all of them, driven by a table it
/// cross-checks against a palette that states every role, so the omission
/// fails a test instead of quietly changing a colour.
struct TintedPalette: DerivedPalette {
    let base: any Palette
    let tint: Color

    /// The tint is the only field this adds; the bases are compared by the caller.
    func hasSameDerivation(as other: Self) -> Bool { tint == other.tint }

    var id: String { base.id }
    var name: String { base.name }

    var background: Color { base.background }
    var statusBarBackground: Color { base.statusBarBackground }
    var appHeaderBackground: Color { base.appHeaderBackground }
    var overlayBackground: Color { base.overlayBackground }

    var foreground: Color { base.foreground }
    var foregroundSecondary: Color { base.foregroundSecondary }
    var foregroundTertiary: Color { base.foregroundTertiary }
    var foregroundQuaternary: Color { base.foregroundQuaternary }

    // Resolve the tint against the base palette so the accent is always a
    // concrete colour. A *semantic* tint (e.g. `.tint(.palette.success)`) would
    // otherwise reach the ANSI renderer unresolved and trap — `.resolve(with:)`
    // returns a concrete colour unchanged, and maps `.semantic(role)` to the
    // base palette's colour for that role.
    var accent: Color { tint.resolve(with: base) }

    var success: Color { base.success }
    var warning: Color { base.warning }
    var error: Color { base.error }
    var info: Color { base.info }

    var border: Color { base.border }
    var focusBackground: Color { base.focusBackground }
    var cursorColor: Color { base.cursorColor }
    var fieldBackground: Color { base.fieldBackground }

    // Not a colour, and forwarded for exactly the reason the colours are: left
    // unstated it would be recomputed from this palette's page, so a `.tint` inside
    // an `.environment(\.colorScheme, …)` would throw the pin away.
    var colorScheme: ColorScheme { base.colorScheme }
}

// MARK: - tint environment

/// Environment key for the cascading tint colour (SwiftUI's `\.tint`).
private struct TintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The tint colour applied to this subtree, if any (set via
    /// ``View/tint(_:)``). The accent affordance of controls follows it.
    public var tint: Color? {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

// MARK: - Tint modifier

/// Applies a tint to its content's subtree by overriding the environment
/// palette's accent (see `TintedPalette`). A read-modify-write at render, so
/// it composes with the surrounding palette like the other style modifiers.
public struct TintModifier<Content: View>: View {
    public let content: Content
    public let tint: Color?

    public init(content: Content, tint: Color?) {
        self.content = content
        self.tint = tint
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        guard let tint else { return context }

        // The same bookkeeping `EnvironmentModifier` and `_StyleEnvironmentView`
        // do, and it is not optional here either: this is NOT a plain
        // `setting()` write that only the subtree reads. The render memo keys on
        // identity + view value + size and deliberately carries no environment,
        // so a memoized view below an `.tint(…)` that changed serves the buffer
        // painted in the OLD accent — wrong pixels, not merely stale work. The
        // `@State`-driven case is covered by accident (the declaring view is an
        // ancestor, so its own invalidation reaches the row); a tint bound to
        // anything else — `@AppStorage`, a cousin's state, a plain box — is not.
        //
        // The TINT is what is noted, not the `TintedPalette`: THAT type has no
        // `Equatable` conformance, so noting it would answer `.incomparable`
        // and refuse every memo store in the subtree — and the palette is a
        // pure function of (base, tint) anyway, so whoever swaps the base
        // palette notes that themselves.
        //
        // Not because it is an existential, which is what this said until
        // `ThemeModifier` needed the same answer and measured it: an `Any`
        // holding `any Palette` reports the CONCRETE type's conformance, so a
        // `SystemPalette` in that slot answers `is any Equatable` perfectly
        // well. It is `TintedPalette` specifically that cannot.
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                tint, identity: context.identity, keyPath: \EnvironmentValues.tint,
                depth: context.environmentApplicationDepth)
        {
            // A tint is ink; the sizes below it stay (see `_StyleEnvironmentView`).
            cache.clearAffected(by: context.identity, keepingSizes: true)
        }

        var environment = context.environment
        environment.tint = tint
        environment.palette = TintedPalette(base: environment.palette, tint: tint)
        var modified = context.withEnvironment(environment)
        modified.environmentApplicationDepth += 1
        return modified
    }
}

extension TintModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension TintModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

extension View {
    /// Sets the tint colour for this view's subtree — the accent affordance of
    /// every control inside (and accent-coloured content) follows it.
    ///
    /// ```swift
    /// Sidebar().tint(.green)        // green buttons, toggles, sliders, …
    /// DangerZone().tint(.red)
    /// ```
    ///
    /// `nil` leaves the inherited tint / palette accent unchanged.
    public func tint(_ tint: Color?) -> some View {
        TintModifier(content: self, tint: tint)
    }
}
