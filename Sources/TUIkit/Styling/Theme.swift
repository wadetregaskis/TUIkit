//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// The button style to install, or `nil` to keep the inherited/default style.
    public var buttonStyle: (any ButtonStyle)?
    /// The list style to install, or `nil` to keep the inherited/default style.
    public var listStyle: (any ListStyle)?
    /// The picker style to install, or `nil` to keep the inherited/default style.
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

    /// A comparable stand-in for a control style, which is not `Equatable`.
    ///
    /// The built-in styles are stateless singletons distinguished only by their
    /// type, so the type IS the value — and unlike the style itself it can be
    /// compared, which is what keeps the note below from answering
    /// `.incomparable` and refusing every memo store in the subtree.
    private func styleToken(_ style: Any?) -> ObjectIdentifier? {
        style.map { ObjectIdentifier(type(of: $0)) }
    }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        // The same bookkeeping `EnvironmentModifier`, `TintModifier` and
        // `_StyleEnvironmentView` do, and not optional here either. The render
        // memo keys on identity, view value and size and deliberately carries
        // no environment, so a memoized subtree under a `.theme(…)` that
        // CHANGED serves the buffer painted in the old palette — wrong pixels,
        // not merely stale work. A theme driven by `@State` on an ancestor is
        // covered by accident, because that view's own invalidation reaches the
        // subtree; one driven by `@AppStorage`, a cousin's state or a plain box
        // is not.
        //
        // What is noted is the theme's INPUTS, never `environment.palette`.
        // With a tint that slot holds a `TintedPalette`, which has no
        // `Equatable` conformance — noting it would answer `.incomparable` and
        // refuse every memo store below every tinted theme, which is a worse
        // regression than the bug. The palette is a pure function of (base,
        // tint) and both of those are comparable, so comparing them is the same
        // question asked of values that can answer it. Same trade, same
        // reasoning, as the note in `TintModifier.modifiedContext`.
        if let cache = context.renderCache {
            var changed = false
            func note(_ value: Any, _ keyPath: PartialKeyPath<EnvironmentValues>) {
                if case .changed = cache.noteAppliedEnvironment(
                    value, identity: context.identity, keyPath: keyPath,
                    depth: context.environmentApplicationDepth)
                {
                    changed = true
                }
            }
            note(theme.appearance, \EnvironmentValues.appearance)
            note(theme.palette, \EnvironmentValues.palette)
            note(theme.tint as Any, \EnvironmentValues.tint)
            note(theme.styles, \EnvironmentValues.styleCascade)
            note(styleToken(theme.buttonStyle) as Any, \EnvironmentValues.buttonStyle)
            note(styleToken(theme.listStyle) as Any, \EnvironmentValues.listStyle)
            note(styleToken(theme.pickerStyle) as Any, \EnvironmentValues.pickerStyle)
            if changed {
                // A theme is ink; the sizes below it stay, as `TintModifier` and
                // `_StyleEnvironmentView` both keep theirs.
                cache.clearAffected(by: context.identity, keepingSizes: true)
            }
        }

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
        var modified = context.withEnvironment(environment)
        modified.environmentApplicationDepth += 1
        return modified
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
