//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// | `.switch` | A two-position switch — a coloured track with a knob |
///
/// > Note: `.automatic` and `.checkbox` both draw a checkbox. `.switch` does
/// > NOT — it draws a two-position switch: a coloured track with a two-cell
/// > knob on the side it points to, over a distinct background. `_ToggleCore`
/// > branches on `is SwitchToggleStyle` to pick it. The *glyphs* of the
/// > checkbox (■/□ or ⬛︎/⬜︎ or `[x]`/`[ ]` — see `ToggleCharacterSet`) are a separate,
/// > TUI-specific choice — see ``ToggleCharacterSet`` and
/// > ``View/toggleCharacterSet(_:)``.
///
/// ## Custom styles
///
/// Conform to `ToggleStyle` and implement ``makeBody(configuration:)`` to draw a
/// toggle however you like (a different glyph, an `ON`/`OFF` word, …). The
/// built-in styles above don't implement `makeBody` — they render procedurally
/// (with the focus glow and ``ToggleCharacterSet`` glyphs); only custom styles use it.
///
/// ## Styles and the render cache
///
/// ``View/toggleStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all.
///
/// All three built-in styles are therefore `Equatable`. Without that, a single
/// `.toggleStyle(...)` turned the cache off for everything below it — the
/// toggle's label, and whatever ``Toggle/toggleContent(_:)`` puts under it. None
/// of them holds anything, so `==` within a type is vacuously true and every
/// instance of one styles a toggle identically. Between types it is the
/// downcast in the comparison that answers, which is what a toggle needs: the
/// style's dynamic type is the whole of what it contributes to the drawing, so
/// a checkbox replaced by a switch must read as a change, and does.
///
/// A custom style need not conform: one that does not simply turns memoization
/// off below itself, which costs render time rather than correctness.
///
/// - Note: SwiftUI's toggle styles declare no such conformance, and this is one
///   of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
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
/// In TUIkit this is a checkbox; its glyphs come from ``ToggleCharacterSet`` (■/□ by default; ⬛︎/⬜︎ under Terminal.app
/// by default).
///
/// `Equatable` for the reason given under ``ToggleStyle``: a memo below a value
/// the render cache cannot compare declines to cache. It holds nothing, so
/// every instance styles a toggle identically.
public struct DefaultToggleStyle: ToggleStyle, Equatable {
    public init() {}
}

/// A toggle style that displays a checkbox followed by its label.
///
/// ```
/// □ Label     (OFF)
/// ■ Label     (ON)
/// ```
///
/// The checkbox glyphs are configurable via ``ToggleCharacterSet`` (e.g.
/// `.toggleCharacterSet(.ascii)` for `[ ]` / `[x]`).
///
/// `Equatable` on the same terms as ``DefaultToggleStyle``, and the two draw the
/// same checkbox, so the worst a comparison between them can do is drop a cache
/// entry that would have been good.
public struct CheckboxToggleStyle: ToggleStyle, Equatable {
    public init() {}
}

/// A toggle style that displays the toggle as a two-position switch.
///
/// In TUIkit this renders a coloured track with a two-cell knob on the side the
/// switch points to — left for off, right for on — over a distinct background
/// (the accent colour when on), so it reads as a switch rather than a checkbox.
///
/// Off, the track is the palette's tertiary foreground tone, moved as little as it
/// takes to stand off both the page, which the knob is drawn in, and the accent. A
/// disabled switch fades that track halfway toward the page.
///
/// `Equatable` on the same terms as ``DefaultToggleStyle``, and this is the one
/// whose type changes what gets drawn: `_ToggleCore` picks the track over the
/// checkbox on `is SwitchToggleStyle` alone. A frame that swaps a checkbox style
/// for this one is a change, and the comparison's downcast is what says so.
public struct SwitchToggleStyle: ToggleStyle, Equatable {
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
    /// > Note: In TUIkit this draws a coloured track with a two-cell knob, not
    /// > a checkbox.
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

// MARK: - Environment Key

/// Environment key for toggle style.
private struct ToggleStyleKey: EnvironmentKey {
    static let defaultValue: any ToggleStyle = DefaultToggleStyle()
}

extension EnvironmentValues {
    /// The toggle style for this environment.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``ToggleStyle``.
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
    /// > Note: `.automatic` and `.checkbox` draw a checkbox, whose glyphs are set
    /// > separately via ``ToggleCharacterSet``; `.switch` draws a two-position
    /// > switch, a coloured track with a knob on the side it points to.
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
/// □ Label     (OFF - dimmed)
/// ■ Label     (ON - accent color)
/// ```
///
/// The checkbox glyphs are configurable — see ``ToggleCharacterSet``.
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
/// > Note: In TUIkit `.automatic` and `.checkbox` draw a checkbox; `.switch`
/// > draws a two-position switch.
///
/// ## Inside a pop-up menu
///
/// A toggle written inside a pop-up ``Menu`` or a `.contextMenu` is a menu ROW,
/// not a checkbox drawn in a column of rows: it takes the row's own look — the
/// highlight bar spanning the menu's interior, the key-equivalent column at the
/// trailing edge, the hover wash — with its on/off mark where a `Button` row has
/// nothing. That is SwiftUI's shape as well, and it is what makes it reachable:
/// a pop-up's rows are not focus stops, they are ordinals claimed from the menu,
/// and a control that does not claim one draws on a line the arrows and the
/// click map both walk past. Choosing the row flips the binding and closes the
/// menu; ``View/menuActionDismissBehavior(_:)`` set to `.disabled` is what makes
/// it a sticky toggle instead.
///
/// Two things have no row to draw into and so do not apply there: a custom
/// ``ToggleStyle`` (a menu draws menu items, as SwiftUI's does) and
/// ``Toggle/toggleContent(_:)`` (a menu row is one row; put the controls it
/// governs on the page). An INLINE menu is unaffected — its rows really are page
/// focus stops, so a toggle in one is the ordinary control.
public struct Toggle<Label: View>: View {
    // Declared so a toggle titled with a string has no padding: the per-pass
    // memos key a view by its raw bytes, and padding is whatever the memory
    // held before. The two word-sized fields, then the label, then the flag —
    // which fills the byte a `Text` label ends one short of — and the 106-byte
    // binding last: none over a `Text` (208 → 194 bytes;
    // `ControlLayoutPaddingTests`). Another label's size can still leave a
    // gap before the binding.

    /// The unique focus identifier.
    var focusID: String?

    /// Builds the controls this toggle governs, drawn under it — `nil` for a
    /// toggle that governs nothing but its own value. See
    /// ``Toggle/toggleContent(_:)``.
    var content: (@MainActor () -> AnyView)?

    /// The label view.
    let label: Label

    /// Whether the toggle is disabled.
    var isDisabled: Bool

    /// The binding to the toggle's boolean state.
    let isOn: Binding<Bool>

    public var body: some View {
        _ToggleCore(
            focusID: focusID,
            content: content,
            label: label,
            isDisabled: isDisabled,
            isOn: isOn
        )
    }
}

// MARK: - Toggle Initializers (String Label)

extension Toggle where Label == Text {
    /// Creates a toggle with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the toggle's label.
    ///   - isOn: A binding to the toggle's boolean state.
    public init(
        _ titleKey: LocalizedStringKey,
        isOn: Binding<Bool>
    ) {
        self.init(titleKey.localized, isOn: isOn)
    }

    /// Creates a toggle with a string label, displayed as written.
    ///
    /// - Parameters:
    ///   - title: The toggle's label text.
    ///   - isOn: A binding to the toggle's boolean state.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        isOn: Binding<Bool>
    ) {
        self.isOn = isOn
        self.label = Text(String(title))
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.content = nil
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
        self.content = nil
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

    /// The controls this toggle governs, drawn under it and live only while it
    /// is on.
    ///
    /// ```swift
    /// Toggle("Edge lines", isOn: $edgeLines)
    ///     .toggleContent {
    ///         Slider(value: $threshold, in: 0.3...2.0, step: 0.1) { Text("Threshold") }
    ///     }
    /// ```
    ///
    /// ```
    ///   ■ Edge lines
    ///     Threshold ◀ ━━━━━━●──────── ▶ 0.9
    /// ```
    ///
    /// A switch that turns something on nearly always has that something's
    /// settings beside it, and stacking them by hand gets the two things this
    /// does right wrong: the indent has to be the INDICATOR's width, which is
    /// a `ToggleCharacterSet` resolved against the terminal at render time
    /// (`■` is one cell, `⬛︎` two, `[x]` three) — a hardcoded two lines the
    /// content up under the box on some terminals and under the label on
    /// others. And the content has to be disabled while the toggle is off, or
    /// the keyboard walks into settings for something that is not happening.
    ///
    /// The content is always DRAWN, on or off, so the rows below the toggle do
    /// not move as it is flipped. What changes is whether it is live — and a
    /// disabled control is not a focus stop, so **Tab** from the toggle reaches
    /// its content exactly when that content applies. Same shape, and the same
    /// reasoning, as ``RadioButtonItem``'s per-option content.
    ///
    /// - Note: A custom ``ToggleStyle`` draws its own indicator, and there is
    ///   nothing there for this to measure, so content under one is not
    ///   indented.
    ///
    /// - Parameter content: The controls this toggle governs.
    /// - Returns: A toggle that carries `content` beneath it.
    @MainActor
    public func toggleContent<Content: View>(
        @ViewBuilder _ content: @escaping () -> Content
    ) -> Toggle {
        var copy = self
        copy.content = { AnyView(content()) }
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
