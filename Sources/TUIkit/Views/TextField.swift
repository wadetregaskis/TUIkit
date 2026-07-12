//  TUIKit - Terminal UI Kit for Swift
//  TextField.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TextField

/// A control that displays an editable text interface.
///
/// You create a text field with a label and a binding to a string value.
/// The text field updates this value continuously as the user types.
///
/// ## Rendering
///
/// The text field renders as `[ text content ]` with a visible cursor when focused.
/// When empty and unfocused, it displays the prompt text in dim styling.
///
/// ```
/// Unfocused, empty:     [ Enter username... ]    (prompt in dim)
/// Unfocused, with text: [ john.doe           ]   (text in normal)
/// Focused, empty:       [ █                  ]   (cursor, brackets pulse)
/// Focused, with text:   [ john.d█e           ]   (cursor in text)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert character at cursor |
/// | Backspace | Delete character before cursor |
/// | Delete | Delete character at cursor |
/// | Left / Right | Move cursor one character |
/// | Option+Left | Move cursor to the start of the current (or previous) word |
/// | Option+Right | Move cursor to the end of the current (or next) word |
/// | Home / End | Move cursor to start / end of text |
/// | Shift+Left / Shift+Right | Extend selection one character |
/// | Shift+Option+Left / Right | Extend selection to the previous / next word boundary |
/// | Ctrl+A | Select all |
/// | Ctrl+C / Ctrl+X / Ctrl+V | Copy / cut / paste |
/// | Ctrl+Z | Undo |
/// | Ctrl+U | Erase the entire field |
/// | Enter | Trigger onSubmit action |
///
/// # Basic Example
///
/// ```swift
/// @State var username = ""
///
/// TextField("Username", text: $username)
/// ```
///
/// # With Prompt
///
/// ```swift
/// TextField("Email", text: $email, prompt: Text("you@example.com"))
/// ```
///
/// # With ViewBuilder Label
///
/// ```swift
/// TextField(text: $username, prompt: Text("Required")) {
///     Text("Username").bold()
/// }
/// ```
///
/// # With Submit Action
///
/// ```swift
/// TextField("Search", text: $query)
///     .onSubmit {
///         performSearch()
///     }
/// ```
public struct TextField<Label: View>: View {
    /// The label view describing the field's purpose.
    let label: Label

    /// The binding to the text content.
    let text: Binding<String>

    /// Optional prompt text shown when the field is empty.
    let prompt: Text?

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the text field is disabled.
    var isDisabled: Bool

    /// Action to perform when the user submits (presses Enter).
    var onSubmitAction: (() -> Void)?

    public var body: some View {
        _TextFieldCore(
            label: label,
            text: text,
            prompt: prompt,
            focusID: focusID,
            isDisabled: isDisabled,
            onSubmitAction: onSubmitAction
        )
    }
}

// MARK: - TextField Initializers (Label == Text)

extension TextField where Label == Text {
    /// Creates a text field with a text label generated from a title string.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
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

    /// Creates a text field with a prompt.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the text field.
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

// MARK: - TextField Initializers (Generic Label)

extension TextField {
    /// Creates a text field with a prompt generated from a `Text` and a custom label.
    ///
    /// Use this initializer when you need a custom label view instead of a simple string.
    ///
    /// # Example
    ///
    /// ```swift
    /// TextField(text: $username, prompt: Text("Required")) {
    ///     HStack {
    ///         Text("Username").bold()
    ///         Text("*").foregroundStyle(.red)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the text field.
    ///   - label: A view that describes the purpose of the text field.
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

// MARK: - TextField Modifiers

extension TextField {
    /// Creates a disabled version of this text field.
    ///
    /// - Parameter disabled: Whether the text field is disabled.
    /// - Returns: A new text field with the disabled state.
    public func disabled(_ disabled: Bool = true) -> TextField {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Adds an action to perform when the user submits (presses Enter).
    ///
    /// Use this modifier to invoke an action when the user presses Enter
    /// while the text field has focus.
    ///
    /// # Example
    ///
    /// ```swift
    /// TextField("Search", text: $query)
    ///     .onSubmit {
    ///         performSearch()
    ///     }
    /// ```
    ///
    /// - Parameter action: The action to perform on submit.
    /// - Returns: A text field that performs the action on submit.
    public func onSubmit(_ action: @escaping () -> Void) -> TextField {
        var copy = self
        copy.onSubmitAction = action
        return copy
    }

    /// Sets a custom focus identifier for this text field.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A text field with the specified focus identifier.
    public func focusID(_ id: String) -> TextField {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_TextFieldCore``.
/// Lifted out of the generic struct because Swift does not
/// allow static stored properties in generic types.
private enum TextFieldStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
}

/// Internal view that handles the actual rendering of TextField.
private struct _TextFieldCore<Label: View>: View, Renderable, Layoutable {
    let label: Label
    let text: Binding<String>
    let prompt: Text?
    let focusID: String?
    let isDisabled: Bool
    let onSubmitAction: (() -> Void)?

    /// Minimum width for the text field content area. Small, so an explicit
    /// narrow `.frame(width:)` is honoured (e.g. a 0–255 / "100%" numeric field
    /// that only needs room for a few characters plus the cursor); fields without
    /// a frame still open at ``defaultContentWidth``.
    private let minContentWidth = 3

    /// Default visible width for the text field content area when no proposal is given.
    private let defaultContentWidth = 20

    var body: Never {
        fatalError("_TextFieldCore renders via Renderable")
    }

    /// Returns the size this text field needs.
    ///
    /// TextField is width-flexible: it has a minimum width but expands
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

    private typealias StateIndex = TextFieldStateIndex

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.environment.stateStorage!
        let palette = context.environment.palette
        let cursorStyle = context.environment.textCursorStyle

        // TextField expands to fill available width (reserve 2 chars for caps)
        let contentWidth = max(minContentWidth, context.availableWidth - 2)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "textfield",
            propertyIndex: StateIndex.focusID
        )

        let handler = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            isDisabled: isDisabled,
            context: context)
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Hover state persists across renders; the dispatcher
        // flips it on .entered / .exited events synthesised from
        // motion. Disabled fields suppress the visual effect.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // Diagnostic (TUIKIT_DEBUG_FOCUS=1): on every render, log
        // what *this* field's binding is reading, what focus it
        // has, and its identity path. When the visible bug is
        // "I typed Z into Search but it's showing up in Input",
        // the per-field render lines for the surrounding frames
        // tell us immediately whether Input's binding is actually
        // reading searchQuery's @State value, or whether the value
        // is right but landing in the wrong screen position.
        if !context.isMeasuring {
            debugFocusLog("""
                TextField render
                  focusID: \(persistedFocusID)
                  text.wrappedValue: \(text.wrappedValue.debugDescription)
                  isFocused: \(isFocused)
                  isMeasuring: \(context.isMeasuring)
                """)
        }

        // Input suggestions (``View/textInputSuggestions(_:)``): sync the
        // handler's completions and reserve two trailing columns for the ▾
        // affordance that marks the field as a combo box.
        let suggestionMenu =
            isDisabled
            ? nil
            : TextFieldSuggestions.prepare(
                entries: context.environment.textInputSuggestions,
                handler: handler,
                currentText: text.wrappedValue,
                isFocused: isFocused,
                context: context)
        let textWidth =
            suggestionMenu != nil ? max(minContentWidth, contentWidth - 2) : contentWidth

        // Build the text field content using shared renderer. The entered text
        // honours a `.control(.textField)` cascade foreground (`.textFieldTextStyle`).
        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.textField)])
        let renderer = TextFieldContentRenderer(
            prompt: prompt,
            isDisabled: isDisabled,
            displayCharacter: { index, text in
                text[text.index(text.startIndex, offsetBy: index)]
            },
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
            contentWidth: textWidth
        )

        // Wrap with half-block caps. Hover bumps the cap tint so
        // the affordance reads as "I'm clickable" without
        // mimicking the focused look (focused fields get their
        // signal from the cursor blink and the bold cap colour
        // elsewhere — TextField's focus styling comes from the
        // text renderer, not the caps).
        // The caps are half-block glyphs painted in the field surface — they
        // read as the field's rounded ends on any palette. Hover tints them
        // toward the accent so the affordance still reads as "clickable".
        let surface = palette.fieldBackground.resolve(with: palette)
        let capColor =
            isHovered
            ? Color.lerp(surface, palette.accent.resolve(with: palette), phase: 0.35)
            : surface
        let openCap = ANSIRenderer.colorize(String(TerminalSymbols.openCap), foreground: capColor)
        let closeCap = ANSIRenderer.colorize(String(TerminalSymbols.closeCap), foreground: capColor)

        // The ▾/▴ combo-box affordance sits inside the field surface, against
        // the trailing cap.
        let disclosure: String
        if let suggestionMenu {
            let caret = suggestionMenu.isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret
            disclosure = ANSIRenderer.colorize(
                " " + caret,
                foreground: palette.foregroundSecondary,
                background: surface)
        } else {
            disclosure = ""
        }
        var buffer = FrameBuffer(text: openCap + fieldContent + disclosure + closeCap)

        // Mouse: click focuses the field and drops the caret at the clicked
        // column; dragging selects. Hover rides on the same region. Shared with
        // SecureField. No-op while measuring or disabled.
        if !isDisabled {
            TextFieldMouseHandler.register(
                buffer: &buffer,
                context: context,
                handler: handler,
                persistedFocusID: persistedFocusID,
                hoverBox: hoverBox,
                contentWidth: textWidth)
        }

        if let suggestionMenu, suggestionMenu.isOpen {
            TextFieldSuggestions.attach(
                menu: suggestionMenu, to: &buffer, handler: handler, context: context)
        }

        return buffer
    }

    /// Fetches (or creates) the persistent editing handler from StateStorage
    /// — it maintains the cursor position across renders — and syncs the
    /// per-frame bindings on it.
    private func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        isDisabled: Bool,
        context: RenderContext
    ) -> TextFieldHandler {
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
        handler.text = text
        handler.canBeFocused = !isDisabled
        handler.onSubmit = onSubmitAction
        handler.textContentType = context.environment.textContentType
        handler.clampCursorPosition()
        return handler
    }
}

extension View {
    /// Styles the entered *text* of every text field in this view's subtree
    /// (a `.control(.textField)`-scoped style entry). The cursor, selection
    /// highlight, and the (dim) prompt keep their own colours.
    public func textFieldTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.textField), build)
    }
}
