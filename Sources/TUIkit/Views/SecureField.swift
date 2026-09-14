//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// | Home / Ctrl+A | Move cursor to start |
/// | End / Ctrl+E | Move cursor to end |
/// | Option+Ctrl+A | Select all |
/// | Ctrl+C / Ctrl+X | Nothing — see below |
/// | Ctrl+V | Paste at cursor |
/// | Enter | Trigger onSubmit action |
///
/// ## The contents never leave the field
///
/// Cut and copy are refused, as they are in SwiftUI ("prevents anyone from
/// cutting or copying the field's contents") and in AppKit's
/// `NSSecureTextField`. Masking alone would not achieve that: the bullets are
/// drawn at render time and the field holds the real string, so a copy would
/// have handed the password to `pbcopy`. Paste still works — the promise is
/// one-directional, and pasting in is how a password manager fills the field.
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
    /// Creates a secure field with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(titleKey.localized, text: text)
    }

    /// Creates a secure field with a localized label and a prompt.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(titleKey.localized, text: text, prompt: prompt)
    }

    /// Creates a secure field with a text label generated from a title string.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The title of the secure field, describing its purpose.
    ///   - text: The text to display and edit.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
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
    /// Generic over `StringProtocol` for the same reason as
    /// ``init(_:text:)-(S,_)``. Only the title is a key: `prompt` is already a
    /// ``Text``, which did its own lookup where it was written.
    ///
    /// - Parameters:
    ///   - title: The title of the secure field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the secure field.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
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
        // parent (e.g. HStack) allocates the field accurately. A `.plain` field
        // draws no caps; the count comes from the style through the one helper
        // both passes use.
        let capWidth = FieldChrome.width(for: context.environment.textFieldStyle)
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
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette
        let cursorStyle = context.environment.textCursorStyle

        // SecureField expands to fill available width, less whatever chrome the
        // style draws (two cap cells, or none for `.plain`).
        let chrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: false, on: context.environment.surfaceBackground)
        let contentWidth = max(minContentWidth, context.availableWidth - chrome.width)

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
        // The one place secure fields diverge from plain ones: no extraction.
        handler.isSecure = true
        // Compose the per-field closure with any cascading `.onSubmit(of:)` that
        // matches this field's role (see TextField for the rationale; stays nil
        // when empty so Return can fall through).
        handler.onSubmit = combinedSubmitAction(
            perField: onSubmitAction,
            cascading: context.environment.submitActions,
            role: context.environment.submitTriggerRole)
        handler.textContentType = context.environment.textContentType
        handler.clampCursorPosition()

        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        // Return submits, when the caller gave it something to submit to.
        FocusRegistration.publishActivationLabel(
            onSubmitAction != nil
                ? LocalizationService.shared.string(for: LocalizationKey.StatusBar.submit) : nil,
            context: context, isFocused: isFocused)

        // Hover state persists across renders; the dispatcher
        // flips it on .entered / .exited events synthesised
        // from motion. Disabled / focused fields suppress the
        // visual effect — same suppression as TextField.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        // Build the secure field content using shared renderer
        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.secureField)])
        let renderer = TextFieldContentRenderer(
            prompt: prompt,
            isDisabled: isDisabled,
            displayCharacter: { _ in TerminalSymbols.maskBullet },
            surface: chrome.surface,
            contentForeground: cascaded.foreground,
            cursorSpeed: context.environment.indicatorAnimationSpeeds.speed(for: .textCursor)
        )

        let fieldContent = renderer.buildContent(
            text: text.wrappedValue,
            cursorPosition: handler.cursorPosition,
            selectionRange: handler.selectionRange,
            isFocused: isFocused,
            palette: palette,
            cursorStyle: cursorStyle,
            cursorTimer: context.environment.cursorTimer,
            cursorTiming: context.environment.indicatorCycleTiming,
            contentWidth: contentWidth
        )

        // The caps are half-block glyphs painted in the field surface — they
        // read as the field's rounded ends on any palette, and hover tints them
        // toward the accent so the affordance reads as "I'm clickable", the same
        // visual language as TextField. A focused field shows the bump too —
        // focus is drawn by the caret, not by the caps, so the two never ask
        // for the same cell. A `.plain` field has no caps at all.
        let hoveredChrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: isHovered, on: context.environment.surfaceBackground)
        var buffer = FrameBuffer(
            text: hoveredChrome.open + fieldContent.line + hoveredChrome.close)

        // The caret animates itself — see the note in TextField. Past the
        // opening cap, which is the only chrome before the content.
        if !context.isMeasuring, let caret = fieldContent.caret {
            buffer.animatedCells = [caret.shifted(byX: chrome.leadingCells, y: 0)]
        }

        // The content's translucent colours, shifted by exactly what the caret is
        // shifted by — both are in the content's own frame, and the opening cap is
        // the only chrome before it. A faded `.textFieldTextStyle` foreground, or a
        // theme that faded the field surface, arrives here rather than being spent
        // on the escape. §30.
        buffer.opacityRegions += fieldContent.claims.map {
            $0.shifted(byX: chrome.leadingCells, y: 0)
        }
        // The caps, which the content renderer knows nothing about — `hoveredChrome`'s,
        // because that is the chrome actually drawn, and asked of the finished line's
        // width because the trailing cap sits at its end. `TextField`'s twin, through
        // the same `FieldChrome.claims(lineWidth:)`: this file and that one have
        // drifted before, which is why the arithmetic is not repeated in either.
        buffer.opacityRegions += hoveredChrome.claims(lineWidth: buffer.width)

        // Mouse: click focuses the field and drops the caret at the clicked
        // column (masked cells map to indices just like TextField); dragging
        // selects. Hover rides on the same region. Shared with TextField.
        if !isDisabled {
            TextFieldMouseHandler.register(
                buffer: &buffer,
                context: context,
                handler: handler,
                persistedFocusID: persistedFocusID,
                hoverBox: hoverBox,
                contentWidth: contentWidth,
                displayCharacter: { _ in TerminalSymbols.maskBullet },
                leadingCapWidth: chrome.leadingCells)
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
