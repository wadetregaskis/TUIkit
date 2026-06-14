//  🖥️ TUIKit — Terminal UI Kit for Swift
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
/// Only `accent` is overridden; stored roles like `focusBackground` and
/// `cursorColor` keep the base palette's values.
struct TintedPalette: Palette {
    let base: any Palette
    let tint: Color

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

    var accent: Color { tint }

    var success: Color { base.success }
    var warning: Color { base.warning }
    var error: Color { base.error }
    var info: Color { base.info }

    var border: Color { base.border }
    var focusBackground: Color { base.focusBackground }
    var cursorColor: Color { base.cursorColor }
}

// MARK: - tint environment

/// Environment key for the cascading tint colour (SwiftUI's `\.tint`).
private struct TintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The tint colour applied to this subtree, if any (set via
    /// ``SwiftUI/View/tint(_:)``). The accent affordance of controls follows it.
    public var tint: Color? {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

// MARK: - Tint modifier

/// Applies a tint to its content's subtree by overriding the environment
/// palette's accent (see ``TintedPalette``). A read-modify-write at render, so
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
        var environment = context.environment
        environment.tint = tint
        environment.palette = TintedPalette(base: environment.palette, tint: tint)
        return context.withEnvironment(environment)
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
