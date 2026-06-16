//  TUIKit - Terminal UI Kit for Swift
//  SecureField.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - SecureField

/// A control for secure text entry, where the display masks the user's input.
///
/// Use `SecureField` when you need to collect sensitive data like passwords.
/// The field behaves identically to `TextField` but displays bullet characters
/// (●) instead of the actual text.
///
/// ## Rendering
///
/// The secure field renders masked text with a visible cursor when focused.
/// When empty and unfocused, it displays the prompt text in dim styling.
///
/// ```
/// Unfocused, empty:     Enter password...       (prompt in dim)
/// Unfocused, with text: ●●●●●●●●                (bullets)
/// Focused, empty:       ❙ █                   ❙ (cursor, bars pulse)
/// Focused, with text:   ❙ ●●●●█●●●            ❙ (bullets + cursor)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert character at cursor |
/// | Backspace | Delete character before cursor |
/// | Delete | Delete character at cursor |
/// | Left | Move cursor left |
/// | Right | Move cursor right |
/// | Home | Move cursor to start |
/// | End | Move cursor to end |
/// | Enter | Trigger onSubmit action |
///
/// # Basic Example
///
/// ```swift
/// @State var password = ""
///
/// SecureField("Password", text: $password)
/// ```
///
/// # With Prompt
///
/// ```swift
/// SecureField("Password", text: $password, prompt: Text("Required"))
/// ```
///
/// # With Submit Action
///
/// ```swift
/// SecureField("Password", text: $password)
///     .onSubmit {
///         authenticate()
///     }
/// ```
public struct SecureField<Label: View>: View {
    /// The label view describing the field's purpose.
    let label: Label

    /// The binding to the text content.
    let text: Binding<String>

    /// Optional prompt text shown when the field is empty.
    let prompt: Text?

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the secure field is disabled.
    var isDisabled: Bool

    /// Action to perform when the user submits (presses Enter).
    var onSubmitAction: (() -> Void)?

    public var body: some View {
        _SecureFieldCore(
            text: text,
            prompt: prompt,
            focusID: focusID,
            isDisabled: isDisabled,
            onSubmitAction: onSubmitAction
        )
    }
}

// MARK: - SecureField Initializers (String Label)

extension SecureField where Label == Text {
    /// Creates a secure field with a text label generated from a title string.
    ///
    /// - Parameters:
    ///   - title: The title of the secure field, describing its purpose.
    ///   - text: The text to display and edit.
    public init(_ title: String, text: Binding<String>) {
        self.label = Text(title)
        self.text = text
        self.prompt = nil
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
    }

    /// Creates a secure field with a prompt.
    ///
    /// - Parameters:
    ///   - title: The title of the secure field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the secure field.
    public init(_ title: String, text: Binding<String>, prompt: Text?) {
        self.label = Text(title)
        self.text = text
        self.prompt = prompt
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
    }
}

// MARK: - SecureField Initializers (ViewBuilder Label)

extension SecureField {
    /// Creates a secure field with a custom label.
    ///
    /// Use this initializer when you need a custom label view instead of a simple string.
    ///
    /// # Example
    ///
    /// ```swift
    /// SecureField(text: $password, prompt: Text("Required")) {
    ///     HStack {
    ///         Text("Password").bold()
    ///         Text("*").foregroundStyle(.red)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the secure field.
    ///   - label: A view that describes the purpose of the secure field.
    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.text = text
        self.prompt = prompt
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
    }
}

// MARK: - SecureField Modifiers

extension SecureField {
    /// Creates a disabled version of this secure field.
    ///
    /// - Parameter disabled: Whether the secure field is disabled.
    /// - Returns: A new secure field with the disabled state.
    public func disabled(_ disabled: Bool = true) -> SecureField {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Adds an action to perform when the user submits (presses Enter).
    ///
    /// Use this modifier to invoke an action when the user presses Enter
    /// while the secure field has focus.
    ///
    /// # Example
    ///
    /// ```swift
    /// SecureField("Password", text: $password)
    ///     .onSubmit {
    ///         authenticate()
    ///     }
    /// ```
    ///
    /// - Parameter action: The action to perform on submit.
    /// - Returns: A secure field that performs the action on submit.
    public func onSubmit(_ action: @escaping () -> Void) -> SecureField {
        var copy = self
        copy.onSubmitAction = action
        return copy
    }

    /// Sets a custom focus identifier for this secure field.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A secure field with the specified focus identifier.
    public func focusID(_ id: String) -> SecureField {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_SecureFieldCore``.
/// Lifted out of the struct to mirror the
/// ``_TextFieldCore`` arrangement and keep the indices
/// named.
private enum SecureFieldStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
}

/// Internal view that handles the actual rendering of SecureField.
private struct _SecureFieldCore: View, Renderable, Layoutable {
    let text: Binding<String>
    let prompt: Text?
    let focusID: String?
    let isDisabled: Bool
    let onSubmitAction: (() -> Void)?

    private typealias StateIndex = SecureFieldStateIndex

    /// Minimum width for the secure field content area. Small, so an explicit
    /// narrow `.frame(width:)` is honoured; unframed fields open at
    /// ``defaultContentWidth``.
    private let minContentWidth = 3

    /// Default visible width for the secure field content area when no proposal is given.
    private let defaultContentWidth = 20

    var body: Never {
        fatalError("_SecureFieldCore renders via Renderable")
    }

    /// Returns the size this secure field needs.
    ///
    /// SecureField is width-flexible: it has a minimum width but expands
    /// to fill available horizontal space in HStack.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // The rendered field is `openCap + content + closeCap`, so the total
        // width is the content width plus the two caps. Report that total so a
        // parent (e.g. HStack) allocates the field accurately.
        let capWidth = 2
        let proposedTotal = proposal.width ?? (defaultContentWidth + capWidth)
        return ViewSize(
            width: max(minContentWidth + capWidth, proposedTotal),
            height: 1,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.environment.stateStorage!
        let palette = context.environment.palette
        let cursorStyle = context.environment.textCursorStyle

        // SecureField expands to fill available width (reserve 2 chars for caps)
        let contentWidth = max(minContentWidth, context.availableWidth - 2)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "securefield",
            propertyIndex: StateIndex.focusID
        )

        // Get or create persistent handler from state storage.
        // Reuses TextFieldHandler since key handling is identical.
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<TextFieldHandler> = stateStorage.storage(
            for: handlerKey,
            default: TextFieldHandler(
                focusID: persistedFocusID,
                text: text,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value

        // Keep handler in sync with current values
        handler.text = text
        handler.canBeFocused = !isDisabled
        handler.onSubmit = onSubmitAction
        handler.textContentType = context.environment.textContentType
        handler.clampCursorPosition()

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Hover state persists across renders; the dispatcher
        // flips it on .entered / .exited events synthesised
        // from motion. Disabled / focused fields suppress the
        // visual effect — same suppression as TextField.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // Build the secure field content using shared renderer
        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.secureField)])
        let renderer = TextFieldContentRenderer(
            prompt: prompt,
            isDisabled: isDisabled,
            displayCharacter: { _, _ in TerminalSymbols.maskBullet },
            contentForeground: cascaded.foreground
        )

        let fieldContent = renderer.buildContent(
            text: text.wrappedValue,
            cursorPosition: handler.cursorPosition,
            selectionRange: handler.selectionRange,
            isFocused: isFocused,
            palette: palette,
            cursorStyle: cursorStyle,
            cursorTimer: context.environment.cursorTimer,
            contentWidth: contentWidth
        )

        // Wrap with half-block caps. Hover bumps the cap tint
        // so the affordance reads as "I'm clickable" — same
        // visual language as TextField. Focused fields don't
        // show the hover bump (focus is the more emphatic
        // signal).
        let capOpacity = isHovered
            ? ViewConstants.hoverBackground
            : ViewConstants.focusBorderDim
        let capColor = palette.accent.opacity(capOpacity)
        let openCap = ANSIRenderer.colorize(String(TerminalSymbols.openCap), foreground: capColor)
        let closeCap = ANSIRenderer.colorize(String(TerminalSymbols.closeCap), foreground: capColor)
        var buffer = FrameBuffer(text: openCap + fieldContent + closeCap)

        // Mouse: a click anywhere on the field grants it
        // focus. The same hit-test region drives the hover
        // state machine — .entered / .exited (synthesised by
        // the dispatcher) flip the hover StateBox.
        if !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            // Ask the dispatcher to enable motion reporting
            // this frame so the hover machine sees .moved
            // events.
            mouseDispatcher.requestFeature(.motion)

            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusID
            let captureHoverBox = hoverBox
            let mouseHandlerID = mouseDispatcher.register { event in
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
                    focusManager.focus(id: captureFocusID)
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
                    handlerID: mouseHandlerID,
                    focusID: persistedFocusID
                )
            )
        }

        return buffer
    }
}

extension View {
    /// Styles the masked *text* of every secure field in this view's subtree
    /// (a `.control(.secureField)`-scoped style entry).
    public func secureFieldTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.secureField), build)
    }
}
