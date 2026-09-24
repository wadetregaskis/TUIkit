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
/// style entries, optional control styles, and indicator animation speeds), so
/// anything applied *closer* to
/// the content still overrides it. It's the convenient way to apply a consistent
/// set of customisations app-wide (or to any subtree).
///
/// ```swift
/// WindowGroup { ContentView() }.theme(.init(palette: AppleTerminalPalette(.ocean)))
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
    /// How fast the theme's ambient indicators animate, per kind: each entry sets
    /// a speed as ``View/indicatorAnimationSpeed(_:for:)`` does.
    ///
    /// Applied broadest first, the entry naming the most kinds before the ones
    /// naming fewer, so the theme's narrower entries win where they overlap, as its
    /// scoped styles do; entries naming as many kinds apply in the order they are
    /// written. A kind no entry names keeps what it inherited, and a speed set
    /// closer to the content still wins.
    public var indicatorAnimationSpeeds: [IndicatorAnimationSpeeds.Entry]

    public init(
        palette: any Palette,
        appearance: Appearance = .rounded,
        tint: Color? = nil,
        styles: [StyleCascade.Entry] = [],
        buttonStyle: (any ButtonStyle)? = nil,
        listStyle: (any ListStyle)? = nil,
        pickerStyle: (any PickerStyle)? = nil,
        indicatorAnimationSpeeds: [IndicatorAnimationSpeeds.Entry] = []
    ) {
        self.palette = palette
        self.appearance = appearance
        self.tint = tint
        self.styles = styles
        self.buttonStyle = buttonStyle
        self.listStyle = listStyle
        self.pickerStyle = pickerStyle
        self.indicatorAnimationSpeeds = indicatorAnimationSpeeds
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

    /// A control style held so it can be compared with the next frame's — what
    /// ``ComparablePalette`` is for a palette, and for the same reason: the slot
    /// holds an existential the compiler cannot promise is `Equatable`, and
    /// ``note(_:_:)`` takes a value it can.
    ///
    /// The TYPE first, which is the cheap rejection and, for a style that cannot
    /// answer by value, the whole of it; then by VALUE where the style can
    /// answer. The style protocols are public and carry no `Equatable`
    /// refinement — an app writes `struct MyStyle: ButtonStyle` and owes nothing
    /// more — so both halves are live. Every style this package ships conforms,
    /// which is what `3a7c1d27..bbac32c8` was for.
    ///
    /// The type alone used to be the whole answer, and that was the bug: two
    /// styles of one type then compared equal however differently they draw, so
    /// a style that HOLDS what it draws changed under a memoized subtree with
    /// nothing to notice, and the buffer painted by the one before was served.
    /// The justification for that read "the built-in styles are stateless
    /// singletons distinguished only by their type, so the type IS the value",
    /// which was never true of `_LinkButtonStyle` or `_ColorSwatchButtonStyle`
    /// and says nothing at all about an app's own.
    private struct ComparableStyle: Equatable {
        /// `Any?` rather than a generic parameter bound to `any ButtonStyle`,
        /// and that is load-bearing rather than laziness: inside a generic whose
        /// parameter is an existential, `type(of:)` answers the EXISTENTIAL
        /// metatype — `(any ButtonStyle).self` for every style alike — so the
        /// comparison below would report two unrelated styles as the same type
        /// and lose the floor entirely. Through `Any` it answers the dynamic
        /// type, which is what `styleToken(_:)` took before it and why it took
        /// it. (`ThemeStyleMemoTests` swaps two styles that cannot be compared
        /// by value, which is the arm where only the type answers.)
        let style: Any?

        init(_ style: Any?) {
            self.style = style
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs.style, rhs.style) {
            case (nil, nil):
                true
            case (let lhs?, let rhs?):
                // `isEqual(to:)` opens the first existential so `Self` is
                // concrete and downcasts the second to it — the type check is
                // therefore already inside it, and stands alone only for the
                // style that cannot be compared at all.
                type(of: lhs) == type(of: rhs)
                    && ((lhs as? any Equatable).map { $0.isEqual(to: rhs) } ?? true)
            default:
                false
            }
        }
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
        // What is noted is the theme's INPUTS, never the `environment.palette`
        // assembled below: with a tint that slot holds a `TintedPalette`, and
        // the tint is noted on a slot of its own, so the BASE palette is the
        // whole of the rest of that question.
        //
        // `note` takes `some Equatable` rather than `Any`, which is the point
        // and not a tidy-up. `noteAppliedEnvironment` answers `.incomparable`
        // for a value it cannot compare, this site matches only `.changed`, and
        // dropping `.incomparable` here does NOT decline the memo below (that is
        // `EnvironmentModifier`'s arm, and it has no counterpart here) — it
        // deadens the slot permanently, so it can never answer `.changed` again
        // and the subtree keeps the ink it was painted with. Taking a value the
        // compiler knows is `Equatable` makes `.incomparable` unreachable here
        // instead of unhandled, and makes a future note of a value that cannot
        // be compared a build error rather than silently wrong pixels.
        //
        // `theme.palette` is what needed the wrapper: it is `any Palette`, and
        // `Palette` carries no `Equatable` refinement — the shape ``ThemingGuide``
        // tells an app to write conforms to neither. `ComparablePalette` asks
        // `isSamePalette(as:)`, which is the id first, then by value where the
        // palette can answer, and through the derivation for the framework's own
        // wrappers. That is the same comparison `EnvironmentSnapshot` already
        // makes at the root, and it keeps memoization alive under a custom
        // palette instead of switching it off.
        //
        // The three control styles are the same shape of question and get the
        // same shape of answer — `ComparableStyle`, the type first and then by
        // value where the style can answer.
        if let cache = context.renderCache {
            var changed = false
            var movedCells = false
            func note(
                _ value: some Equatable, _ keyPath: PartialKeyPath<EnvironmentValues>,
                movesCells: Bool = false
            ) {
                if case .changed = cache.noteAppliedEnvironment(
                    value, identity: context.identity, keyPath: keyPath,
                    depth: context.environmentApplicationDepth)
                {
                    changed = true
                    movedCells = movedCells || movesCells
                }
            }
            note(theme.appearance, \EnvironmentValues.appearance)
            note(ComparablePalette(theme.palette), \EnvironmentValues.palette)
            note(theme.tint, \EnvironmentValues.tint)
            note(theme.styles, \EnvironmentValues.styleCascade, movesCells: true)
            note(ComparableStyle(theme.buttonStyle), \EnvironmentValues.buttonStyle, movesCells: true)
            note(ComparableStyle(theme.listStyle), \EnvironmentValues.listStyle, movesCells: true)
            note(ComparableStyle(theme.pickerStyle), \EnvironmentValues.pickerStyle, movesCells: true)
            note(theme.indicatorAnimationSpeeds, \EnvironmentValues.indicatorAnimationSpeeds)
            if changed {
                // Most of a theme is ink, and ink keeps the sizes below it, as
                // `TintModifier` and `_StyleEnvironmentView` keep theirs. The
                // control styles and the style cascade are NOT ink: a plain
                // button has neither brackets nor padding, and a cascaded
                // `textCase` turns "ß" into "SS". Kept across one of those, a
                // memoized size is the old style's size, laid out as the new one.
                cache.clearAffected(by: context.identity, keepingSizes: !movedCells)
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
        if !theme.indicatorAnimationSpeeds.isEmpty {
            environment.indicatorAnimationSpeeds = Self.applying(
                theme.indicatorAnimationSpeeds, to: environment.indicatorAnimationSpeeds)
        }
        var modified = context.withEnvironment(environment)
        modified.environmentApplicationDepth += 1
        return modified
    }
}

extension ThemeModifier {
    /// `inherited`, with `entries` set over it broadest first: the entry naming the
    /// most kinds before the ones naming fewer, and entries naming as many kinds in
    /// the order they are written. The speed counterpart of the specificity order
    /// the theme's scoped styles are installed in.
    static func applying(
        _ entries: [IndicatorAnimationSpeeds.Entry], to inherited: IndicatorAnimationSpeeds
    ) -> IndicatorAnimationSpeeds {
        let ordered = entries.enumerated().sorted { lhs, rhs in
            let lhsKinds = lhs.element.indicators.rawValue.nonzeroBitCount
            let rhsKinds = rhs.element.indicators.rawValue.nonzeroBitCount
            return lhsKinds != rhsKinds ? lhsKinds > rhsKinds : lhs.offset < rhs.offset
        }
        var speeds = inherited
        for (_, entry) in ordered {
            speeds.set(entry.speed, for: entry.indicators)
        }
        return speeds
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

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension ThemeModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<V: View>(_ view: V) -> any View {
        ThemeModifier<V>(content: view, theme: theme)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension ThemeModifier: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension ThemeModifier: GridRowProviding where Content: GridRowProviding {}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension ThemeModifier: DrawsContentUnchanged {}
