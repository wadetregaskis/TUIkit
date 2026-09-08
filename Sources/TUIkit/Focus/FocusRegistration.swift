//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusRegistration.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Focus Registration

/// The result of registering an interactive view with the focus system.
///
/// `FocusRegistration` consolidates the common pattern shared by all interactive
/// views (Button, TextField, Toggle, Slider, etc.) into a single helper.
/// It handles:
/// - Persisting the focusID across renders via `StateStorage`
/// - Registering a `Focusable` handler with the `FocusManager`
/// - Marking the identity as active in `StateStorage`
/// - Determining the current focus state
///
/// # Usage
///
/// ```swift
/// // In _*Core.renderToBuffer(context:):
/// let registration = FocusRegistration.resolve(
///     context: context,
///     explicitFocusID: focusID,
///     defaultPrefix: "button",
///     focusIDPropertyIndex: 0
/// )
///
/// // Use registration.persistedFocusID and registration.isFocused
/// ```
struct FocusRegistration {
    /// The stable focusID persisted across renders.
    let persistedFocusID: String

    /// Whether this view currently has focus.
    let isFocused: Bool

    /// Resolves focus state and registers a handler with the focus system.
    ///
    /// This is the primary entry point for views that create their handler
    /// inline (Button, Toggle) using `ActionHandler`.
    ///
    /// - Parameters:
    ///   - context: The current render context.
    ///   - handler: The focusable handler to register.
    ///   - explicitFocusID: An explicit focusID from the view's init, or `nil`.
    ///   - defaultPrefix: The prefix for auto-generated focusIDs (e.g. `"button"`).
    ///   - focusIDPropertyIndex: The `StateStorage` property index for persisting the focusID.
    /// - Returns: A `FocusRegistration` with the persisted focusID and focus state.
    static func resolve(
        context: RenderContext,
        handler: Focusable,
        explicitFocusID: String?,
        defaultPrefix: String,
        focusIDPropertyIndex: Int
    ) -> Self {
        let persistedFocusID = persistFocusID(
            context: context,
            explicitFocusID: explicitFocusID,
            defaultPrefix: defaultPrefix,
            propertyIndex: focusIDPropertyIndex
        )

        register(context: context, handler: handler, focusID: persistedFocusID)

        let isFocused = context.isMeasuring
            ? false
            : (context.environment.focusManager?.isFocused(id: persistedFocusID) ?? false)

        return Self(persistedFocusID: persistedFocusID, isFocused: isFocused)
    }

    /// Persists the focusID in StateStorage and returns it, without registering a handler.
    ///
    /// Use this when the handler is also persisted in StateStorage and needs the
    /// focusID before construction (e.g. TextField, Slider, Stepper).
    ///
    /// After creating/retrieving the handler, call ``register(context:handler:)``
    /// and ``isFocused(context:focusID:)`` separately.
    ///
    /// - Parameters:
    ///   - context: The current render context.
    ///   - explicitFocusID: An explicit focusID from the view's init, or `nil`.
    ///   - defaultPrefix: The prefix for auto-generated focusIDs (e.g. `"textfield"`).
    ///   - propertyIndex: The `StateStorage` property index for persisting the focusID.
    /// - Returns: The stable focusID.
    static func persistFocusID(
        context: RenderContext,
        explicitFocusID: String?,
        defaultPrefix: String,
        propertyIndex: Int
    ) -> String {
        let stateStorage = context.stateStorage!
        // A `.focused($binding, equals:)` modifier offers its id to the FIRST
        // focusable below it (see `AssignedFocusID`); it ranks below an explicit
        // `.focusID(_:)` but above the auto-generated path id. Claimed on the
        // render pass only — a measuring control resolves the persisted id
        // below, which is this id if the control is the one that took it.
        let assigned =
            context.isMeasuring
            ? nil : context.environment.assignedFocusID?.claim(context.identity)
        let declared = explicitFocusID ?? assigned
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex)
        // Written as an argument rather than a `let` on purpose: the default is
        // an `@autoclosure`, and `context.identity.path` renders the whole
        // identity chain into a string of demangled generic type names. Every
        // focusable view asked for it on every measure and every render, and
        // every frame after the first threw it away.
        let box: StateBox<String> = stateStorage.storage(
            for: key, default: declared ?? "\(defaultPrefix)-\(context.identity.path)")

        // A DECLARED id is the app's answer on every frame, not just the first.
        // Returning the stored one regardless froze whatever `.focusID(_:)`
        // happened to say the first time this view rendered: an id computed
        // from state — `focusID("row-\(selectedID)")` — never changed again, so
        // `.focused($field, equals:)` and every other by-id lookup went on
        // addressing a control that no longer answered to that name.
        //
        // The box still holds it, for the same reason it always did: nothing
        // else persists the id, and it must survive a frame where the
        // declaration is momentarily absent. It is written only on the render
        // pass, since a write is an invalidation and a measure pass must not
        // cause one — the returned value is the declaration either way, so
        // what is measured still matches what is drawn.
        if let declared {
            if !context.isMeasuring, box.value != declared {
                box.value = declared
            }
            return declared
        }
        return box.value
    }

    /// Registers a handler with the focus manager and marks the identity as active.
    ///
    /// Skipped during measurement passes to avoid side effects.
    ///
    /// - Parameters:
    ///   - context: The current render context.
    ///   - handler: The focusable handler to register.
    ///   - focusID: The id the control DECLARES this frame, from
    ///     ``persistFocusID(context:explicitFocusID:defaultPrefix:propertyIndex:)``.
    ///     Required, and required of every site rather than defaulted, so the
    ///     compiler asks the question of the next handler somebody persists —
    ///     the silent version of this is a control the focus ring can no longer
    ///     find. Pass the handler's own id where it is rebuilt each frame.
    static func register(context: RenderContext, handler: Focusable, focusID: String) {
        guard !context.isMeasuring else { return }
        // A persisted handler was built once, from the id in force on the frame
        // it first drew; the declaration is re-resolved on every frame. Re-point
        // it before the ring files it, or `.focused($field, equals:)` and every
        // other by-id lookup goes on addressing a name the view has stopped
        // answering to.
        if var persisted = handler as? any PersistedFocusable, persisted.focusID != focusID {
            persisted.focusID = focusID
        }
        // Focus registration is per-frame presence (sections are rebuilt every
        // pass), so a value-memoized row serving a cached buffer would drop
        // its focusables from the ring while still on screen. In practice an
        // interactive row is already uncacheable via its hit-test regions, but
        // that only holds when a mouse dispatcher is wired in — declare the
        // side effect so keyboard-only configurations are safe too.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        // A nil focus manager means "no focus system" (e.g. an isolated test or
        // dimmed-backdrop render): skip registration so nothing auto-focuses.
        // `isFocusSuppressed` is the narrower form of the same thing — a
        // `.hidden()` subtree, which has no picture for Tab to land on but is
        // otherwise alive (see `EnvironmentValues.isFocusSuppressed`).
        // markActive is unrelated to focus (state GC) and always runs.
        if !context.environment.isFocusSuppressed {
            context.environment.focusManager?.register(
                handler, inSection: context.environment.activeFocusSectionID)
        }
        context.stateStorage!.markActive(context.identity)
    }

    /// Determines whether the given focusID currently has focus.
    ///
    /// Always returns `false` during measurement passes.
    ///
    /// - Parameters:
    ///   - context: The current render context.
    ///   - focusID: The focusID to check.
    /// - Returns: `true` if the view is focused.
    static func isFocused(context: RenderContext, focusID: String) -> Bool {
        context.isMeasuring ? false : (context.environment.focusManager?.isFocused(id: focusID) ?? false)
    }

    /// Says what Return would do to this control, while it holds the focus.
    ///
    /// The status bar renames its Return item to this, so one declared item
    /// stays true as the focus moves between controls that answer the key
    /// differently — "open menu" over a closed pop-up, "toggle" over a switch,
    /// "activate" over a button. A control that does nothing with Return says
    /// nothing and the page's own label stands.
    ///
    /// A verb, lower case, no key name: the bar draws the key itself.
    ///
    /// - Parameters:
    ///   - label: What Return does here, or `nil` to say nothing.
    ///   - context: The current render context.
    ///   - isFocused: Whether this control holds the focus. Unfocused controls
    ///     publish nothing, so the claim always belongs to exactly one.
    static func publishActivationLabel(
        _ label: String?, context: RenderContext, isFocused: Bool
    ) {
        guard isFocused, !context.isMeasuring, let label else { return }
        context.environment.statusBar?.activationLabelOverride = label
    }
}
