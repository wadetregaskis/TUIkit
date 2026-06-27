//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Button.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Button Role

/// A value that describes the purpose of a button.
///
/// Use button roles to give buttons a semantic meaning that affects
/// their appearance and behavior. In alerts and dialogs, buttons are
/// automatically ordered based on their role.
///
/// - `cancel`: A button that cancels the current operation. Placed on the left.
/// - `destructive`: A button that deletes data or performs an irreversible action.
public struct ButtonRole: Equatable, Sendable {
    let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// A role that indicates a cancellation action.
    ///
    /// Cancel buttons are placed on the left side in alerts and dialogs.
    /// Pressing ESC triggers the cancel action if one exists.
    public static let cancel = Self("cancel")

    /// A role that indicates a destructive action.
    ///
    /// Destructive buttons are styled with the error color to indicate danger.
    /// Use for buttons that delete user data or perform irreversible operations.
    public static let destructive = Self("destructive")
}

// MARK: - Button

/// An interactive button that triggers an action when pressed.
///
/// Buttons can receive focus and respond to keyboard input (Enter or Space).
/// They display differently when focused to indicate the current selection.
///
/// ## Styling
///
/// A button's appearance is controlled by its ``ButtonStyle``, applied with
/// the ``View/buttonStyle(_:)`` modifier rather than an initializer argument —
/// mirroring SwiftUI:
///
/// ```swift
/// Button("Submit") { handleSubmit() }
///     .buttonStyle(.primary)
/// ```
///
/// The default style renders a single-line bracketed button, `▐ Label ▌`.
/// The ``PlainButtonStyle`` renders just the label with no brackets.
///
/// # Basic Example
///
/// ```swift
/// Button("Submit") {
///     handleSubmit()
/// }
/// ```
///
/// # Destructive Button
///
/// ```swift
/// Button("Delete", role: .destructive) {
///     handleDelete()
/// }
/// ```
public struct Button: View {
    /// The button's label text (used by the built-in styles' string path; empty
    /// when the button was built with a `@ViewBuilder` label — see ``labelView``).
    let label: String

    /// A composed `@ViewBuilder` label, type-erased, or `nil` for a string label.
    ///
    /// `Button` is deliberately **not** generic over its label (unlike SwiftUI's
    /// `Button<Label>`): terminal idioms collect buttons into homogeneous arrays
    /// (``ButtonRow``, ``Alert``'s `[Button]`), which a generic label type would
    /// break. Erasing the label keeps `Button` a single concrete type while still
    /// matching SwiftUI's `Button(action:label:)` call syntax.
    let labelView: AnyView?

    /// The action to perform when pressed.
    let action: () -> Void

    /// The button's semantic role.
    ///
    /// Roles affect button ordering in alerts/dialogs and can trigger
    /// automatic styling. Cancel buttons appear on the left; destructive
    /// buttons use error coloring.
    let role: ButtonRole?

    /// The unique focus identifier.
    ///
    /// If `nil`, automatically generated from the view's identity path.
    /// Use the `.focusID()` modifier to override.
    var focusID: String?

    /// Whether the button is disabled.
    ///
    /// Set with the ``disabled(_:)`` modifier.
    var isDisabled: Bool

    /// Creates a button with a label and action.
    ///
    /// - Parameters:
    ///   - label: The button's label text.
    ///   - action: The action to perform when pressed.
    public init(
        _ label: String,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.labelView = nil
        self.action = action
        self.role = nil
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
    }

    /// Creates a button with an optional role for semantic meaning.
    ///
    /// Use this initializer to create buttons with roles like `.cancel` or `.destructive`.
    /// The role affects button ordering in alerts and can influence styling.
    ///
    /// This matches the SwiftUI signature:
    /// `init(_ title: S, role: ButtonRole?, action: () -> Void)`
    ///
    /// - Parameters:
    ///   - label: The button's label text.
    ///   - role: An optional semantic role describing the button.
    ///   - action: The action to perform when pressed.
    public init(
        _ label: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.labelView = nil
        self.action = action
        self.role = role
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
    }

    /// Creates a button with a custom `@ViewBuilder` label.
    ///
    /// Mirrors SwiftUI's `Button(action:label:)`. The label can be any view
    /// (e.g. styled `Text`, or a glyph + text in an `HStack`); the built-in
    /// styles render it inside their chrome, a plain `Text` label picking up the
    /// style's tint via the foreground environment.
    ///
    /// - Parameters:
    ///   - action: The action to perform when pressed.
    ///   - label: A view builder producing the button's label.
    public init<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.label = ""
        self.labelView = AnyView(label())
        self.action = action
        self.role = nil
        self.focusID = nil
        self.isDisabled = false
    }

    /// Creates a button with a semantic role and a custom `@ViewBuilder` label.
    ///
    /// Mirrors SwiftUI's `Button(role:action:label:)`.
    ///
    /// - Parameters:
    ///   - role: An optional semantic role describing the button.
    ///   - action: The action to perform when pressed.
    ///   - label: A view builder producing the button's label.
    public init<Label: View>(
        role: ButtonRole?,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.label = ""
        self.labelView = AnyView(label())
        self.action = action
        self.role = role
        self.focusID = nil
        self.isDisabled = false
    }

    public var body: some View {
        _ButtonCore(
            label: label,
            labelView: labelView,
            action: action,
            role: role,
            focusID: focusID,
            isDisabled: isDisabled
        )
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of Button.
///
/// `_ButtonCore` owns the interactive behaviour — focus registration and
/// keyboard handling — and delegates all visual appearance to the active
/// ``ButtonStyle`` read from the environment.
private struct _ButtonCore: View, Renderable, Layoutable {
    let label: String
    let labelView: AnyView?
    let action: () -> Void
    let role: ButtonRole?
    let focusID: String?
    let isDisabled: Bool

    var body: Never {
        fatalError("_ButtonCore renders via Renderable")
    }

    private enum StateIndex {
        static let focusID = 0
        static let isHovered = 1
    }

    /// A button hugs its label (it never grows to fill), so a single render is
    /// its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Combine this button's own disabled state with the cascading
        // `.disabled(_:)` environment value (a container can disable it).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "button",
            propertyIndex: StateIndex.focusID
        )
        let handler = ActionHandler(
            focusID: persistedFocusID,
            action: action,
            canBeFocused: !isDisabled
        )
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Hover state persists across renders via StateStorage —
        // the dispatcher flips it on .entered / .exited events
        // synthesised by the hover state machine. Disabled
        // buttons never show the affordance, so clamp to false
        // when isDisabled regardless of the stored value.
        let stateStorage = context.environment.stateStorage!
        let hoverKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.isHovered
        )
        let hoverBox: StateBox<Bool> = stateStorage.storage(for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        let style = context.environment.buttonStyle
        let configuration = ButtonStyleConfiguration(
            label: label,
            labelView: labelView,
            role: role,
            isPressed: false,
            isFocused: isFocused && !isDisabled,
            isHovered: isHovered,
            isEnabled: !isDisabled
        )
        var buffer = style.makeBuffer(configuration: configuration, context: context)

        // Hit-test region for mouse clicks AND hover transitions.
        // A left-button release inside the button's bounds counts
        // as a click; .entered / .exited (synthesised by the
        // dispatcher from cursor motion) drive the hover state.
        // Disabled buttons skip registration entirely so they
        // neither steal focus nor swallow events.
        if !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            // Ask the dispatcher to enable motion reporting this
            // frame so .moved events come through and feed the
            // hover state machine.
            mouseDispatcher.requestFeature(.motion)

            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusID
            let captureAction = action
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
                    // Claim the press so the dispatcher routes the
                    // matching release back here even if the cursor
                    // drifts off the button before it lifts.
                    return true
                case .released where event.button == .left:
                    focusManager?.focus(id: captureFocusID)
                    captureAction()
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

// MARK: - Button Convenience Modifiers

extension Button {
    /// Creates a disabled version of this button.
    ///
    /// - Parameter disabled: Whether the button is disabled.
    /// - Returns: A new button with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Button {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this button.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A button with the specified focus identifier.
    public func focusID(_ id: String) -> Button {
        var copy = self
        copy.focusID = id
        return copy
    }
}
