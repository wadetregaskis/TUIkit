//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ButtonStyleConfiguration

/// The properties of a button, passed to a ``ButtonStyle`` so it can
/// produce the button's appearance.
///
/// You don't create this type yourself — TUIkit constructs a configuration
/// for each ``Button`` and hands it to the active style's
/// ``ButtonStyle/makeBody(configuration:)`` method.
public struct ButtonStyleConfiguration {
    /// The button's label text.
    ///
    /// - Note: SwiftUI exposes `label` as a type-erased `View`. TUIkit's default
    ///   button label is plain text, so the configuration carries the `String`
    ///   directly for the common case. When the button was built with a
    ///   `@ViewBuilder` label (`Button(action:label:)`), this is empty and the
    ///   composed view is in ``labelView`` instead — read that when it's non-nil.
    public let label: String

    /// The composed `@ViewBuilder` label, type-erased, when the button was built
    /// with `Button(action:label:)`; `nil` for a plain string label.
    ///
    /// A custom style can place this view in its body to render an arbitrary
    /// label (styled text, a glyph + text, …). The built-in styles render it
    /// inside their chrome when present.
    public let labelView: AnyView?

    /// The semantic role of the button, if any.
    ///
    /// A style may use this to adjust its appearance — for example, the
    /// built-in styles always colour a ``ButtonRole/destructive`` button
    /// with the palette's error colour.
    public let role: ButtonRole?

    /// Whether the button is currently being pressed.
    ///
    /// - Note: Terminals have no press-and-hold gesture — a key press
    ///   triggers the action instantly — so this is always `false`. It is
    ///   kept for source compatibility with SwiftUI button styles.
    public let isPressed: Bool

    /// Whether the button currently holds keyboard focus.
    ///
    /// - Note: Terminal-specific addition. SwiftUI styles read focus from
    ///   the environment; TUIkit surfaces it directly on the configuration
    ///   because button rendering is procedural.
    public let isFocused: Bool

    /// Whether the cursor is currently hovering over the button.
    ///
    /// - Note: Terminal-specific addition. SwiftUI surfaces hover
    ///   state via the `.onHover` modifier; TUIkit surfaces it on
    ///   the configuration because button rendering is procedural,
    ///   so styles can pick up the affordance without each one
    ///   wiring its own `.onHover`. Always `false` on a disabled
    ///   button.
    public let isHovered: Bool

    /// Whether the button is enabled.
    ///
    /// - Note: Terminal-specific addition mirroring SwiftUI's `\.isEnabled`
    ///   environment value. A disabled button renders dimmed.
    public let isEnabled: Bool

    /// The button's ``KeyboardShortcut``, already resolved for this terminal
    /// (so a `⌘` shortcut appears as whatever ``EnvironmentValues/commandKey``
    /// binds it to), or `nil` when the button has none.
    ///
    /// - Note: Terminal-specific addition. AppKit draws a menu item's key
    ///   equivalent for you; here a menu-row style has to draw it, so it needs
    ///   to know. ``KeyboardShortcut/displayString`` is the printable form.
    public let keyboardShortcut: KeyboardShortcut?

    // Configurations are produced by ``Button`` during rendering, never by
    // client code — the compiler-synthesized memberwise initializer
    // (internal access level) is exactly what's needed.
}

// MARK: - ButtonStyle

/// A type that applies a custom appearance to all buttons within a view
/// hierarchy.
///
/// To configure the button style for a view, apply the
/// ``View/buttonStyle(_:)`` modifier:
///
/// ```swift
/// Button("Save") { save() }
///     .buttonStyle(.primary)
/// ```
///
/// The modifier flows through the environment, so it can also be applied to
/// a container to style every button it contains:
///
/// ```swift
/// VStack {
///     Button("One") { }
///     Button("Two") { }
/// }
/// .buttonStyle(.plain)
/// ```
///
/// ## Built-in Styles
///
/// - ``DefaultButtonStyle`` (``default``) — bracketed, accent-tinted.
/// - ``PrimaryButtonStyle`` (``primary``) — bold, emphasised.
/// - ``DestructiveButtonStyle`` (``destructive``) — error-coloured.
/// - ``SuccessButtonStyle`` (``success``) — success-coloured.
/// - ``PlainButtonStyle`` (``plain``) — no brackets, just the label.
///
/// ## Custom Styles
///
/// Conform to `ButtonStyle` and return a view from
/// ``makeBody(configuration:)``:
///
/// ```swift
/// struct LinkButtonStyle: ButtonStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         Text(configuration.label)
///             .foregroundStyle(configuration.isFocused ? .palette.accent
///                                                       : .palette.foregroundSecondary)
///     }
/// }
/// ```
///
/// - Note: The built-in styles draw terminal-specific flourishes (half-block
///   caps, a pulsing focus glow) that require procedural buffer rendering.
///   Custom styles compose ordinary TUIkit views and modifiers, which is
///   enough for colour and weight changes but cannot reproduce those
///   procedural effects.
public protocol ButtonStyle: Sendable {
    /// A view that represents the body of a button.
    associatedtype Body: View

    /// Creates a view that represents the body of a button.
    ///
    /// - Parameter configuration: The properties of the button being styled.
    /// - Returns: A view describing the button's appearance.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a button.
    typealias Configuration = ButtonStyleConfiguration
}

extension ButtonStyle {
    /// Renders this style's body for `configuration` into a frame buffer.
    ///
    /// Call sites hold the style as `any ButtonStyle`. This method opens the
    /// existential so ``makeBody(configuration:)`` can return its concrete
    /// ``Body`` type, which the renderer then resolves into a buffer.
    @MainActor
    func makeBuffer(
        configuration: Configuration,
        context: RenderContext
    ) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }
}

// MARK: - Built-in Button Styles

/// The default button style: a single-line bracketed button with an
/// accent-tinted background.
///
/// Access this style with the ``ButtonStyle/default`` static property.
public struct DefaultButtonStyle: ButtonStyle {
    /// Creates a default button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .default)
    }
}

/// A bold, emphasised button style that uses the palette's accent colour.
///
/// Access this style with the ``ButtonStyle/primary`` static property.
public struct PrimaryButtonStyle: ButtonStyle {
    /// Creates a primary button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .primary)
    }
}

/// A button style that uses the palette's error colour to signal a
/// destructive action.
///
/// Access this style with the ``ButtonStyle/destructive`` static property.
public struct DestructiveButtonStyle: ButtonStyle {
    /// Creates a destructive button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .destructive)
    }
}

/// A button style that uses the palette's success colour.
///
/// Access this style with the ``ButtonStyle/success`` static property.
public struct SuccessButtonStyle: ButtonStyle {
    /// Creates a success button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .success)
    }
}

/// A minimal button style with no brackets or background — just the label,
/// preceded by a focus indicator when focused.
///
/// Access this style with the ``ButtonStyle/plain`` static property.
public struct PlainButtonStyle: ButtonStyle {
    /// Creates a plain button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .plain)
    }
}

// MARK: - ButtonStyle Static Accessors

extension ButtonStyle where Self == DefaultButtonStyle {
    /// The default button style — a bracketed, accent-tinted button.
    public static var `default`: DefaultButtonStyle { DefaultButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// A bold, emphasised button style that uses the accent colour.
    public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    /// A button style that uses the error colour for destructive actions.
    public static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

extension ButtonStyle where Self == SuccessButtonStyle {
    /// A button style that uses the success colour.
    public static var success: SuccessButtonStyle { SuccessButtonStyle() }
}

extension ButtonStyle where Self == PlainButtonStyle {
    /// A minimal button style with no brackets or background.
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

/// A ``Link``'s style: plain, with the focus in the text rather than in front
/// of it.
///
/// Internal on purpose. The public way to choose between the two affordances is
/// ``SwiftUICore/View/linkFocusIndicator(_:)``, and SwiftUI has no `.link`
/// button style to be source-compatible with — adding one would be a public
/// name this framework would then owe forever for the sake of an internal
/// wiring detail.
struct _LinkButtonStyle: ButtonStyle {
    /// Which affordance the app asked for. Carried as a value rather than read
    /// from the environment inside the style, so the choice is made once, in
    /// `_Link`'s body, where the environment is legitimately readable.
    let indicator: LinkFocusIndicator

    func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(
            configuration: configuration,
            appearance: indicator == .bullet ? .plain : .link)
    }
}

// MARK: - Focus in the label

extension _ButtonStyleBody {
    /// A one-line label that breathes between `resting` and `bright` instead of
    /// growing a bullet beside it — see ``_ButtonAppearance/indicatesFocusInLabel``.
    @MainActor
    static func breathingLabel(
        _ text: String, style: TextStyle, resting: Color, bright: Color,
        cycle: SelectionEmphasisCycle, indicating: Bool, isMeasuring: Bool
    ) -> FrameBuffer {
        func drawn(_ colour: Color) -> String {
            var style = style
            style.foregroundColor = colour
            return ANSIRenderer.render(text, with: style)
        }
        let now = indicating ? cycle.colorNow(dim: resting, bright: bright) : resting
        var buffer = FrameBuffer(lines: [drawn(now)])
        if !isMeasuring, indicating,
            let run = cycle.run(
                dim: resting, bright: bright, offsetX: 0, offsetY: 0, draw: drawn)
        {
            buffer.animatedCells = [run]
        }
        return buffer
    }

    /// The same, for a label that is a VIEW and may therefore wrap.
    ///
    /// `lines` is called once per frame of the cycle rather than the render
    /// being recoloured after the fact, because the label's cells can carry an
    /// underline (a link's do), a symbol or bold, and a string-level recolour
    /// would have to reproduce all of it. That is `frames.count` renders of a
    /// short label, for the one control holding the focus, on the passes where
    /// it re-renders.
    @MainActor
    static func breathingLabel(
        resting: Color, bright: Color, cycle: SelectionEmphasisCycle,
        indicating: Bool, isMeasuring: Bool, lines: (Color) -> [String]
    ) -> FrameBuffer {
        let now = indicating ? cycle.colorNow(dim: resting, bright: bright) : resting
        var buffer = FrameBuffer(lines: lines(now))
        guard !isMeasuring, indicating, cycle.isAnimating else { return buffer }
        // One run per ROW: a run names a rectangle of cells on ONE line, and a
        // label may wrap onto several.
        let framed = cycle.frames.map { lines($0.color(dim: resting, bright: bright)) }
        buffer.animatedCells = buffer.lines.indices.compactMap { row in
            let rowFrames = framed.compactMap { row < $0.count ? $0[row] : nil }
            guard rowFrames.count == framed.count, let first = rowFrames.first else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: row, width: first.strippedLength,
                frames: rowFrames, clock: .cursor)
        }
        return buffer
    }
}

// MARK: - Button Appearance

/// The resolved visual parameters shared by the built-in button styles.
///
/// Framework infrastructure — built-in ``ButtonStyle`` types hand one of
/// these to ``_ButtonStyleBody`` for procedural rendering.
private struct _ButtonAppearance {
    /// The label colour, or `nil` to use the palette accent.
    var foregroundColor: Color?

    /// Whether the label is bold even when unfocused.
    var isBold: Bool

    /// Horizontal padding, in characters, inside the button.
    var horizontalPadding: Int

    /// Whether the button renders without brackets or background.
    var isPlain: Bool

    /// The variant token used to scope `.controlVariant(.button, …)` style
    /// entries (see ``Button/Variant``).
    var variant: String

    /// Whether focus is shown by breathing the LABEL rather than by a bullet
    /// in front of it — and therefore whether the two chrome cells the bullet
    /// needs are reserved at all.
    ///
    /// What a `Link` wants, and the reason it is a property here rather than a
    /// second plain style: a link is written INSIDE a sentence, and a control
    /// that reserves two columns cannot be. The bullet is the right affordance
    /// for a plain button sitting on its own line, where the reservation keeps
    /// a column of them aligned as the focus moves between them; it is the
    /// wrong one for four words in a paragraph.
    ///
    /// The breath goes in the text for the same reason the tab strip's does —
    /// see ``ActiveChipCycle``, which says it at more length.
    var indicatesFocusInLabel: Bool = false

    /// The default appearance — dimmed foreground, not bold.
    static let `default` = Self(
        foregroundColor: Color.palette.foregroundSecondary,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false,
        variant: "default"
    )

    /// The primary appearance — bold, accent-coloured.
    static let primary = Self(
        foregroundColor: Color.palette.accent,
        isBold: true,
        horizontalPadding: 1,
        isPlain: false,
        variant: "primary"
    )

    /// The destructive appearance — error-coloured.
    static let destructive = Self(
        foregroundColor: Color.palette.error,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false,
        variant: "destructive"
    )

    /// The success appearance — success-coloured.
    static let success = Self(
        foregroundColor: Color.palette.success,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false,
        variant: "success"
    )

    /// The plain appearance — no brackets, no background, no padding.
    static let plain = Self(
        foregroundColor: nil,
        isBold: false,
        horizontalPadding: 0,
        isPlain: true,
        variant: "plain"
    )

    /// The link appearance — plain, and with the focus in the text rather than
    /// in front of it, so a link occupies exactly its own words.
    ///
    /// The variant stays `"plain"`: it is the token `.controlVariant(.button, …)`
    /// scopes on, a link IS a plain button, and an app that styled plain
    /// buttons did not ask for links to fall out of that.
    static let link = Self(
        foregroundColor: nil,
        isBold: false,
        horizontalPadding: 0,
        isPlain: true,
        variant: "plain",
        indicatesFocusInLabel: true
    )
}

// MARK: - Button Style Body

/// The procedural rendering core shared by the built-in button styles.
///
/// - Important: Framework infrastructure. The built-in ``ButtonStyle`` types
///   return this from `makeBody`; it is never used directly.
private struct _ButtonStyleBody: View, Renderable {
    /// The button being styled.
    let configuration: ButtonStyleConfiguration

    /// The resolved visual parameters to draw with.
    let appearance: _ButtonAppearance

    var body: Never {
        fatalError("_ButtonStyleBody renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A `@ViewBuilder` label renders via view composition, preserving its own
        // styling; plain string labels keep the procedural path below unchanged.
        if let labelView = configuration.labelView {
            return renderViewLabel(labelView, context: context)
        }

        let palette = context.environment.palette
        let isDisabled = !configuration.isEnabled
        let isFocused = configuration.isFocused
        // Focus and hover are two different questions — where the KEYBOARD
        // goes, and where the MOUSE would — so a button that is both shows
        // both. They do not compete here because they are answered in
        // different ink: focus moves the caps (pulsing them to accent) and the
        // weight, hover moves the FACE. Disabled buttons never show hover
        // (Button._ButtonCore clamps it to false before constructing the
        // configuration).
        let isHovered = configuration.isHovered

        // A destructive role always wins on colour, matching SwiftUI, where
        // the role overrides whatever tint the style would otherwise use.
        let baseForeground: Color? =
            configuration.role == .destructive
            ? Color.palette.error
            : appearance.foregroundColor

        // Scoped style cascade for this button (.control(.button) + this style's
        // variant). The label's colour/weight inherit it as soft overrides — but
        // a destructive role's error colour stays load-bearing (not broadly
        // overridable), so it's excluded from the cascade foreground.
        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.button), .controlVariant(.button, appearance.variant)])
        let cascadeForeground: Color? =
            configuration.role == .destructive ? nil : cascaded.foreground

        // Focused buttons render bold — this replaces the old explicit "focused
        // style" that was a bold variant of the normal style. A cascade `.bold`
        // (e.g. `.buttonTextStyle { $0.bold = true }`) adds to that.
        let isBold = appearance.isBold || isFocused || (cascaded.bold ?? false)

        let padding = String(repeating: " ", count: appearance.horizontalPadding)

        // Plain: focus indicator prefix + label, no brackets, no background.
        if appearance.isPlain {
            // The plain variant has no caps; chrome is the focus-indicator
            // prefix (which always reserves 2 cells — `BorderRenderer` pads
            // with spaces when unfocused so things stay aligned) plus the
            // horizontal padding either side of the label.
            let indicatorWidth =
                appearance.indicatesFocusInLabel ? 0 : BorderRenderer.focusIndicatorWidth
            let chromeWidth = indicatorWidth + 2 * appearance.horizontalPadding
            let labelText = Self.fitLabel(
                configuration.label, into: context.availableWidth, chrome: chromeWidth)
            let paddedLabel = padding + labelText + padding

            let restingColor: Color =
                isDisabled
                ? palette.foregroundTertiary.opacity(
                    ViewConstants.disabledForeground, over: palette.background)
                : (cascadeForeground?.resolve(with: palette)
                    ?? baseForeground?.resolve(with: palette) ?? palette.accent)
            // A plain button has no face to light up — no caps, no fill, it
            // draws straight onto the page — so the pointer lifts the colour it
            // already has (``Palette/hoveredForeground(_:)``), which is also
            // what gives `Link` its hover: a link IS a plain button. The lift
            // keeps whatever hue is in force, so a cascade colour or a
            // destructive role still reads as itself.
            let foregroundColor =
                isHovered ? palette.hoveredForeground(restingColor) : restingColor

            var textStyle = TextStyle()
            textStyle.foregroundColor = foregroundColor
            textStyle.isBold = isBold && !isDisabled

            // The focus indicator is handed to the run loop as a finished cycle
            // rather than re-derived every tick: the two prefix cells are the
            // ONLY thing that changes while a focused button sits still, and
            // re-rendering the screen 20 times a second to move them is what
            // made an idle page cost a third of a core. See ``AnimatedCellRun``.
            let indicating = isFocused && !isDisabled
            let cycle = context.environment.selectionEmphasis.cycle(indicating)

            // The label breathes, and nothing sits in front of it. Same clock
            // and same frames as the bullet — only the cells it lands on
            // differ, which is the whole of the difference between the two
            // affordances.
            if appearance.indicatesFocusInLabel {
                return Self.breathingLabel(
                    paddedLabel, style: textStyle, resting: foregroundColor,
                    bright: palette.accent, cycle: cycle, indicating: indicating,
                    isMeasuring: context.isMeasuring)
            }

            let prefixes = cycle.frames.map {
                BorderRenderer.focusIndicatorPrefix(
                    isFocused: indicating, emphasis: $0, palette: palette)
            }
            let styledLabel = ANSIRenderer.render(paddedLabel, with: textStyle)
            var buffer = FrameBuffer(
                lines: [prefixes[cycle.step % prefixes.count] + styledLabel])
            if cycle.isAnimating, !context.isMeasuring {
                buffer.animatedCells = [
                    AnimatedCellRun(
                        offsetX: 0, offsetY: 0,
                        width: BorderRenderer.focusIndicatorWidth,
                        frames: prefixes, clock: .cursor)
                ]
            }
            return buffer
        }

        // The standard variant wraps the label in `▐ … ▌` end caps plus
        // `horizontalPadding` cells of padding either side. If the cell
        // can't fit the full label the label is ellipsis-truncated so
        // the caps still align and the truncation is visible to the user.
        let chromeWidth = 2 + 2 * appearance.horizontalPadding  // caps + paddings
        let labelText = Self.fitLabel(
            configuration.label, into: context.availableWidth, chrome: chromeWidth)
        let paddedLabel = padding + labelText + padding

        // Standard: half-block caps around an accent-tinted
        // background. Hover bumps the tint slightly so the
        // affordance reads as "I am clickable" without the
        // pulsing animation that focus uses.
        let buttonBg = isHovered ? palette.hoveredControlFace : palette.restingControlFace

        // Label foreground: a scoped cascade colour wins (in every state);
        // otherwise the style/role's own colour is used in every state too. A
        // semantic tint — a destructive button's error red, a success button's
        // green — is load-bearing: it must not drop to a neutral grey just
        // because the button is unfocused, or `.buttonStyle(.destructive)` would
        // be indistinguishable from `.default` until focused (and a bare
        // `role: .destructive` likewise). Focus changes the *weight* (`isBold`,
        // applied below) and the caps/background pulse, not whether the tint
        // shows. The default style's own colour already IS `foregroundSecondary`,
        // so an unfocused default button still reads as a dim, recessive control.
        // Framework-chosen colours are floored (hue-preserving) against the
        // face they sit on — a mid-tone palette's secondary text over its
        // accent-tinted face can land tone-on-tone (Red Sands' parchment on
        // gold-over-brick). An explicit cascade colour is the app author's
        // and is left alone.
        let labelFg: Color
        if isDisabled {
            // Floored against the FACE, like every other framework-chosen
            // colour here. The fade is computed over the page background — the
            // recessive look this state wants — but the label is painted on
            // the button's accent tint, and unfloored the two land 1.0–1.6:1
            // apart on every built-in palette. Five of them then quantise to
            // the same 256-colour entry and the label disappears completely.
            labelFg = palette.foregroundTertiary
                .opacity(ViewConstants.disabledForeground, over: palette.background)
                .ensuringRenderedContrast(
                    atLeast: ViewConstants.disabledLabelContrastFloor, against: buttonBg)
        } else if let cascadeForeground {
            labelFg = cascadeForeground.resolve(with: palette)
        } else {
            labelFg = (baseForeground?.resolve(with: palette) ?? palette.foregroundSecondary)
                .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: buttonBg)
        }

        // Caps match the background normally, pulsing to accent when focused —
        // as a whole cycle, so the run loop can breathe those two cells without
        // re-rendering the screen. See ``ButtonCapCycle``.
        let caps = ButtonCapCycle(
            isFocused: isFocused && !isDisabled,
            background: buttonBg, accent: palette.accent, context: context)

        let openCap = ANSIRenderer.colorize(
            String(TerminalSymbols.openCap),
            foreground: caps.colorNow
        )
        let closeCap = ANSIRenderer.colorize(
            String(TerminalSymbols.closeCap),
            foreground: caps.colorNow
        )
        let styledLabel = ANSIRenderer.colorize(
            paddedLabel,
            foreground: labelFg,
            background: buttonBg,
            bold: isBold && !isDisabled
        )

        var buffer = FrameBuffer(lines: [openCap + styledLabel + closeCap])
        if !context.isMeasuring {
            buffer.animatedCells = caps.runs(width: 2 + paddedLabel.strippedLength)
        }
        return buffer
    }

    /// Renders a `@ViewBuilder` button label (``ButtonStyleConfiguration/labelView``)
    /// by composing TUIkit views, so the label's own styling and structure are
    /// preserved. A plain `Text` label still picks up the style's tint because it
    /// is rendered under a `.foregroundStyle(_:)` the explicit colours override.
    /// The procedural string path above is left untouched for string labels.
    private func renderViewLabel(_ labelView: AnyView, context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let isDisabled = !configuration.isEnabled
        let isFocused = configuration.isFocused
        // Both, for the reason given in the string path above.
        let isHovered = configuration.isHovered

        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.button), .controlVariant(.button, appearance.variant)])
        let baseForeground: Color? =
            configuration.role == .destructive ? Color.palette.error : appearance.foregroundColor
        let cascadeForeground: Color? =
            configuration.role == .destructive ? nil : cascaded.foreground

        // Computed up front so the standard path can floor its default label
        // colour against the face it sits on; the plain path ignores it.
        let buttonBg = isHovered ? palette.hoveredControlFace : palette.restingControlFace

        // Same rules as the string path: cascade wins untouched; framework
        // colours are floored against the face (see makeStandardBody).
        let labelFg: Color
        if isDisabled {
            // See makeStandardBody. Floored only for the STANDARD variant: a
            // plain button has no face, so its label sits on the page
            // background and flooring it against `buttonBg` — a fill that is
            // never drawn — would brighten it against nothing.
            let faded = palette.foregroundTertiary
                .opacity(ViewConstants.disabledForeground, over: palette.background)
            labelFg = appearance.isPlain
                ? faded
                : faded.ensuringRenderedContrast(
                    atLeast: ViewConstants.disabledLabelContrastFloor, against: buttonBg)
        } else if appearance.isPlain {
            // Ahead of the cascade branch, not after it: a plain button's only
            // affordance IS the colour of its label — no caps, no fill, it
            // draws straight onto the page — so the pointer has to be able to
            // lift whatever colour is in force, the app's included. The lift
            // keeps the hue, so the label still reads as itself.
            let resting =
                cascadeForeground?.resolve(with: palette)
                ?? baseForeground?.resolve(with: palette) ?? palette.foregroundSecondary
            labelFg = isHovered ? palette.hoveredForeground(resting) : resting
        } else if let cascadeForeground {
            labelFg = cascadeForeground.resolve(with: palette)
        } else {
            labelFg = (baseForeground?.resolve(with: palette) ?? palette.foregroundSecondary)
                .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: buttonBg)
        }

        // Plain: focus-indicator prefix + the label, no caps or background.
        if appearance.isPlain {
            let indicating = isFocused && !isDisabled
            let cycle = context.environment.selectionEmphasis.cycle(indicating)

            // The label breathes, and reserves nothing in front of itself —
            // see ``_ButtonAppearance/indicatesFocusInLabel``. Rendered once
            // per frame of the cycle rather than recoloured after the fact,
            // because the label is a VIEW: its cells can carry an underline (a
            // link's does), a symbol, or bold, and a string-level recolour
            // would have to reproduce all of it. That is `frames.count`
            // renders of a short label, for the one control that holds the
            // focus, on the passes where it re-renders.
            if appearance.indicatesFocusInLabel {
                return Self.breathingLabel(
                    resting: labelFg, bright: palette.accent.resolve(with: palette),
                    cycle: cycle, indicating: indicating, isMeasuring: context.isMeasuring
                ) { colour in
                    TUIkit.renderToBuffer(
                        labelView.foregroundStyle(colour),
                        context: context.withChildIdentity(
                            erasedType: type(of: labelView), index: 0)
                    ).lines
                }
            }

            let prefixes = cycle.frames.map {
                BorderRenderer.focusIndicatorPrefix(
                    isFocused: indicating, emphasis: $0, palette: palette)
            }
            // Under a child identity: the plain path renders the caller's
            // label directly (the standard path's HStack pushes one
            // implicitly), and at the core's identity a composite label's
            // @State landed on the focusID/isHovered slots — 778699f5's
            // collision class, missed here.
            let body = TUIkit.renderToBuffer(
                labelView.foregroundStyle(labelFg),
                context: context.withChildIdentity(erasedType: type(of: labelView), index: 0))
            var buffer = FrameBuffer(
                lines: body.lines.map { prefixes[cycle.step % prefixes.count] + $0 })
            guard !context.isMeasuring else { return buffer }
            // The label's own runs ride the prefix's width to the right; the
            // prefix repeats on every row of a multi-line label, so each row is
            // its own run.
            buffer.animatedCells = body.shiftedAnimatedCells(
                byX: BorderRenderer.focusIndicatorWidth, y: 0)
            buffer.opacityRegions = body.shiftedOpacityRegions(
                byX: BorderRenderer.focusIndicatorWidth, y: 0)
            if cycle.isAnimating {
                buffer.animatedCells += body.lines.indices.map { row in
                    AnimatedCellRun(
                        offsetX: 0, offsetY: row,
                        width: BorderRenderer.focusIndicatorWidth,
                        frames: prefixes, clock: .cursor)
                }
            }
            return buffer
        }

        // Standard: half-block caps around the background-tinted, padded label.
        // Full accent at the bright end — see the note on the compact
        // variant's cap above.
        let caps = ButtonCapCycle(
            isFocused: isFocused && !isDisabled,
            background: buttonBg, accent: palette.accent, context: context)

        let composed = HStack(spacing: 0) {
            Text(String(TerminalSymbols.openCap)).foregroundStyle(caps.colorNow)
            labelView
                .foregroundStyle(labelFg)
                .padding(.horizontal, appearance.horizontalPadding)
                .background(buttonBg)
            Text(String(TerminalSymbols.closeCap)).foregroundStyle(caps.colorNow)
        }
        var buffer = TUIkit.renderToBuffer(composed, context: context)
        guard !context.isMeasuring, caps.isAnimating else { return buffer }

        // A run has to name the row it sits on, and these caps are single-line
        // `Text`s that the HStack centres against whatever height the label
        // turns out to be — so only a one-row button can hand them over. A
        // taller label (rare, and never from the string path) keeps the old
        // cost: say the frame consulted the clock, and the loop goes on
        // rendering every tick exactly as it does today.
        if buffer.lines.count == 1 {
            buffer.animatedCells += caps.runs(width: buffer.lines[0].strippedLength)
        } else {
            context.environment.volatileReadTracker?.recordVolatileRead()
        }
        return buffer
    }

    /// Truncates a button label so it fits in `availableWidth` after
    /// reserving `chrome` cells for the button's chrome (caps + padding).
    ///
    /// Labels that already fit are returned unchanged. Labels longer than
    /// the available space are truncated to one less than their budget and
    /// suffixed with `…` so the user can see the truncation. If the cell
    /// is so narrow that even the chrome doesn't fit, the label is
    /// dropped entirely — the parent's clamping safety net will then clip
    /// the chrome itself.
    fileprivate static func fitLabel(_ label: String, into availableWidth: Int, chrome: Int) -> String {
        let labelBudget = availableWidth - chrome
        guard labelBudget > 0 else { return "" }
        let labelWidth = label.strippedLength
        if labelWidth <= labelBudget { return label }
        // truncatedToWidth places the ellipsis itself; with a tiny budget it
        // returns just `…` which still keeps the chrome aligned.
        return label.truncatedToWidth(labelBudget)
    }
}

// MARK: - Environment

/// Environment key for the button style.
private struct ButtonStyleKey: EnvironmentKey {
    static let defaultValue: any ButtonStyle = DefaultButtonStyle()
}

extension EnvironmentValues {
    /// The button style for this environment.
    ///
    /// Controls how ``Button`` views render. Set via the
    /// ``View/buttonStyle(_:)`` modifier. Default: ``DefaultButtonStyle``.
    public var buttonStyle: any ButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

// MARK: - Button Style Modifier

extension View {
    /// Sets the style for buttons within this view.
    ///
    /// Apply this modifier to a single ``Button`` or to a container to style
    /// every button it contains:
    ///
    /// ```swift
    /// Button("Delete") { delete() }
    ///     .buttonStyle(.destructive)
    /// ```
    ///
    /// - Parameter style: The button style to apply.
    /// - Returns: A view whose buttons use the specified style.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        environment(\.buttonStyle, style)
    }
}

// MARK: - Button Variants & Targeted Text Styling

extension Button {
    /// A built-in button visual variant, used to scope styling to a specific
    /// kind of button via ``View/buttonTextStyle(_:_:)``.
    public enum Variant: Sendable, Hashable {
        /// The default bracketed style (``DefaultButtonStyle``).
        case automatic
        /// The bold, accent-emphasised style (``PrimaryButtonStyle``).
        case primary
        /// The error-coloured style (``DestructiveButtonStyle``).
        case destructive
        /// The success-coloured style (``SuccessButtonStyle``).
        case success
        /// The minimal, bracket-less style (``PlainButtonStyle``).
        case plain

        /// The type-erased token stored in `.controlVariant(.button, _)`.
        var token: String {
            switch self {
            case .automatic: return "default"
            case .primary: return "primary"
            case .destructive: return "destructive"
            case .success: return "success"
            case .plain: return "plain"
            }
        }
    }
}

extension View {
    /// Styles the *text* of every button in this view's subtree (a
    /// `.control(.button)`-scoped style entry).
    ///
    /// ```swift
    /// Sidebar().buttonTextStyle { $0.bold = true; $0.foreground = .green }
    /// ```
    ///
    /// The button's structure (brackets, background, focus glow) is unchanged;
    /// only its label colour/attributes are overridden. A `.destructive` role's
    /// error colour stays load-bearing and is not overridden by a broad entry.
    public func buttonTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.button), build)
    }

    /// Styles the text of buttons of a specific ``Button/Variant`` in this
    /// view's subtree (a `.controlVariant(.button, …)`-scoped entry).
    ///
    /// ```swift
    /// RootView().buttonTextStyle(.automatic) { $0.foreground = .blue }
    /// ```
    public func buttonTextStyle(
        _ variant: Button.Variant, _ build: (inout StyleAttributes) -> Void
    ) -> some View {
        style(.controlVariant(.button, variant.token), build)
    }
}
