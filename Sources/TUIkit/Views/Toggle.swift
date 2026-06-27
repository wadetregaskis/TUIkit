//  TUIKit - Terminal UI Kit for Swift
//  Toggle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ToggleStyle Protocol

/// The appearance and behavior of a toggle.
///
/// To configure the style for a single `Toggle` or for all toggle instances
/// in a view hierarchy, use the `toggleStyle(_:)` modifier.
///
/// ## Built-in Styles
///
/// | Style | Description |
/// |-------|-------------|
/// | `.automatic` | Platform default (checkbox in TUI) |
/// | `.checkbox` | Classic checkbox |
/// | `.switch` | Switch style (renders same as checkbox in TUI) |
///
/// > Note: The built-in `ToggleStyle`s render identically — a checkbox — due to
/// > terminal constraints; the API matches SwiftUI for compatibility. The
/// > *glyphs* of that checkbox (⬛/⬜ by default, or `[x]`/`[ ]`) are a separate,
/// > TUI-specific choice — see ``CheckboxStyle`` and
/// > ``SwiftUICore/View/checkboxStyle(_:)``.
///
/// ## Custom styles
///
/// Conform to `ToggleStyle` and implement ``makeBody(configuration:)`` to draw a
/// toggle however you like (a different glyph, an `ON`/`OFF` word, …). The
/// built-in styles above don't implement `makeBody` — they render procedurally
/// (with the focus glow and ``CheckboxStyle`` glyphs); only custom styles use it.
public protocol ToggleStyle: Sendable {
    /// A view representing the toggle's appearance.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a toggle.
    ///
    /// - Parameter configuration: The properties of the toggle being styled.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a toggle.
    typealias Configuration = ToggleStyleConfiguration
}

extension ToggleStyle {
    /// Default body for the built-in marker styles, which TUIkit renders
    /// procedurally rather than through `makeBody`. A custom style overrides it.
    @MainActor public func makeBody(configuration: Configuration) -> EmptyView {
        EmptyView()
    }

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any ToggleStyle` existential so ``makeBody(configuration:)`` can
    /// return its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }
}

/// The properties of a toggle, passed to a ``ToggleStyle`` so it can produce the
/// toggle's appearance.
///
/// You don't create this — TUIkit builds one per ``Toggle`` and hands it to a
/// custom style's ``ToggleStyle/makeBody(configuration:)``. Mirrors SwiftUI's
/// `ToggleStyleConfiguration` (`label`, `isOn`) plus terminal-specific focus /
/// hover / enabled flags, exactly as ``ButtonStyleConfiguration`` does, because
/// toggle rendering is procedural.
public struct ToggleStyleConfiguration {
    /// The toggle's label, type-erased.
    public let label: AnyView

    /// A binding to the toggle's on/off state. Read `isOn.wrappedValue`; write it
    /// to flip the toggle.
    public let isOn: Binding<Bool>

    /// Whether the toggle currently holds keyboard focus. (Terminal-specific
    /// addition, like ``ButtonStyleConfiguration/isFocused``.)
    public let isFocused: Bool

    /// Whether the cursor is hovering over the toggle. (Terminal-specific.)
    public let isHovered: Bool

    /// Whether the toggle is enabled. (Terminal-specific.)
    public let isEnabled: Bool
}

// MARK: - Built-in Toggle Styles

/// The default toggle style.
///
/// In TUIkit this is a checkbox; its glyphs come from ``CheckboxStyle`` (⬛/⬜
/// by default).
public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
}

/// A toggle style that displays a checkbox followed by its label.
///
/// ```
/// ⬜ Label     (OFF)
/// ⬛ Label     (ON)
/// ```
///
/// The checkbox glyphs are configurable via ``CheckboxStyle`` (e.g.
/// `.checkboxStyle(.ascii)` for `[ ]` / `[x]`).
public struct CheckboxToggleStyle: ToggleStyle {
    public init() {}
}

/// A toggle style that displays a leading label and a trailing switch.
///
/// > Note: In TUIkit, this renders identically to `CheckboxToggleStyle`
/// > due to terminal constraints. The API exists for SwiftUI compatibility.
public struct SwitchToggleStyle: ToggleStyle {
    public init() {}
}

// MARK: - ToggleStyle Static Extensions

extension ToggleStyle where Self == DefaultToggleStyle {
    /// The default toggle style.
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    /// A toggle style that displays a checkbox followed by its label.
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    /// A toggle style that displays a leading label and a trailing switch.
    ///
    /// > Note: In TUIkit, this renders identically to checkbox style.
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

// MARK: - Environment Key

/// Environment key for toggle style.
private struct ToggleStyleKey: EnvironmentKey {
    static let defaultValue: any ToggleStyle = DefaultToggleStyle()
}

extension EnvironmentValues {
    /// The toggle style for this environment.
    public var toggleStyle: any ToggleStyle {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }
}

// MARK: - Toggle Style Modifier

extension View {
    /// Sets the style for toggles within this view.
    ///
    /// Use this modifier to set a specific style for all toggles within a view:
    ///
    /// ```swift
    /// VStack {
    ///     Toggle("Option 1", isOn: $option1)
    ///     Toggle("Option 2", isOn: $option2)
    /// }
    /// .toggleStyle(.checkbox)
    /// ```
    ///
    /// > Note: In TUIkit, all `ToggleStyle`s currently render as a checkbox; the
    /// > checkbox glyphs are set separately via ``CheckboxStyle``.
    ///
    /// - Parameter style: The toggle style to use.
    /// - Returns: A view with the toggle style set.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        environment(\.toggleStyle, style)
    }

    /// Styles the *label* text of every toggle in this view's subtree (a
    /// `.control(.toggle)`-scoped style entry). The checkbox indicator is
    /// unaffected.
    ///
    /// ```swift
    /// SettingsForm().toggleTextStyle { $0.italic = true }
    /// ```
    public func toggleTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.toggle), build)
    }
}

// MARK: - Toggle

/// A control that toggles between on and off states.
///
/// You create a toggle by providing an `isOn` binding and a label:
///
/// ```swift
/// @State private var isEnabled = false
///
/// Toggle("Enable notifications", isOn: $isEnabled)
/// ```
///
/// ## Rendering
///
/// ```
/// ⬜ Label     (OFF - dimmed)
/// ⬛ Label     (ON - accent color)
/// ```
///
/// The checkbox glyphs are configurable — see ``CheckboxStyle``.
///
/// When focused, the brackets pulse in the accent color.
///
/// ## Styling
///
/// Use the `toggleStyle(_:)` modifier to customize appearance:
///
/// ```swift
/// Toggle("Option", isOn: $isOn)
///     .toggleStyle(.checkbox)
/// ```
///
/// Available styles: `.automatic`, `.checkbox`, `.switch`
///
/// > Note: In TUIkit, all styles currently render identically as checkbox
/// > due to terminal constraints.
public struct Toggle<Label: View>: View {
    /// The binding to the toggle's boolean state.
    let isOn: Binding<Bool>

    /// The label view.
    let label: Label

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the toggle is disabled.
    var isDisabled: Bool

    public var body: some View {
        _ToggleCore(
            isOn: isOn,
            label: label,
            focusID: focusID,
            isDisabled: isDisabled
        )
    }
}

// MARK: - Toggle Initializers (String Label)

extension Toggle where Label == Text {
    /// Creates a toggle with a string label.
    ///
    /// - Parameters:
    ///   - title: The toggle's label text.
    ///   - isOn: A binding to the toggle's boolean state.
    public init<S: StringProtocol>(
        _ title: S,
        isOn: Binding<Bool>
    ) {
        self.isOn = isOn
        self.label = Text(String(title))
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
    }
}

// MARK: - Toggle Initializers (ViewBuilder Label)

extension Toggle {
    /// Creates a toggle with a custom label.
    ///
    /// - Parameters:
    ///   - isOn: A binding to the toggle's boolean state.
    ///   - label: A view that describes the purpose of the toggle.
    public init(
        isOn: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) {
        self.isOn = isOn
        self.label = label()
        self.focusID = nil
        self.isDisabled = false
    }
}

// MARK: - Toggle Modifiers

extension Toggle {
    /// Creates a disabled version of this toggle.
    ///
    /// - Parameter disabled: Whether the toggle is disabled.
    /// - Returns: A new toggle with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Toggle {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this toggle.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A toggle with the specified focus identifier.
    public func focusID(_ id: String) -> Toggle {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_ToggleCore``. Lifted
/// out of the generic struct because Swift does not allow
/// static stored properties in generic types.
private enum ToggleStateIndex {
    static let focusID = 0
    static let isHovered = 1
}

/// Internal view that handles the actual rendering of Toggle.
private struct _ToggleCore<Label: View>: View, Renderable, Layoutable {
    let isOn: Binding<Bool>
    let label: Label
    let focusID: String?
    let isDisabled: Bool

    var body: Never {
        fatalError("_ToggleCore renders via Renderable")
    }

    /// Size from one render (the label is flattened into the `<mark> label` row, so
    /// its width can't be derived structurally), with flexibility taken from the
    /// label: the toggle fills its width iff its label does. The single-render
    /// fallback would size it the same, but always reports fixed — this adds the
    /// structural label probe so a flexible label still makes the toggle flexible.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        let labelFlexible = measureChild(label, proposal: proposal, context: context).isWidthFlexible
        return ViewSize(width: size.width, height: size.height, isWidthFlexible: labelFlexible)
    }

    private typealias StateIndex = ToggleStateIndex

    /// The styled checkbox indicator (⬛/⬜ by default, `[x]`/`[ ]` under
    /// `.checkboxStyle(.ascii)`) for the toggle's current state, themed for
    /// focus / hover / disabled.
    private func styledToggleIndicator(
        isOnValue: Bool, isDisabled: Bool, isFocused: Bool, isHovered: Bool, context: RenderContext
    ) -> String {
        let palette = context.environment.palette

        // Bracket color: pulsing accent when focused, the normal foreground
        // when simply unfocused, and dimmed only when actually disabled.
        // (An unfocused-but-enabled control must stay readable — dimming it
        // to the disabled style made the brackets almost invisible against
        // the terminal background.)
        let bracketColor: Color
        if isDisabled {
            bracketColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        } else if isFocused {
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
            bracketColor = SelectionIndicator.resolve(isFocused: true, context: context)
                .color(dim: dimAccent, bright: palette.accent)
        } else if isHovered {
            // Hover bumps the brackets to a partial accent tint
            // so the affordance reads without the focused pulse.
            bracketColor = palette.accent.opacity(ViewConstants.hoverBackground)
        } else {
            bracketColor = palette.foreground
        }

        // The checkbox glyphs come from the configurable ``CheckboxStyle`` (⬛/⬜
        // by default, `[x]`/`[ ]` under `.checkboxStyle(.ascii)`).
        let style = context.environment.checkboxStyle
        let mark = isOnValue ? style.onMark : style.offMark

        if style.openBracket.isEmpty {
            // Self-contained glyph (squares): its *shape* shows on/off, so its
            // colour is free to show state — accent when checked, plus the
            // focus / hover / disabled tints the brackets would otherwise carry.
            let markColor = (isOnValue && !isDisabled && !isFocused) ? palette.accent : bracketColor
            return ANSIRenderer.colorize(mark, foreground: markColor)
        }
        // Two-tone bracketed (ASCII): the brackets show focus while the
        // inner mark shows on/off (accent when checked, dimmed when
        // disabled; the OFF mark is a space, so its colour is moot).
        let contentColor: Color
        if isDisabled {
            contentColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        } else if isOnValue {
            contentColor = palette.accent
        } else {
            contentColor = palette.foreground
        }
        return ANSIRenderer.colorize(style.openBracket, foreground: bracketColor)
            + ANSIRenderer.colorize(mark, foreground: contentColor)
            + ANSIRenderer.colorize(style.closeBracket, foreground: bracketColor)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "toggle",
            propertyIndex: StateIndex.focusID
        )
        let binding = isOn
        let handler = ActionHandler(
            focusID: persistedFocusID,
            action: { binding.wrappedValue.toggle() },
            canBeFocused: !isDisabled
        )
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        let isOnValue = isOn.wrappedValue

        // Hover state — flipped by the dispatcher on .entered /
        // .exited events synthesised from motion. Suppressed
        // when focused (focus is the more emphatic affordance)
        // and when disabled.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // The built-in styles render procedurally (focus glow + `CheckboxStyle`
        // glyphs); a custom `ToggleStyle` renders through its `makeBody`. Either
        // way the interaction wiring below (focus, mouse) is the core's job.
        var buffer: FrameBuffer
        let toggleStyle = context.environment.toggleStyle
        if toggleStyle is DefaultToggleStyle || toggleStyle is CheckboxToggleStyle
            || toggleStyle is SwitchToggleStyle {
            // Render the label, keeping its colour styling. Stripping the ANSI
            // here left the label with no foreground colour at all, so it drew
            // in the terminal's default — unreadable against the themed
            // background. A disabled toggle dims its label; otherwise the label
            // inherits the normal foreground colour.
            var labelContext = context
            // Tag the label subtree so its Text resolves `.control(.toggle)` style
            // entries (e.g. `.toggleTextStyle { … }`).
            labelContext.environment.controlKind = .toggle
            if isDisabled {
                labelContext.environment.foregroundStyle =
                    palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
            }
            let labelBuffer = TUIkit.renderToBuffer(label, context: labelContext)
            let labelText = labelBuffer.lines.joined(separator: " ")

            let styledIndicator = styledToggleIndicator(
                isOnValue: isOnValue, isDisabled: isDisabled,
                isFocused: isFocused, isHovered: isHovered, context: context)

            // Combine: [indicator] label
            buffer = FrameBuffer(lines: [styledIndicator + " " + labelText])
        } else {
            let configuration = ToggleStyleConfiguration(
                label: AnyView(label),
                isOn: isOn,
                isFocused: isFocused && !isDisabled,
                isHovered: isHovered,
                isEnabled: !isDisabled)
            buffer = toggleStyle.makeBuffer(configuration: configuration, context: context)
        }

        // Hit-test region: a left-button release anywhere on the
        // toggle row flips its value, mirroring how Space / Enter
        // activate it. The same region drives the hover state
        // machine — .entered / .exited (synthesised by the
        // dispatcher) flip the hover StateBox.
        if !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            mouseDispatcher.requestFeature(.motion)
            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusID
            let toggleBinding = isOn
            let captureHoverBox = hoverBox
            let handlerID = mouseDispatcher.register { event in
                switch event.phase {
                case .entered:
                    captureHoverBox.value = true
                    return true
                case .exited:
                    captureHoverBox.value = false
                    return true
                case .pressed where event.button == .left:
                    return true
                case .released where event.button == .left:
                    focusManager?.focus(id: captureFocusID)
                    toggleBinding.wrappedValue.toggle()
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0,
                    offsetY: 0,
                    width: buffer.width,
                    height: buffer.height,
                    handlerID: handlerID,
                    focusID: persistedFocusID
                )
            )
        }

        return buffer
    }
}
