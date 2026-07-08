//  🖥️ TUIKit — Terminal UI Kit for Swift
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

        register(context: context, handler: handler)

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
        let stateStorage = context.environment.stateStorage!
        let defaultID = explicitFocusID ?? "\(defaultPrefix)-\(context.identity.path)"
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex)
        let box: StateBox<String> = stateStorage.storage(for: key, default: defaultID)
        return box.value
    }

    /// Registers a handler with the focus manager and marks the identity as active.
    ///
    /// Skipped during measurement passes to avoid side effects.
    ///
    /// - Parameters:
    ///   - context: The current render context.
    ///   - handler: The focusable handler to register.
    static func register(context: RenderContext, handler: Focusable) {
        guard !context.isMeasuring else { return }
        // Focus registration is per-frame presence (sections are rebuilt every
        // pass), so a value-memoized row serving a cached buffer would drop
        // its focusables from the ring while still on screen. In practice an
        // interactive row is already uncacheable via its hit-test regions, but
        // that only holds when a mouse dispatcher is wired in — declare the
        // side effect so keyboard-only configurations are safe too.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        // A nil focus manager means "no focus system" (e.g. an isolated test or
        // dimmed-backdrop render): skip registration so nothing auto-focuses.
        // markActive is unrelated to focus (state GC) and always runs.
        context.environment.focusManager?.register(handler, inSection: context.environment.activeFocusSectionID)
        context.environment.stateStorage!.markActive(context.identity)
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
}
