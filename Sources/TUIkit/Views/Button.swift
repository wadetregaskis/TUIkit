//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Whether this button is a pop-up menu's trigger, and so runs its action on
    /// the PRESS rather than the release — see ``menuTrigger()``.
    ///
    /// Internal: the only thing that wants it is a menu's own collapsed control.
    var isMenuTrigger = false

    /// Creates a button with a localized label and an action.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. A `String` you computed binds to
    /// ``init(_:action:)-(S,_)`` and is shown as written.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the button's label.
    ///   - action: The action to perform when pressed.
    public init(
        _ titleKey: LocalizedStringKey,
        action: @escaping () -> Void
    ) {
        self.init(titleKey.localized, action: action)
    }

    /// Creates a button with a title and action, displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The button's label text.
    ///   - action: The action to perform when pressed.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        action: @escaping () -> Void
    ) {
        self.label = String(title)
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
    ///   - titleKey: The key for the button's label — a literal is looked up.
    ///   - role: An optional semantic role describing the button.
    ///   - action: The action to perform when pressed.
    public init(
        _ titleKey: LocalizedStringKey,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) {
        self.init(titleKey.localized, role: role, action: action)
    }

    /// Creates a button with a role and a title displayed as written.
    ///
    /// Generic over `StringProtocol` for the same reason as
    /// ``init(_:action:)-(S,_)``.
    ///
    /// - Parameters:
    ///   - title: The button's label text.
    ///   - role: An optional semantic role describing the button.
    ///   - action: The action to perform when pressed.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) {
        self.label = String(title)
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
            isDisabled: isDisabled,
            isMenuTrigger: isMenuTrigger
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
    var isMenuTrigger = false

    var body: Never {
        fatalError("_ButtonCore renders via Renderable")
    }

    private enum StateIndex {
        static let focusID = 0
        static let isHovered = 1
        static let isPressed = 2
    }

    /// A button hugs its label (it never grows to fill), so this is its exact,
    /// fixed measure.
    ///
    /// Measured through the style's own body rather than by rendering this
    /// button and discarding the buffer. The two are the same question:
    /// `ButtonStyle.makeBuffer` is `renderToBuffer(makeBody(configuration:))`
    /// and lives in an extension — not a protocol requirement — so EVERY button
    /// style's buffer is its body's buffer, and `renderToBuffer` below adds only
    /// a hit-test region to it, never a cell. So the size of the body is the
    /// size of the button, and `measureChild` is the way to ask for a size.
    ///
    /// It matters because rendering to measure is most of what a button costs.
    /// Two-pass layout measures a stack's children before it renders them, so a
    /// plain button was drawn twice a frame; inside a menu, which takes a hug
    /// measure of the whole column first, three times. Priced by caching the
    /// answer across frames in the Mode A harness (checksums unchanged):
    /// `menu` -48.4%, `paneled` -31.1%, `form` -9.0%, all 9 of 9 paired reps,
    /// and nothing on the six trees with no buttons in them.
    ///
    /// A style whose body is procedural (`_ButtonStyleBody`) answers one level
    /// further down: a string label by the render's own arithmetic, a
    /// `@ViewBuilder` one by drawing it (and, when it drew its whole offer, by
    /// asking the view it drew the label in whether that fills). A style whose
    /// body is structural — `_MenuItemButtonStyle`, whose `_MenuItemRowBar`
    /// answers `sizeThatFits` with `measureChild(row)` — never paints at all.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let style = context.environment.buttonStyle
        // A procedural body is going to be drawn to be measured whichever way
        // it is asked, and going through the style would then resolve the
        // configuration twice — once here and again inside the render. Measured:
        // that double resolve was `paneled` +1.3%, 0 of 9 reps faster.
        guard style.bodyCanMeasureItself else {
            return measureFixedByRendering(self, proposal: proposal, context: context)
        }
        let resolved = resolve(context: context)
        return style.makeSize(
            configuration: resolved.configuration, proposal: proposal, context: context)
    }

    /// Reports this button to whatever owns its highlight, and answers whether
    /// it is the highlighted one.
    ///
    /// Two owners, one question. Inside an open pop-up menu that is the menu's
    /// column, which holds an ordinal; anywhere else — including inside an
    /// INLINE menu, whose rows really are page focus stops — it is the focus
    /// manager, exactly as before.
    private func claimHighlight(
        menuOrdinal: Int?, focusID: String, action: @escaping () -> Void, isDisabled: Bool,
        context: RenderContext
    ) -> Bool {
        guard let menuOrdinal else {
            // A measure pass reaches the end of this branch having computed
            // `false` and changed nothing, so it can start there instead.
            // Every one of the three things below is already measure-gated at
            // its own door — `FocusRegistration.register` returns on
            // `!context.isMeasuring`, `isFocused` answers `false` outright, and
            // `publishActivationLabel` needs both `isFocused` and not
            // measuring. What is NOT gated is the work of getting to them: an
            // `ActionHandler` object whose default `triggerKeys` builds a fresh
            // `Set<Key>`, an environment read for its extras, and a
            // `LocalizationService` lookup that takes a lock and returns a
            // dictionary value by value. All of it allocated and thrown away.
            //
            // This is the measure/render asymmetry the project already knows
            // about, met from the performance side rather than the correctness
            // side: a button is rendered three times a frame inside a menu and
            // twice of those are measures.
            guard !context.isMeasuring else { return false }
            let handler = ActionHandler(
                focusID: focusID, action: action, canBeFocused: !isDisabled,
                // Read here rather than in the closure: the environment is out
                // of reach by the time a key arrives, exactly as the menu's
                // dismiss action is.
                extras: context.environment.buttonKeyExtras)
            // `ActionHandler` is rebuilt from `focusID` on every frame, so it
            // agrees with the declaration by construction — see
            // ``PersistedFocusable``.
            FocusRegistration.register(context: context, handler: handler, focusID: focusID)
            let isFocused = FocusRegistration.isFocused(context: context, focusID: focusID)
            // What Return does here, for the status bar: a menu trigger opens
            // its menu, a row of a menu chooses, and a button on the page
            // activates.
            let verb =
                isMenuTrigger
                ? MenuPresentationLabels.popUp.open
                : LocalizationService.shared.string(
                    for: context.environment.isInsideMenu
                        ? LocalizationKey.StatusBar.choose : .activate)
            FocusRegistration.publishActivationLabel(
                verb, context: context, isFocused: isFocused)
            return isFocused
        }
        // `FocusRegistration.register` bundles three things; skipping it must
        // not skip the other two. `markActive` is state-GC, not focus — without
        // it the row's hover box and any `@State` in a `@ViewBuilder` label are
        // collected at the end of the frame. And the side-effect record is what
        // keeps the row out of a value memo: a cached row would serve last
        // frame's highlight forever, which is the same hole a memoised `ForEach`
        // row falls into.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        context.stateStorage?.markActive(context.identity)
        context.environment.menuRowSink?.publish(
            ordinal: menuOrdinal, action: action, isEnabled: !isDisabled)
        return menuOrdinal == context.environment.menuHighlightedOrdinal
    }

    /// Everything a pass works out before it asks the style for anything.
    ///
    /// Shared because the measure and the render must agree to the cell: the
    /// size a button reports is the size of the very view the style would
    /// build, so both passes have to arrive at the same
    /// ``ButtonStyleConfiguration`` — same focus, same hover, same resolved
    /// shortcut (whose hint the row prints, and which a measure that missed it
    /// would size too narrow for the render to fit).
    private struct Resolved {
        let configuration: ButtonStyleConfiguration
        let persistedFocusID: String
        let menuOrdinal: Int?
        let hoverBox: StateBox<Bool>
        let pressBox: StateBox<Bool>
        let effectiveAction: () -> Void
        let isDisabled: Bool
    }

    /// Resolves this button against `context`, running the per-frame side
    /// effects that are already gated on `!context.isMeasuring` inside
    /// themselves. This is what `renderToBuffer` used to do inline, verbatim.
    private func resolve(context: RenderContext) -> Resolved {
        // Combine this button's own disabled state with the cascading
        // `.disabled(_:)` environment value (a container can disable it).
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "button",
            propertyIndex: StateIndex.focusID
        )
        // If this button sits inside an open pop-up menu, selecting it should run
        // its action AND close the menu (SwiftUI's menu auto-dismiss). Capture the
        // dismiss action into a local now — the environment isn't reachable from
        // the event closure. `nil` everywhere outside a menu subtree, so a plain
        // page button is unaffected — and `nil` too under a
        // `.menuActionDismissBehavior(.disabled)`, which is exactly "run the
        // action, leave the menu up".
        let dismissMenu =
            context.environment.menuActionDismissBehavior.dismissesMenu
            ? context.environment.dismissMenu : nil
        let action = self.action
        let effectiveAction: () -> Void = {
            action()
            dismissMenu?()
        }
        // Inside an open pop-up menu a row does NOT join the page's focus ring:
        // the menu owns an ordinal instead, which is what gives it the jump keys
        // and the windowed scrolling a `Picker` drop-down has always had. On the
        // page — and inside an INLINE menu, whose rows really are page focus
        // stops — this is nil and nothing changes. See
        // `Documentation/Unifying the menu implementations.md`.
        //
        // Claimed on the RENDER pass only. A measure runs the same rows through
        // here, and the identities it hands them are its own — so letting a
        // measure claim would spend the ordinals the render then wants, and the
        // highlight would point at a row that never drew. On a measure this is
        // nil and the row takes the ordinary path, which registers nothing while
        // measuring anyway.
        let menuOrdinal =
            context.isMeasuring
            ? nil : context.environment.menuRowSink?.claimOrdinal(for: context.identity)
        // Gated for DRAWING only — see `RenderContext.indicatesFocus(_:)`.
        // `claimHighlight` still runs with the true answer inside it, because
        // it also publishes the status bar's Return verb, and what a key does
        // is not a focus effect.
        let isFocused = context.indicatesFocus(
            claimHighlight(
                menuOrdinal: menuOrdinal, focusID: persistedFocusID, action: effectiveAction,
                isDisabled: isDisabled, context: context))

        // Hover state persists across renders via StateStorage —
        // the dispatcher flips it on .entered / .exited events
        // synthesised by the hover state machine. Disabled
        // buttons never show the affordance, so clamp to false
        // when isDisabled regardless of the stored value.
        let stateStorage = context.stateStorage!
        let hoverKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.isHovered
        )
        let hoverBox: StateBox<Bool> = stateStorage.storage(for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        // Press state persists across renders the same way hover does: the
        // mouse handler below flips this box on `.pressed` / `.released` for
        // an ordinary (non-menu-trigger) button, which is a real press-and-hold
        // — down over the button, up to activate, or drag off to cancel — the
        // same gesture `MouseEventDispatcher.endsHeldGesture` already tracks.
        // Disabled buttons never show it, same clamp as hover.
        let pressKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.isPressed
        )
        let pressBox: StateBox<Bool> = stateStorage.storage(for: pressKey, default: false)
        let isPressed = !isDisabled && pressBox.value

        // A `.keyboardShortcut(.defaultAction / .cancelAction)` wrapper plants a
        // claimable assignment in the environment; the wrapped button claims it
        // and registers its action for the frame.
        var resolvedShortcut: KeyboardShortcut?
        if !isDisabled,
            let assignment = context.environment.assignedKeyboardShortcut,
            let shortcut = assignment.claim(by: context.identity, isMeasuring: context.isMeasuring)
        {
            // `.command` is not a key a terminal can report, so it is resolved
            // to whatever stands in for it here (`.commandKey(_:)`) — the one
            // place that both holds the environment and knows the shortcut.
            // Resolved on EVERY pass, because it is handed to the style so a
            // menu row can print its hint (as AppKit draws a menu item's key
            // equivalent), and a measure that didn't see the hint would size
            // the menu too narrow for the render to fit it.
            resolvedShortcut = shortcut.resolved(commandKey: context.environment.commandKey)
            // Registration, though, is per-frame presence: the registry is
            // emptied before every walk, so a button whose subtree was served
            // from a value memo has to register again or its key equivalent is
            // dead while the button is still on screen. Declared to any
            // value-memoizing ancestor either way — as REPLAYABLE when the
            // modifier carrying the shortcut is inside the memo, and as a plain
            // render side effect when it was planted above one, where a served
            // frame would leave the offer standing. See
            // `KeyboardShortcutRegistrar`.
            if let resolvedShortcut, !context.isMeasuring,
                KeyboardShortcutRegistrar.register(
                    resolvedShortcut, action: effectiveAction, context: context)
            {
                KeyboardShortcutRegistrar.declare(
                    resolvedShortcut, action: effectiveAction, carrier: assignment,
                    context: context)
            }
        }

        let configuration = ButtonStyleConfiguration(
            label: label,
            labelView: labelView,
            role: role,
            isPressed: isPressed,
            isFocused: isFocused && !isDisabled,
            isHovered: isHovered,
            isEnabled: !isDisabled,
            keyboardShortcut: resolvedShortcut
        )
        return Resolved(
            configuration: configuration,
            persistedFocusID: persistedFocusID,
            menuOrdinal: menuOrdinal,
            hoverBox: hoverBox,
            pressBox: pressBox,
            effectiveAction: effectiveAction,
            isDisabled: isDisabled)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let resolved = resolve(context: context)
        let isDisabled = resolved.isDisabled
        let persistedFocusID = resolved.persistedFocusID
        let menuOrdinal = resolved.menuOrdinal
        let hoverBox = resolved.hoverBox
        let pressBox = resolved.pressBox
        let effectiveAction = resolved.effectiveAction
        let style = context.environment.buttonStyle
        var buffer = style.makeBuffer(
            configuration: resolved.configuration, context: context)

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
            mouseDispatcher.requestFeature(.motion, in: context)

            // A menu row is not a focus stop, so clicking one must not try to
            // move the focus onto an id nothing registered; the click just runs
            // the row, which closes the menu anyway.
            let focusManager = menuOrdinal == nil ? context.environment.focusManager : nil
            let captureFocusID = persistedFocusID
            let captureAction = effectiveAction
            let captureHoverBox = hoverBox
            let capturePressBox = pressBox
            let handlerID = mouseDispatcher.register(in: context, hoverBox: captureHoverBox) { event in
                switch event.phase {
                case .pressed where event.button == .left:
                    guard isMenuTrigger else {
                        // Claim the press so the dispatcher routes the
                        // matching release back here even if the cursor
                        // drifts off the button before it lifts — which is
                        // also what guarantees the `.released` below always
                        // arrives to clear this again. A REAL press-and-hold:
                        // set it and let the render this unblocks show it.
                        capturePressBox.value = true
                        return true
                    }
                    // A menu trigger fires on the press and then gets out of
                    // the way: the menu it just opened is what the drag and
                    // release belong to, so the press hands the rest of the
                    // gesture back to live hit-testing. That is what makes
                    // press-drag-release pick a row, the way a Mac menu does.
                    // There is no held moment to show here — the action (and
                    // usually the menu covering this button) both land on the
                    // same frame as the press — and hand-off means no release
                    // is guaranteed back to this handler to clear a flag it
                    // set, so this path leaves `capturePressBox` alone.
                    focusManager?.focus(id: captureFocusID)
                    captureAction()
                    mouseDispatcher.handOffGesture()
                    mouseDispatcher.pressOpenedPopup()
                    return true
                case .released where event.button == .left:
                    // The trigger already fired on the press. This release only
                    // arrives when the menu did not take it (it opens on the
                    // frame after the press, so a press and release in one input
                    // batch both land here) — consumed, but never a second
                    // activation, which would toggle the menu straight shut.
                    guard !isMenuTrigger else { return true }
                    capturePressBox.value = false
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
                    // A menu row names itself by its ordinal: it has no focus id
                    // to be found by, and a tall menu still has to scroll its
                    // highlighted row into view.
                    focusID: menuOrdinal.map(menuRowRegionID) ?? persistedFocusID
                )
            )
        }

        return buffer
    }
}

// MARK: - Button Convenience Modifiers

extension Button {
    /// Makes this button a pop-up menu's trigger: its action runs on the mouse
    /// PRESS, and the drag and release that follow are handed back to live
    /// hit-testing so they reach the menu the action opened.
    ///
    /// That is the whole of macOS menu tracking — press and hold to open, drag
    /// to highlight, release to choose — and it only makes sense for a control
    /// whose action opens something under the pointer, which is why this is
    /// internal rather than a general "activate on press" knob. An ordinary
    /// button keeps firing on release, so you can still slide off one to change
    /// your mind.
    ///
    /// - Returns: A button that opens its menu on the press.
    func menuTrigger() -> Button {
        var copy = self
        copy.isMenuTrigger = true
        return copy
    }

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
