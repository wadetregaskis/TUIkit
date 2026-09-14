//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// | Ctrl+A | Start of line |
/// | Ctrl+E | End of line |
/// | Option+Ctrl+A | Select all |
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

    /// Action fired when editing begins (`true`) and ends (`false`).
    var onEditingChangedAction: ((Bool) -> Void)?

    /// Set when the field edits a typed value rather than a `String` — see
    /// ``init(value:format:prompt:label:)``. `text` is then unused: the string
    /// being edited is a draft the bridging view holds, not the caller's.
    var formatting: _FieldValueFormatting?

    @ViewBuilder
    public var body: some View {
        if let formatting {
            _FormattedFieldBody(
                formatting: formatting,
                prompt: prompt,
                label: label,
                focusID: focusID,
                isDisabled: isDisabled,
                onSubmitAction: onSubmitAction,
                onEditingChangedAction: onEditingChangedAction
            )
        } else {
            _TextFieldCore(
                label: label,
                text: text,
                prompt: prompt,
                focusID: focusID,
                isDisabled: isDisabled,
                onSubmitAction: onSubmitAction,
                onEditingChangedAction: onEditingChangedAction
            )
        }
    }
}

// MARK: - TextField Initializers (Label == Text)

extension TextField where Label == Text {
    /// Creates a text field with a localized label.
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

    /// Creates a text field with a localized label and a prompt.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(titleKey.localized, text: text, prompt: prompt)
    }

    /// Creates a text field with a text label generated from a title string.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
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
        self.onEditingChangedAction = nil
        self.formatting = nil
    }

    /// Creates a text field with a prompt.
    ///
    /// Generic over `StringProtocol` for the same reason as
    /// ``init(_:text:)-(S,_)``. Only the title is a key: `prompt` is already a
    /// ``Text``, which did its own lookup where it was written.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the text field.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
        self.label = Text(title)
        self.text = text
        self.prompt = prompt
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
        self.onEditingChangedAction = nil
        self.formatting = nil
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
        self.onEditingChangedAction = nil
        self.formatting = nil
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

    /// Adds an action fired when editing begins and ends: `true` as the
    /// field gains focus, `false` as it loses it.
    ///
    /// The `false` call is the "editing ended" commit point — a combo box
    /// records the entered value to its recents there, so a value that
    /// applied live isn't lost just because the user tabbed away instead of
    /// pressing Enter.
    ///
    /// (SwiftUI carries this signal as the classic
    /// `TextField(_:text:onEditingChanged:)` initializer parameter; TUIkit
    /// exposes it as a modifier, per its modifier-first convention for
    /// options beyond the core SwiftUI signatures.)
    ///
    /// - Parameter action: Receives `true` when editing begins, `false` when
    ///   it ends.
    /// - Returns: A text field that reports editing transitions.
    public func onEditingChanged(_ action: @escaping (Bool) -> Void) -> TextField {
        var copy = self
        copy.onEditingChangedAction = action
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
    let onEditingChangedAction: ((Bool) -> Void)?

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
        // parent (e.g. HStack) allocates the field accurately. A `.plain` field
        // draws no caps, so they cost nothing — the number comes from the style
        // in both passes, through the one helper, so they cannot disagree.
        let capWidth = FieldChrome.width(for: context.environment.textFieldStyle)
        let proposedTotal = proposal.width ?? (defaultContentWidth + capWidth)
        return ViewSize(
            width: max(minContentWidth + capWidth, proposedTotal),
            height: 1,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    private typealias StateIndex = TextFieldStateIndex

    /// What Return does to this field, for the status bar — `nil` when the
    /// caller gave it nothing to submit to, which is what suppresses the entry.
    ///
    /// A property rather than a `let` in `renderToBuffer`: resolving it inline
    /// took that function to 101 lines against SwiftLint's 100-line ceiling,
    /// and the lookup is a self-contained question about this field anyway.
    private var submitVerb: String? {
        guard onSubmitAction != nil else { return nil }
        return LocalizationService.shared.string(for: LocalizationKey.StatusBar.submit)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette
        let cursorStyle = context.environment.textCursorStyle

        // TextField expands to fill available width, less whatever chrome the
        // style draws (two cap cells, or none for `.plain`).
        let chrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: false, on: context.environment.surfaceBackground)
        let contentWidth = max(minContentWidth, context.availableWidth - chrome.width)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "textfield", propertyIndex: StateIndex.focusID)

        let handler = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            isDisabled: isDisabled,
            context: context)
        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        FocusRegistration.publishActivationLabel(submitVerb, context: context, isFocused: isFocused)

        // Hover state persists across renders; the dispatcher
        // flips it on .entered / .exited events synthesised from
        // motion. Disabled fields suppress the visual effect.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

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
        // Identity: a text field draws what was typed. Written out rather than
        // passed as `{ $0 }` so the secure field's bullet has a visible twin.
        let displayCharacter: (Character) -> Character = { $0 }
        let renderer = TextFieldContentRenderer(
            prompt: prompt,
            isDisabled: isDisabled,
            displayCharacter: displayCharacter,
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
            contentWidth: textWidth
        )

        // The caps are half-block glyphs painted in the field surface — they
        // read as the field's rounded ends on any palette. Hover tints them
        // toward the accent so the affordance reads as "I'm clickable" without
        // mimicking the focused look (a focused field signals through its
        // caret, from the text renderer rather than the caps). A `.plain` field
        // has neither cap; `hoveredChrome` is the same chrome the width above
        // came from, re-derived with the hover tint.
        let hoveredChrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: isHovered, on: context.environment.surfaceBackground)

        // The ▾/▴ combo-box affordance sits inside the field surface, against
        // the trailing cap.
        let disclosure = Self.disclosureGlyph(
            isOpen: suggestionMenu?.isOpen, palette: palette, surface: chrome.surface)
        var buffer = FrameBuffer(
            text: hoveredChrome.open + fieldContent.line + disclosure.text
                + hoveredChrome.close)

        // The caret animates itself: its cells go to the run loop, which
        // repaints them on the cursor clock without re-rendering anything. Past
        // the opening cap, which is the only chrome before the content. See
        // ``AnimatedCellRun``.
        if !context.isMeasuring, let caret = fieldContent.caret {
            buffer.animatedCells = [caret.shifted(byX: chrome.leadingCells, y: 0)]
        }

        Self.attachFieldClaims(
            to: &buffer, content: fieldContent.claims, chrome: hoveredChrome,
            disclosure: disclosure.claims, contentStart: chrome.leadingCells,
            textWidth: textWidth)

        // Mouse: click focuses the field and drops the caret at the clicked
        // column; dragging selects. Hover rides on the same region. Shared with
        // SecureField. No-op while measuring or disabled.
        if !isDisabled {
            Self.attachMouse(
                to: &buffer, context: context, handler: handler,
                persistedFocusID: persistedFocusID, hoverBox: hoverBox, chrome: chrome,
                textWidth: textWidth, hasSuggestions: suggestionMenu != nil)
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
    /// Registers the click, drag and hover regions.
    ///
    /// The ▾ disclosure occupies the two cells between the content and the closing cap;
    /// clicks there toggle the menu, not the caret. Plus the cap itself, which is leeway
    /// rather than sloppiness: the arrow is ONE cell, the pad to its left already
    /// counts, and a pointer a single cell wide of a target that small has no way to see
    /// the miss coming. The cap is chrome with no click behaviour of its own, so nothing
    /// is taken from anything else — a press on it used to focus the field and drop the
    /// caret at the end, which is not what someone reaching for the arrow meant.
    private static func attachMouse(
        to buffer: inout FrameBuffer, context: RenderContext, handler: TextFieldHandler,
        persistedFocusID: String, hoverBox: StateBox<Bool>, chrome: FieldChrome,
        textWidth: Int, hasSuggestions: Bool
    ) {
        let leading = chrome.leadingCells
        let disclosureRange: Range<Int>? =
            hasSuggestions
            ? (leading + textWidth)..<(leading + textWidth + 2 + chrome.trailingCells) : nil
        TextFieldMouseHandler.register(
            buffer: &buffer,
            context: context,
            handler: handler,
            persistedFocusID: persistedFocusID,
            hoverBox: hoverBox,
            contentWidth: textWidth,
            // A text field draws what was typed. Written out here rather than threaded
            // through as a ninth parameter, and the secure field's bullet is the visible
            // twin of this line.
            displayCharacter: { $0 },
            leadingCapWidth: leading,
            disclosureRange: disclosureRange)
    }

    /// Everything a field's line owes, in the line's own columns.
    ///
    /// Three sources, each in a different frame, which is the whole reason this is one
    /// function: the CONTENT's claims are in the content's own frame and shift by the
    /// opening cap (the only chrome before it — the same shift the caret takes); the
    /// CAPS' need the finished line's width, because the trailing one sits at its end;
    /// and the ▾'s sit past the content. A faded `.textFieldTextStyle` foreground, a
    /// theme that faded the field surface, and a faded page whose surface now carries
    /// its alpha (§39) all arrive here rather than being spent on the escape.
    private static func attachFieldClaims(
        to buffer: inout FrameBuffer, content: [OpacityRegion], chrome: FieldChrome,
        disclosure: [OpacityRegion], contentStart: Int, textWidth: Int
    ) {
        buffer.opacityRegions += content.map { $0.shifted(byX: contentStart, y: 0) }
        buffer.opacityRegions += chrome.claims(lineWidth: buffer.width)
        buffer.opacityRegions += disclosure.map {
            $0.shifted(byX: contentStart + textWidth, y: 0)
        }
    }

    /// The combo box's ▾/▴ affordance, drawn inside the field surface against
    /// the trailing cap, or `""` when the field has no suggestion menu.
    private static func disclosureGlyph(
        isOpen: Bool?, palette: any Palette, surface: Color?
    ) -> ClaimingRow {
        var row = ClaimingRow()
        guard let isOpen else { return row }
        let caret = isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret
        // Two cells — a pad and the arrow — in one run, which is what it always
        // emitted; `ClaimingRow` adds the claim its colours owe and states them
        // opaquely. Both can be faded: the ink is `foregroundSecondary` and the field
        // is the derived field surface.
        row.append(
            " " + caret, cells: 2, ink: palette.foregroundSecondary, field: surface)
        return row
    }
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
        // Compose the per-field closure with any cascading `.onSubmit(of:)` in
        // scope that matches this field's role (.text by default). Stays nil when
        // there's nothing to run, so Return still falls through to a dialog's
        // default button.
        handler.onSubmit = combinedSubmitAction(
            perField: onSubmitAction,
            cascading: context.environment.submitActions,
            role: context.environment.submitTriggerRole)
        handler.onEditingChanged = onEditingChangedAction
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
