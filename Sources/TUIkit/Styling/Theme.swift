//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Theme.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - Theme

/// A bundle of styling defaults applied together with `.theme(_:)`.
///
/// A theme is **not** a new resolution mechanism — `.theme(_:)` expands into the
/// individual environment settings (palette, appearance, tint, a set of scoped
/// style entries, and optional control styles), so anything applied *closer* to
/// the content still overrides it. It's the convenient way to apply a consistent
/// set of customisations app-wide (or to any subtree).
///
/// ```swift
/// WindowGroup { ContentView() }.theme(.init(palette: TerminalProfilePalette(.ocean)))
/// // …or just one slice deeper:
/// DangerZone().tint(.red)
/// ```
public struct Theme: Sendable {
    /// The base palette.
    public var palette: any Palette
    /// The border appearance.
    public var appearance: Appearance
    /// An optional tint (overrides the palette's accent for the subtree).
    public var tint: Color?
    /// Scoped style entries the theme installs (e.g. "section headers bold",
    /// "default buttons green"). Applied in specificity order so the theme's
    /// more specific entries win over its broader ones; any deeper subtree
    /// modifier still wins by proximity.
    public var styles: [StyleCascade.Entry]
    /// Control styles to install, or `nil` to keep the inherited/default style.
    public var buttonStyle: (any ButtonStyle)?
    public var listStyle: (any ListStyle)?
    public var pickerStyle: (any PickerStyle)?

    public init(
        palette: any Palette,
        appearance: Appearance = .rounded,
        tint: Color? = nil,
        styles: [StyleCascade.Entry] = [],
        buttonStyle: (any ButtonStyle)? = nil,
        listStyle: (any ListStyle)? = nil,
        pickerStyle: (any PickerStyle)? = nil
    ) {
        self.palette = palette
        self.appearance = appearance
        self.tint = tint
        self.styles = styles
        self.buttonStyle = buttonStyle
        self.listStyle = listStyle
        self.pickerStyle = pickerStyle
    }

    /// The palette with the theme's tint folded into its accent — what the
    /// scene-level `.theme(_:)` applies so out-of-tree surfaces match.
    public var resolvedPalette: any Palette {
        if let tint { return TintedPalette(base: palette, tint: tint) }
        return palette
    }
}

// MARK: - Theme modifier

/// Expands a ``Theme`` into the individual environment settings for its content.
public struct ThemeModifier<Content: View>: View {
    public let content: Content
    public let theme: Theme

    public init(content: Content, theme: Theme) {
        self.content = content
        self.theme = theme
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        var environment = context.environment
        environment.appearance = theme.appearance
        if let tint = theme.tint {
            environment.tint = tint
            environment.palette = TintedPalette(base: theme.palette, tint: tint)
        } else {
            environment.palette = theme.palette
        }
        if let buttonStyle = theme.buttonStyle { environment.buttonStyle = buttonStyle }
        if let listStyle = theme.listStyle { environment.listStyle = listStyle }
        if let pickerStyle = theme.pickerStyle { environment.pickerStyle = pickerStyle }
        // Install the theme's scoped entries, broad-first so its more specific
        // ones win within the bundle; deeper subtree entries still win by proximity.
        var cascade = environment.styleCascade
        for entry in theme.styles.sorted(by: { $0.scope.specificity < $1.scope.specificity }) {
            cascade = cascade.appending(entry.scope, entry.attributes)
        }
        environment.styleCascade = cascade
        return context.withEnvironment(environment)
    }
}

extension ThemeModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension ThemeModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

extension View {
    /// Applies a ``Theme`` to this view's subtree — its palette, appearance,
    /// tint, scoped style defaults, and any control styles. Anything applied
    /// closer to the content overrides the theme's value for that slice.
    public func theme(_ theme: Theme) -> some View {
        ThemeModifier(content: self, theme: theme)
    }
}

extension Scene {
    /// Applies a ``Theme``'s palette (with its tint folded in) at the scene
    /// level, so out-of-tree surfaces (app header, status bar) match — the
    /// scene-level counterpart to ``View/theme(_:)``.
    ///
    /// - Note: Scene level applies the theme's **palette + tint**. To also apply
    ///   its scoped styles, control styles, and appearance, use ``View/theme(_:)``
    ///   on the scene's root content.
    public func theme(_ theme: Theme) -> some Scene {
        palette(theme.resolvedPalette)
    }
}
