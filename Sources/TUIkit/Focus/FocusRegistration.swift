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
/// let persistedFocusID = FocusRegistration.persistFocusID(
///     context: context,
///     explicitFocusID: focusID,
///     defaultPrefix: "button",
///     propertyIndex: StateIndex.focusID)
/// let handler: StateBox<MyHandler> = /* built or fetched from StateStorage */
/// FocusRegistration.register(
///     context: context, handler: handler.value, focusID: persistedFocusID)
/// let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
/// ```
///
/// An `enum` rather than a `struct` because nothing is ever an instance of it:
/// it had two stored properties that existed only to be a `resolve` return
/// value, and every caller went the three-step way above instead.
enum FocusRegistration {

    /// Persists the focusID in StateStorage and returns it, without registering a handler.
    ///
    /// Use this when the handler is also persisted in StateStorage and needs the
    /// focusID before construction (e.g. TextField, Slider, Stepper).
    ///
    /// After creating/retrieving the handler, call
    /// ``register(context:handler:focusID:)`` and ``isFocused(context:focusID:)``
    /// separately.
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
    ///
    /// `@MainActor`, as every `Renderable.renderToBuffer` that calls it already
    /// is: a registration that can be replayed has to hand the render cache a
    /// closure holding this `Focusable`, and a handler is not `Sendable`, so
    /// building that closure anywhere else would be sending an isolated value.
    @MainActor
    static func register(context: RenderContext, handler: Focusable, focusID: String) {
        guard !context.isMeasuring else { return }
        // A persisted handler was built once, from the id in force on the frame
        // it first drew; the declaration is re-resolved on every frame. Re-point
        // it before the ring files it, or `.focused($field, equals:)` and every
        // other by-id lookup goes on addressing a name the view has stopped
        // answering to.
        // `let`, not `var`, and the difference is nothing: ``Focusable`` refines
        // `AnyObject`, so the binding is a reference and the write lands on the
        // handler the ring holds. Written `var` it drew a compiler warning that
        // it was never mutated — which is exactly right, and would be a real bug
        // rather than a warning if the protocol ever stopped being class-bound.
        if let persisted = handler as? any PersistedFocusable, persisted.focusID != focusID {
            persisted.focusID = focusID
        }
        let sectionID = context.environment.activeFocusSectionID
        // Read BEFORE the claim below, because claiming is what consumes it.
        // `.focused($x, equals:)` offers an id to the first focusable that
        // renders under it, and `.focusHandoff(_:_:)` offers a target the same
        // way; both are planted above the control and may be planted above a
        // memo boundary too, where the memo's key cannot see them.
        let carriesOfferedDeclaration =
            context.environment.assignedFocusID != nil
            || context.environment.focusHandoffOffer != nil
        FocusRegistrar.register(
            identity: context.identity, handler: handler, focusID: focusID,
            sectionID: sectionID, context: context)
        // A `.focusHandoff(_:_:)` above names where this control's focus goes
        // when it can no longer hold it. Declared only where the control
        // registers, so a control that stops registering (removed, hidden, a
        // disabled `.focusable()`) stops declaring, and the manager recovers it
        // by what it declared on its last frame.
        if !context.environment.isFocusSuppressed, let manager = context.environment.focusManager,
            let handoff = context.environment.focusHandoffOffer?.claim(context.identity)
        {
            manager.registerFocusHandoff(from: focusID, store: handoff.store, value: handoff.value)
        }
        declareRegistration(
            context: context, handler: handler, focusID: focusID, sectionID: sectionID,
            carriesOfferedDeclaration: carriesOfferedDeclaration)
        // markActive is unrelated to focus (state GC) and always runs.
        context.stateStorage!.markActive(context.identity)
        publishHelpText(context: context, focusID: focusID)
    }

    /// Tells a value-memoizing ancestor what this registration was: whether it
    /// must decline to store the subtree, or may store it and make the
    /// registration again on every hit.
    ///
    /// Focus registration is per-frame presence — the ring is rebuilt every pass
    /// (`FocusManager.beginSceneRender`) — so a served subtree that did not
    /// register again would drop its controls out of the Tab ring while they are
    /// still on screen. Most registrations can simply be made again, which is
    /// what ``FocusRegistrar`` is: recorded here while a memo records, and
    /// replayed at the point in the walk where the control would have rendered,
    /// so the ring is in the same order whether the subtree rendered or was
    /// served. Four cases cannot be made again and keep declining:
    ///
    /// - **A control that holds the focus.** Its buffer draws the focus ring,
    ///   and nothing in the memo's key sees the focus move away from it.
    /// - **A backdrop's manager** (`isBackdrop`). The page beneath a modal is a
    ///   picture drawn with everything unfocused. Stored, it would be served
    ///   again once the modal was dismissed — and a modal carrying no focusables
    ///   of its own moves no focused id, so nothing would invalidate it and the
    ///   page would keep drawing no focus at all.
    /// - **A probe's manager** (`suppressesAutoFocus`). The windowed stack's
    ///   focus-reach probe renders rows the frame never draws.
    /// - **A control under an offered declaration**, per the caller: replayed, it
    ///   would hold an id another focusable is free to claim on the frame that
    ///   serves it, and a handoff — pruned at the end of every pass — would not
    ///   be re-declared at all.
    ///
    /// The entry carries the key channels in force, as every other replayable
    /// registration does, even though the focus ring is not one of them. That is
    /// exact rather than merely cautious: the only two contexts with throwaway
    /// key channels are `RenderContext.isolatedForBackground()` and the
    /// focus-reach probe, and both carry a manager refused above — so no entry a
    /// memo would filter out on its token is ever recorded, and no control can
    /// vanish from the ring that way.
    @MainActor
    private static func declareRegistration(
        context: RenderContext, handler: Focusable, focusID: String, sectionID: String?,
        carriesOfferedDeclaration: Bool
    ) {
        let tracker = context.environment.volatileReadTracker
        let manager = context.environment.focusManager
        guard !carriesOfferedDeclaration,
            manager?.isBackdrop != true,
            manager?.suppressesAutoFocus != true,
            // Asked AFTER registering, because registering is what can focus it:
            // an empty section auto-focuses its first registrant, and a pending
            // intent resolves the moment its target appears.
            manager?.isFocused(id: focusID) != true
        else {
            tracker?.recordRenderSideEffect()
            return
        }
        tracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        // Built only while a memo records, so the live path allocates no second
        // closure. The identity and the section are captured rather than looked
        // up: they are where this control rendered and the section it registered
        // in, and the memo checks that the section it is served under is the one
        // the registration was recorded in.
        let identity = context.identity
        journal.append(
            EffectJournal.Entry(
                kind: FocusRegistrar.kind, channelToken: context.environment.keyChannelToken
            ) { [handler] replay in
                FocusRegistrar.register(
                    identity: identity, handler: handler, focusID: focusID,
                    sectionID: sectionID, context: replay)
            })
    }

    /// Claims the subtree's `EnvironmentValues.helpText` for this control, if
    /// it holds the focus.
    ///
    /// Called from ``register(context:handler:focusID:)`` rather than from each
    /// control, because every focusable control already funnels through there
    /// and a per-control call is the version somebody forgets — a control whose
    /// `help(_:)` silently does nothing on the keyboard, with no way to tell
    /// from the call site that it was meant to.
    ///
    /// Publishing does not usually SHOW anything: a focus candidate is revealed
    /// by the help key, unless the subtree asked for ``TooltipTrigger/onFocus``.
    /// See `TooltipState.keyboardRevealed`.
    /// Internal, not private, for one caller: the `NavigationSplitView` divider
    /// registers with the focus manager directly rather than through
    /// ``register(context:handler:focusID:)``, so it has to ask for this itself.
    /// It is the only such site; anything else hung off `register` reaches every
    /// focusable in the framework.
    static func publishHelpText(context: RenderContext, focusID: String) {
        let trigger = context.environment.tooltipTrigger
        guard let text = context.environment.helpText,
            trigger != .never,
            let tooltips = context.environment.tooltipState,
            context.environment.focusManager?.isFocused(id: focusID) == true
        else { return }
        // The delay and the trigger are read HERE, from the focused control's
        // own environment, for the reason the style is: all three are subtree
        // settings, and the run loop that resolves the tooltip has only the
        // root's.
        tooltips.focusing(
            text, handlerID: nil, nowNanos: context.environment.frameNowNanos,
            style: trigger.presentation(context.environment.tooltipStyle),
            delaySeconds: context.environment.tooltipDelay,
            revealsItself: trigger.revealsOnFocus)
    }

    /// Whether the given focusID currently has focus.
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

    /// Tells a focus stop's content whether the stop holds the focus, as
    /// ``EnvironmentValues/isFocused`` — and tells the render memo as well,
    /// which the assignment alone does not.
    ///
    /// A memo below keys on identity, view value and size and carries no
    /// environment, so a bare `contentContext.environment.isFocused = x` is a
    /// change nothing compares. That is how `Card().equatable().focusable()`
    /// took the focus and went on drawing the frame from before it arrived —
    /// and so did every row of `VStack { ForEach(items) { Row($0) } }.focusable()`
    /// with no memo asked for, since `ForEach` wraps each `Equatable` row in
    /// `_MemoizedRow`. Declaring a render side effect here instead does NOT
    /// work: it lands on the ancestor's tracker before the memo below takes its
    /// snapshot, so it declines a memo ABOVE this stop (which registration
    /// already does) and none below it.
    ///
    /// So the value is noted where it is applied, exactly as `TintModifier`
    /// notes a tint: one comparison per stop per pass, rather than one more
    /// environment probe on every memo lookup in the tree. Unlike a tint, a
    /// change clears the SIZES below too: a view is free to lay itself out
    /// differently while it holds the focus.
    ///
    /// Noted on the render walk only. A measuring stop registers nothing and
    /// has no answer, and a note from the measure walk would record the
    /// INHERITED value first each pass — the render walk's note would then hit
    /// `noteAppliedEnvironment`'s once-per-pass short circuit and never be
    /// compared. The depth bump is on both walks, because an
    /// `EnvironmentModifier` below notes on both and must find the same slot.
    ///
    /// - Parameters:
    ///   - isFocused: The stop's answer, or `nil` when no stop was registered
    ///     this pass — not focusable, disabled, an open menu's backdrop. The
    ///     content then sees what it inherits, and THAT is noted, so a stop
    ///     that goes from focused to unregistered still clears what was drawn
    ///     focused below it.
    ///   - context: The publishing modifier's own context; its identity and
    ///     depth name the slot.
    ///   - contentContext: The context the content renders with.
    static func publishIsFocused(
        _ isFocused: Bool?, context: RenderContext, into contentContext: inout RenderContext
    ) {
        contentContext.environmentApplicationDepth += 1
        guard !context.isMeasuring else { return }
        let published = isFocused ?? contentContext.environment.isFocused
        if let isFocused { contentContext.environment.isFocused = isFocused }
        // Matching only `.changed` is exhaustive here, unlike at
        // `ThemeModifier`, where it was not: `published` is a `Bool` and so is
        // `\EnvironmentValues.isFocused`'s value, so `noteAppliedEnvironment`
        // has an `Equatable` value at this slot however it is reached and can
        // never answer `.incomparable`.
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                published, identity: context.identity,
                keyPath: \EnvironmentValues.isFocused, depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity)
        }
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

// MARK: - Registration

/// The one focus registration every interactive control makes, shared by the
/// live render and by a value memo replaying it — see `EffectJournal`.
enum FocusRegistrar {
    /// The journal kind of a focus registration.
    static let kind = EffectJournal.Kind("focusRegistration")

    /// Files `handler` under `focusID` in `sectionID` of `context`'s focus ring.
    ///
    /// It looks the focus manager and the render cache up in `context` rather
    /// than taking them, so a replay registers into the services of the frame
    /// that serves it. `identity` is passed instead, because it is the
    /// CONTROL's, and the context a replay runs against is the memo's — whose
    /// identity is the memo root, not the control.
    @MainActor
    static func register(
        identity: ViewIdentity, handler: Focusable, focusID: String, sectionID: String?,
        context: RenderContext
    ) {
        // A nil focus manager means "no focus system" (e.g. an isolated test):
        // skip registration so nothing auto-focuses. `isFocusSuppressed` is the
        // narrower form of the same thing — a `.hidden()` subtree, which has no
        // picture for Tab to land on but is otherwise alive (see
        // `EnvironmentValues.isFocusSuppressed`).
        guard !context.environment.isFocusSuppressed,
            let manager = context.environment.focusManager
        else { return }
        // Before the registration, not after. Registering can focus this control
        // on the spot — an empty section auto-focuses its first registrant — and
        // the write that does it drops the cached buffers drawing this control,
        // which it can only do once the manager knows where this control is.
        manager.noteFocusIdentity(identity, for: focusID, cachedIn: context.renderCache)
        manager.register(handler, inSection: sectionID)
    }
}
