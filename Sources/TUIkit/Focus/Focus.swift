//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Focus.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Focus Manager

/// Manages focus state across the application.
///
/// The focus manager organizes interactive elements into **focus sections**.
/// Each section is a named, focusable area (e.g. a sidebar, a content panel,
/// a modal) that contains its own list of focusable elements.
///
/// - **Tab / Shift+Tab** cycles between sections.
/// - **Up/Down arrows** navigate within the active section's focusable elements.
/// - **Enter/Space** activates the focused element.
///
/// Elements registered without an explicit section go into a default section.
/// When only one section exists, Tab cycles elements within it (legacy behavior).
///
/// `FocusManager` is injected via the Environment system.
/// Each app instance gets its own `FocusManager`, ensuring test isolation.
///
/// # Usage
///
/// ```swift
/// // Access via Environment in views
/// let focusManager = context.environment.focusManager
///
/// // Register a section (done by .focusSection() modifier)
/// focusManager.registerSection(id: "playlist")
///
/// // Register a focusable element in a section
/// focusManager.register(button, inSection: "playlist")
///
/// // Move focus
/// focusManager.focusNextInSection()     // within active section
/// focusManager.focusPreviousInSection() // within active section
/// focusManager.activateNextSection()    // switch to next section
///
/// // Check focus
/// if focusManager.isFocused(button) {
///     // render focused style
/// }
/// ```
public final class FocusManager: @unchecked Sendable {
    /// The default section ID for elements registered without an explicit section.
    static let defaultSectionID = "__default__"

    /// Registered focus sections in render order.
    private var sections: [FocusSection] = []

    /// The ID of the currently active section.
    private var activeSectionID: String?

    /// The currently focused element's ID within the active section.
    private var focusedID: String?

    /// The last focused element ID per section, so returning to a section
    /// (e.g. dismissing a modal whose overlay activated its own section)
    /// restores its focus instead of resetting to the section's first element.
    /// Without this, opening then closing a modal moved focus to the top of the
    /// page — and a `ScrollView` would snap-scroll there, resetting the scroll.
    private var sectionFocusMemory: [String: String] = [:]

    /// Sections that belong to a presented modal / alert — surfaces that *grab*
    /// input. Re-marked each render by the presentation modifiers (cleared in
    /// `beginRenderPass`). When the active section is one of these, the app's
    /// global default key bindings (appearance / theme cycling) must not fire
    /// behind the modal; see `InputHandler` and ``activeSectionIsModal``.
    private var modalSectionIDs: Set<String> = []

    /// Which device drove the most recent input event.
    ///
    /// A control that behaves differently depending on how it was activated —
    /// a menu opening with or without a selection — needs this because by the
    /// time its action runs, a `Button` has erased the difference: a click and
    /// a Return both just call the action. Kept here because `FocusManager` is
    /// the object that already decides where focus lands, and every event
    /// closure that would want this already holds one.
    private(set) var lastInputSource: InputSource = .keyboard

    /// Where an input event came from — see ``lastInputSource``.
    enum InputSource {
        case keyboard
        case pointer
    }

    /// Sections that may rest with NOTHING focused.
    ///
    /// A menu opened by the POINTER opens with no row highlighted — macOS
    /// behaviour, and the honest one: the pointer has not chosen anything yet,
    /// so pre-selecting an item invites a mis-click. The first arrow then
    /// chooses (Down → first item, Up → last), which the ring already does from
    /// an empty state. A menu opened from the KEYBOARD does not set this: there
    /// is no pointer, so it must start somewhere.
    ///
    /// Re-marked each render by whatever presents the section and cleared in
    /// ``beginRenderPass()``, exactly like ``modalSectionIDs`` — a dismissed
    /// menu simply stops marking and the flag evaporates.
    private var optionalFocusSectionIDs: Set<String> = []

    /// Whether this manager may give focus to a control merely because it
    /// registered. Set on the throwaway manager the page-beneath-a-modal
    /// renders into (`RenderContext.isolatedForBackground()`): that render
    /// exists only to draw a dimmed backdrop, so nothing in it should become
    /// focused — and crucially nothing should ACT on becoming focused. An
    /// auto-focused background control fires `onFocusReceived`, whose
    /// scroll-to-reveal then rewrites the page's scroll position, which is
    /// why the backdrop used to need a throwaway `StateStorage` too (and why
    /// the page's state was being pruned as a side effect). Suppressing the
    /// cause lets the backdrop share the real storage, so it draws the page
    /// as it actually is.
    ///
    /// Explicit focus (`focus(id:)`, section restore) is unaffected — only
    /// the "first registrant wins an empty focus" rule is.
    var suppressesAutoFocus = false

    /// For each section that was activated *over* another, the section to revert
    /// to when it is deactivated (e.g. a modal section reverts to the page's).
    private var sectionRevertTarget: [String: String] = [:]

    /// A focus request whose target was not registered when it was made —
    /// durable focus intent ("Locating things without drawing them" §5d:
    /// focus identity is durable; the registration set is per-frame, exactly
    /// the controls drawn last frame). Held until a registration with this ID
    /// appears: windowing containers consult it (`renderViewportWindow`) and
    /// render the routed-to row precisely so it registers, resolving the
    /// intent in the same pass. Expires after ``pendingFocusPassBudget``
    /// render passes so an ID that matches nothing doesn't scan forever; any
    /// other explicit focus change clears it.
    public private(set) var pendingFocusID: String?

    /// Render passes the pending intent survives unresolved: one for the
    /// routing render it triggers, one of slack for an intervening frame.
    private static let pendingFocusPassBudget = 2

    /// Passes remaining before ``pendingFocusID`` expires.
    private var pendingFocusPassesRemaining = 0

    /// A monotonic counter that increments every time the
    /// currently focused element handles (consumes) a key event.
    /// Used by ``ScrollView`` to tell apart "the focused control
    /// was just interacted with" from "the wheel just fired";
    /// when the counter changes between renders, the ScrollView
    /// snaps its viewport back to the focused control even
    /// though `currentFocusedID` itself hasn't changed.
    public private(set) var focusedInteractionGeneration: UInt64 = 0

    /// Callback triggered when focus changes (element or section).
    public var onFocusChange: (() -> Void)?

    // MARK: @FocusState binding registry

    /// One `.focused(_:equals:)` binding: which focusID a value maps to, and
    /// the render generation it was last registered in (for per-frame pruning).
    private struct FocusBinding {
        let focusID: String
        var generation: UInt64
    }

    /// One `.defaultFocus(_:_:)` declaration.
    private struct DefaultFocusDeclaration {
        let value: AnyHashable
        let priority: DefaultFocusEvaluationPriority
        var generation: UInt64
    }

    /// Per-`@FocusState` value→binding maps, keyed by the store's stable id.
    /// Rebuilt as `.focused(_:equals:)` modifiers render, but kept HERE — on the
    /// manager that outlives any single frame's view structs — so a
    /// `@FocusState` read at the top of a body (before its `.focused` modifiers
    /// have re-registered this frame) still resolves against the last frame's
    /// mapping. This is what makes `if focus == .name { … }` read the live
    /// focus, not a momentarily-empty map. Entries carry a render generation so
    /// ``pruneFocusRegistry()`` can drop those whose control left the tree,
    /// keeping the maps bounded to the working set (a windowed list of thousands
    /// of `.focused` rows never accumulates thousands of stale entries).
    private var focusBindings: [String: [AnyHashable: FocusBinding]] = [:]

    /// The declared default-focus value per store (from `.defaultFocus`), used
    /// to pick the initial focus once its bound control's id is known.
    private var focusDefaultValues: [String: DefaultFocusDeclaration] = [:]

    /// Store ids whose `.automatic` default focus has been applied —
    /// `.defaultFocus` sets the INITIAL focus once, then leaves the user in
    /// control. Dropped when a store's scope leaves the tree, so a dismissed and
    /// re-presented scope re-applies its default.
    private var appliedDefaultFocus: Set<String> = []

    /// Monotonic per-render-pass counter, bumped in ``beginRenderPass()``, used
    /// to age out `@FocusState` registry entries whose control stopped rendering.
    private var focusRenderGeneration: UInt64 = 0

    /// Creates a new focus manager instance.
    public init() {}

    /// The currently active focus section.
    var activeSection: FocusSection? {
        guard let activeID = activeSectionID else { return nil }
        return section(id: activeID)
    }

    /// The ID of the currently active section, if any.
    var activeSectionIdentifier: String? {
        activeSectionID
    }

    /// Whether the active section belongs to a presented modal / alert — i.e. a
    /// surface that grabs input. The `InputHandler` consults this to suppress the
    /// app's global default key bindings (appearance / theme) so they don't fire
    /// behind a modal. See ``markSectionModal(id:)``.
    var activeSectionIsModal: Bool {
        guard let activeID = activeSectionID else { return false }
        return modalSectionIDs.contains(activeID)
    }

    /// All registered section IDs in render order.
    var sectionIDs: [String] {
        sections.map(\.id)
    }

    /// Whether any sections are registered (besides potentially the default).
    var hasSections: Bool {
        !sections.isEmpty
    }

    /// The currently focused element, if any.
    public var currentFocused: Focusable? {
        guard let focusedIdentifier = focusedID else { return nil }
        // Search in active section first, then all sections
        if let section = activeSection,
            let element = section.focusables.first(where: { $0.focusID == focusedIdentifier })
        {
            return element
        }
        for section in sections where section.id != activeSectionID {
            if let element = section.focusables.first(where: { $0.focusID == focusedIdentifier }) {
                return element
            }
        }
        return nil
    }

    /// The ID of the currently focused element, if any.
    public var currentFocusedID: String? {
        focusedID
    }

    /// Whether the currently focused element is a text-input handler.
    ///
    /// When `true`, the input handler should give the focused element
    /// priority for key events before dispatching to other layers.
    var hasTextInputFocus: Bool {
        currentFocused is TextFieldHandler
    }
}

// MARK: - Public API

extension FocusManager {
    /// Registers a focusable element in a specific section.
    ///
    /// If the section doesn't exist, it is created automatically.
    /// If no element is focused yet in the active section, the element
    /// is auto-focused.
    ///
    /// - Parameters:
    ///   - element: The element to register.
    ///   - sectionID: The section to register in. Defaults to the active section
    ///     or the default section if no section is active.
    public func register(_ element: Focusable, inSection sectionID: String? = nil) {
        // Membership comes from WHERE the control renders — the environment's
        // activeFocusSectionID, threaded here by FocusRegistration and set by
        // .focusSection, modal/alert presentation, and NavigationSplitView's
        // columns. A nil means "no enclosing section": file it in the stable
        // default section. Falling back to the momentarily-ACTIVE section
        // (the old behaviour) made membership and section ORDER drift with
        // focus — focus a split-view divider and the next frame filed the
        // page's controls into the divider's section, created FIRST that
        // pass, collapsing Tab into a two-stop oscillation.
        let targetID = sectionID ?? Self.defaultSectionID

        // Ensure section exists
        if !sections.contains(where: { $0.id == targetID }) {
            registerSection(id: targetID)
        }

        guard let section = section(id: targetID) else { return }
        section.register(element)

        // Auto-activate section and auto-focus first element if needed
        if activeSectionID == nil {
            activeSectionID = targetID
        }
        // Hold off auto-focusing the section's first element while a
        // `.defaultFocus` still wants the initial focus — otherwise the first
        // control would transiently receive (and then lose) focus this frame,
        // firing a spurious editing-began/ended on the wrong control. The
        // default lands directly in `endRenderPass`.
        if targetID == activeSectionID && focusedID == nil && element.canBeFocused
            && !hasUnresolvedDefaultFocus
            && !optionalFocusSectionIDs.contains(targetID)
            && !suppressesAutoFocus
        {
            focusPreservingPendingIntent(element)
        }

        // A pending focus intent resolves the moment its target registers —
        // the windowing container rendered the routed-to row for exactly this.
        if let pending = pendingFocusID, element.focusID == pending, element.canBeFocused {
            pendingFocusID = nil
            if activeSectionID != targetID {
                activeSectionID = targetID
            }
            focusPreservingPendingIntent(element)
        }
    }

    /// Registers a focusable element (legacy API, uses active or default section).
    ///
    /// This overload exists for backward compatibility. New code should use
    /// ``register(_:inSection:)`` to explicitly assign sections.
    ///
    /// - Parameter element: The element to register.
    public func register(_ element: Focusable) {
        register(element, inSection: nil)
    }

    /// Unregisters a focusable element from all sections.
    ///
    /// - Parameter element: The element to unregister.
    public func unregister(_ element: Focusable) {
        for section in sections {
            section.unregister(element)
        }

        // If the removed element was focused, focus the next available
        if focusedID == element.focusID {
            focusedID = nil
            focusNextInSection()
        }
    }

    /// Clears all sections and focusable elements, including selection state.
    ///
    /// This is a hard reset. For per-frame clearing that preserves the active
    /// section and focused element, use `beginRenderPass()` instead.
    public func clear() {
        sections.removeAll()
        activeSectionID = nil
        focusedID = nil
        sectionFocusMemory.removeAll()
        sectionRevertTarget.removeAll()
        modalSectionIDs.removeAll()
        optionalFocusSectionIDs.removeAll()
        focusBindings.removeAll()
        focusDefaultValues.removeAll()
        appliedDefaultFocus.removeAll()
    }

    /// Focuses a specific element.
    ///
    /// An explicit focus supersedes any pending focus intent — without this,
    /// a click would be yanked to the pending target a frame later when the
    /// routed-to row registers.
    ///
    /// - Parameter element: The element to focus.
    public func focus(_ element: Focusable) {
        pendingFocusID = nil
        focusPreservingPendingIntent(element)
    }

    /// ``focus(_:)`` for the framework's *automatic* focus moves (auto-focus
    /// of a section's first element, the pending-intent resolver itself) —
    /// moves that must not supersede a live pending intent.
    func focusPreservingPendingIntent(_ element: Focusable) {
        guard element.canBeFocused else { return }

        // Focusing the already-focused element is a no-op: a click inside a
        // focused control must not fire a spurious lost/received lifecycle —
        // that would tear down the control's transient state (an open
        // suggestions menu, editing-session callbacks) mid-interaction.
        guard focusedID != element.focusID else { return }

        notifyFocusLost()

        focusedID = element.focusID
        element.onFocusReceived()
        onFocusChange?()
    }

    /// Focuses an element by ID (searches all sections).
    ///
    /// A target that is not registered — off the window of a lazy container,
    /// most likely — becomes a durable pending intent (``pendingFocusID``)
    /// rather than a silent no-op: the next render routes to it (default,
    /// path-derived IDs), renders it so it registers, and focuses it. An ID
    /// that matches nothing expires after a couple of passes.
    ///
    /// - Parameter id: The focus ID of the element to focus.
    public func focus(id: String) {
        pendingFocusID = nil
        for section in sections {
            if let element = section.focusables.first(where: { $0.focusID == id && $0.canBeFocused }) {
                // Also activate the section containing this element
                if activeSectionID != section.id {
                    activeSectionID = section.id
                }
                focus(element)
                return
            }
        }
        pendingFocusID = id
        pendingFocusPassesRemaining = Self.pendingFocusPassBudget
        onFocusChange?()
    }

    /// Clears focus entirely, firing the current element's `onFocusLost`.
    /// Used by `@FocusState`'s setter when a binding is set to its empty value.
    func relinquishFocus() {
        guard focusedID != nil else { return }
        notifyFocusLost()
        focusedID = nil
        onFocusChange?()
    }

    // MARK: - @FocusState bindings

    /// Records that a `.focused(_:equals:)` control (identified by its store's
    /// stable id and the bound `value`) renders with `focusID`. Rebuilt each
    /// frame as the modifiers render, but retained on the manager so a
    /// `@FocusState` read BEFORE those modifiers re-register this frame still
    /// resolves against last frame's mapping. Stamped with the current render
    /// generation for ``pruneFocusRegistry()``.
    func registerFocusBinding(store: String, value: AnyHashable, focusID: String) {
        focusBindings[store, default: [:]][value] =
            FocusBinding(focusID: focusID, generation: focusRenderGeneration)
    }

    /// The value whose bound control currently holds focus, for a store — the
    /// getter behind `@FocusState`. `nil` (the empty value) when none does.
    func focusedValue(forStore store: String) -> AnyHashable? {
        guard let focused = focusedID, let map = focusBindings[store] else { return nil }
        return map.first { $0.value.focusID == focused }?.key
    }

    /// Moves focus to the control bound to `value` for a store, or — when
    /// `value` is `nil` (the empty value) — relinquishes focus if one of the
    /// store's controls currently holds it. The setter behind `@FocusState`,
    /// called from event closures (outside a render pass).
    func setFocusValue(_ value: AnyHashable?, forStore store: String) {
        let map = focusBindings[store] ?? [:]
        if let value, let binding = map[value] {
            focus(id: binding.focusID)
        } else if let focused = focusedID, map.values.contains(where: { $0.focusID == focused }) {
            relinquishFocus()
        }
    }

    /// Declares a store's initial-focus value (from `.defaultFocus`), stamped
    /// with the current render generation.
    func setDefaultFocusValue(
        _ value: AnyHashable, priority: DefaultFocusEvaluationPriority, forStore store: String
    ) {
        focusDefaultValues[store] = DefaultFocusDeclaration(
            value: value, priority: priority, generation: focusRenderGeneration)
    }

    /// Whether a store has a default focus that still wants to steal the initial
    /// focus this pass, so ``register(_:inSection:)`` can hold off the automatic
    /// first-focusable choice and let the default land directly (no transient
    /// focus on the wrong control).
    private var hasUnresolvedDefaultFocus: Bool {
        focusDefaultValues.contains { store, declaration in
            declaration.priority == .userInitiated || !appliedDefaultFocus.contains(store)
        }
    }

    /// Applies each store's declared default focus — the initial focus, after
    /// which the user is in control (`.automatic`), or on every pass
    /// (`.userInitiated`). Called from ``endRenderPass()`` once every `.focused`
    /// binding for the frame has registered.
    ///
    /// An `.automatic` default is a ONE-SHOT: it is consumed on the first pass
    /// it is declared, whether or not its target has a bound control yet. If the
    /// target is present it takes focus; if it is not (a conditionally-shown or
    /// not-yet-windowed control) the shot is spent and the automatic
    /// first-focusable stands — so the default never lies in wait to yank focus
    /// off the user's later choice.
    private func resolvePendingDefaultFocus() {
        for (store, declaration) in focusDefaultValues {
            let isAutomatic = declaration.priority == .automatic
            if isAutomatic && appliedDefaultFocus.contains(store) { continue }
            if isAutomatic { appliedDefaultFocus.insert(store) }
            guard let binding = focusBindings[store]?[declaration.value] else { continue }
            // `focus(id:)` fires the old element's onFocusLost and the new one's
            // onFocusReceived (and no-ops if it is already focused).
            focus(id: binding.focusID)
        }
    }

    /// Drops `@FocusState` registry entries whose control did not render this
    /// pass — keeping the maps bounded to the working set — while retaining this
    /// pass's entries for the next frame's body-top reads. A default whose scope
    /// vanished loses its applied-flag, so re-presenting the scope re-applies it.
    private func pruneFocusRegistry() {
        for (store, var map) in focusBindings {
            map = map.filter { $0.value.generation == focusRenderGeneration }
            if map.isEmpty { focusBindings[store] = nil } else { focusBindings[store] = map }
        }
        for (store, declaration) in focusDefaultValues
        where declaration.generation != focusRenderGeneration {
            focusDefaultValues[store] = nil
            appliedDefaultFocus.remove(store)
        }
    }

    /// Whether a focus ID (default form: `"<prefix>-<identity path>"`)
    /// addresses a control at or below the given identity path.
    ///
    /// Path-boundary-safe: the character after the matched path must be a
    /// component boundary (`/` for a child type, `#` for a conditional
    /// branch) or the end of the ID, so `…#7` never matches `…#70` and a
    /// keyed sibling (`…Row[7]`) never matches its unkeyed prefix. Explicit
    /// `.focusID("…")` strings embed no path and never match — routing to
    /// those without rendering is the identity tax the design doc records
    /// (§12): there is nothing to route by.
    static func focusID(_ id: String, addressesSubtreeAt path: String) -> Bool {
        guard !path.isEmpty, let range = id.range(of: path) else { return false }
        if range.upperBound == id.endIndex { return true }
        let next = id[range.upperBound]
        return next == "/" || next == "#"
    }

    /// Moves focus to the next element within the active section.
    ///
    /// Arrow-key navigation: does **not** wrap at the boundary.
    public func focusNextInSection() {
        moveFocusInSection(direction: .forward, wrap: false)
    }

    /// Moves focus to the previous element within the active section.
    ///
    /// Arrow-key navigation: does **not** wrap at the boundary.
    public func focusPreviousInSection() {
        moveFocusInSection(direction: .backward, wrap: false)
    }

    /// Moves focus to the next focusable element.
    ///
    /// When multiple sections exist, Tab navigates within the current section
    /// first. Only when the current element is the last in its section does
    /// Tab switch to the next section.
    /// When only one section exists, this cycles within it (wrapping).
    public func focusNext() {
        if sections.count > 1 {
            let moved = moveFocusInSection(direction: .forward, wrap: false)
            if !moved { activateNextSection() }
        } else {
            moveFocusInSection(direction: .forward, wrap: true)
        }
    }

    /// Moves focus to the previous focusable element.
    ///
    /// When multiple sections exist, Shift+Tab navigates within the current
    /// section first. Only when the current element is the first in its section
    /// does Shift+Tab switch to the previous section.
    /// When only one section exists, this cycles within it (wrapping).
    public func focusPrevious() {
        if sections.count > 1 {
            let moved = moveFocusInSection(direction: .backward, wrap: false)
            if !moved { activatePreviousSection() }
        } else {
            moveFocusInSection(direction: .backward, wrap: true)
        }
    }

    /// Returns whether the given element is currently focused.
    ///
    /// - Parameter element: The element to check.
    /// - Returns: True if the element is focused.
    public func isFocused(_ element: Focusable) -> Bool {
        focusedID == element.focusID
    }

    /// Returns whether an element with the given ID is currently focused.
    ///
    /// - Parameter id: The focus ID to check.
    /// - Returns: True if the element is focused.
    public func isFocused(id: String) -> Bool {
        focusedID == id
    }

    /// Returns whether the given section is currently active.
    ///
    /// - Parameter sectionID: The section identifier to check.
    /// - Returns: True if the section is active.
    public func isActiveSection(_ sectionID: String) -> Bool {
        activeSectionID == sectionID
    }

    /// Dispatches a key event through the focus system.
    ///
    /// Navigation model:
    /// - **Tab / Shift+Tab**: Cycles between sections (or within a single section).
    /// - **Up / Down arrows**: Cycles between focusable elements within the active section.
    /// - **Enter / Space**: Dispatched to the focused element for activation.
    /// - **Other keys**: Dispatched to the focused element.
    ///
    /// - Parameter event: The key event to dispatch.
    /// - Returns: True if the event was handled.
    @discardableResult
    public func dispatchKeyEvent(_ event: KeyEvent) -> Bool {
        // Dispatch to focused element first — let it handle keys like Up/Down/Left/Right.
        // If element consumes the event, stop here.
        if let focused = currentFocused {
            debugFocusLog("""
                dispatchKeyEvent \(event.key)
                  focusedID: \(focusedID ?? "nil")
                  activeSection: \(activeSectionID ?? "nil")
                  sections: \(debugSectionsSummary())
                  currentFocused.focusID: \(focused.focusID)
                """)
            if focused.handleKeyEvent(event) {
                // Bump the interaction generation so any
                // surrounding ScrollView re-renders this frame
                // and snaps the viewport back to the focused
                // control (Phase 2 of "follow the focused
                // control").
                focusedInteractionGeneration &+= 1
                return true
            }
        } else {
            debugFocusLog("""
                dispatchKeyEvent \(event.key)
                  focusedID: \(focusedID ?? "nil")
                  activeSection: \(activeSectionID ?? "nil")
                  sections: \(debugSectionsSummary())
                  currentFocused: nil
                """)
        }

        // A Page Up/Down or Home/End the focused element didn't consume scrolls
        // the enclosing scroll container — so the page scrolls even while a
        // non-scrollable control (e.g. a Button) inside a ScrollView holds focus,
        // and even when nothing is focused at all. (Plain Up/Down remain focus
        // navigation, handled below.)
        switch event.key {
        case .pageUp, .pageDown, .home, .end:
            if scrollActiveSection(for: event.key) {
                // Deliberately NOT bumping `focusedInteractionGeneration` here.
                //
                // That counter means "the focused control just consumed a key,
                // so scroll it back into view". This branch is the opposite
                // case: the focused control did NOT consume the key, and we
                // scrolled the container on its behalf — the whole point is to
                // move AWAY from it. Bumping made the reveal snap the viewport
                // straight back to the focused control on the same frame, so
                // Page Up/Down/Home/End read as completely dead whenever a
                // non-scrollable control (a Button, a text field) held focus
                // inside a scrollable. The scroll was happening and being undone
                // before it was ever drawn.
                return true
            }
        default:
            break
        }

        // Tab navigation: cycle sections (or elements within single section)
        if event.key == .tab {
            if event.shift {
                focusPrevious()
            } else {
                focusNext()
            }
            return true
        }

        // Arrow keys: navigate within the active section (fallback if element didn't handle)
        // Up/Left go to previous, Down/Right go to next
        switch event.key {
        case .up, .left:
            focusPreviousInSection()
            return true
        case .down, .right:
            focusNextInSection()
            return true
        default:
            break
        }

        return false
    }

    /// Scrolls the active section's enclosing scroll container for a
    /// page/home/end key the focused element didn't consume.
    ///
    /// Scrolls the viewport directly through ``ScrollableOffsetState`` (so it
    /// never disturbs a list's selection — it is a viewport move, not a focus
    /// move), and only when the active section has exactly one scroller that can
    /// currently move. That one-scroller guard keeps it unambiguous (the common
    /// "a single ScrollView/List wraps the page" case) and avoids scrolling the
    /// wrong container when several are on screen.
    ///
    /// - Returns: `true` if a scroll container was moved.
    private func scrollActiveSection(for key: Key) -> Bool {
        guard let section = activeSection else { return false }
        let focusedID = currentFocused?.focusID
        let scrollers = section.focusables.compactMap { focusable -> (any ScrollableOffsetState)? in
            guard focusable.focusID != focusedID,
                let scroller = focusable as? any ScrollableOffsetState,
                scroller.maxOffset > 0
            else { return nil }
            return scroller
        }
        guard scrollers.count == 1, let scroller = scrollers.first else { return false }

        let page = max(1, scroller.viewportHeight)
        switch key {
        case .pageUp: scroller.scroll(by: -page)
        case .pageDown: scroller.scroll(by: page)
        case .home: scroller.scrollOffset = 0
        case .end: scroller.scrollOffset = scroller.maxOffset
        default: return false
        }
        return true
    }
}

// MARK: - Internal API

extension FocusManager {
    /// Registers a focus section.
    ///
    /// If a section with the same ID already exists, it is reused (not duplicated).
    /// The first registered section becomes the active section automatically.
    ///
    /// - Parameter id: The unique section identifier.
    func registerSection(id: String) {
        guard !sections.contains(where: { $0.id == id }) else { return }
        let section = FocusSection(id: id)
        sections.append(section)

        // Auto-activate first section
        if activeSectionID == nil {
            activeSectionID = id
        }
    }

    /// Marks a section as belonging to a presented modal / alert (an
    /// input-grabbing surface). Called by the presentation modifiers each render
    /// — the set is cleared in `beginRenderPass`, so an unmarked (dismissed)
    /// modal's section naturally stops grabbing input. See ``activeSectionIsModal``.
    func markSectionModal(id: String) {
        modalSectionIDs.insert(id)
    }

    /// Records which device drove the event now being dispatched. Called by the
    /// app's event funnel, before the event reaches any handler.
    func noteInputSource(_ source: InputSource) {
        lastInputSource = source
    }

    /// Declares that `id` may rest with nothing focused — see
    /// ``optionalFocusSectionIDs``. Re-mark it every render while it applies.
    func markSectionFocusOptional(id: String) {
        optionalFocusSectionIDs.insert(id)
    }

    /// Returns the section with the given ID, or nil if not found.
    ///
    /// - Parameter id: The section identifier.
    /// - Returns: The focus section, or nil.
    func section(id: String) -> FocusSection? {
        sections.first { $0.id == id }
    }

    /// Activates the next section (wrapping around).
    ///
    /// When switching sections, the first focusable element in the new
    /// section receives focus automatically.
    func activateNextSection() {
        cycleSection(direction: .forward)
    }

    /// Activates the previous section (wrapping around).
    ///
    /// When switching sections, the first focusable element in the new
    /// section receives focus automatically.
    func activatePreviousSection() {
        cycleSection(direction: .backward)
    }

    /// Activates a specific section by ID.
    ///
    /// If the section was not previously active, focus moves to the section's
    /// first focusable element. If the section is *already* the active one,
    /// the current `focusedID` is preserved across re-renders — overlay
    /// surfaces (`ModalPresentationModifier`, an open `Picker` drop-down)
    /// call `registerSection` + `activateSection` on every frame, and
    /// `beginRenderPass` has already cleared the section's focusables by
    /// the time activateSection runs. Resetting focus here would snap the
    /// user's focus back to the first child of the (still-empty) section.
    /// `endRenderPass` validates the stale `focusedID` once the section
    /// has been re-populated, so it is safe to defer the choice.
    ///
    /// - Parameters:
    ///   - id: The section identifier to activate.
    ///   - focusBoundary: When non-`nil`, focus lands on the section's boundary
    ///     element for a directional move — its first focusable for `.forward`,
    ///     its last for `.backward` — rather than on its remembered element.
    ///     Tab / Shift+Tab section cycling passes this so the ring keeps
    ///     advancing; modal presentation leaves it `nil` to resume where the
    ///     user left off.
    func activateSection(id: String, focusBoundary: FocusDirection? = nil) {
        guard sections.contains(where: { $0.id == id }) else { return }

        // Re-activating the section we're already on is a no-op: leave
        // `focusedID` alone and let `endRenderPass` validate it once the
        // section's focusables have been re-registered during this render.
        if activeSectionID == id {
            return
        }

        // Remember the section we're leaving so returning to it restores focus,
        // and record it as the revert target for `deactivateSection(id:)`.
        rememberFocusForActiveSection()
        if let leaving = activeSectionID {
            sectionRevertTarget[id] = leaving
        }

        // Notify current focused element
        notifyFocusLost()

        activeSectionID = id
        focusedID = nil

        // Enter at the directional boundary when cycling with Tab / Shift+Tab;
        // otherwise restore the section's remembered focus.
        if let focusBoundary {
            focusBoundaryOfActiveSection(direction: focusBoundary)
        } else {
            restoreFocusForActiveSection()
        }

        onFocusChange?()
    }

    /// Deactivates `id` if it is the active section, reverting to the section it
    /// was activated over (or the default), and restoring that section's
    /// remembered focus.
    ///
    /// Called when a transient overlay (a modal) is dismissed. The focus is set
    /// *directly* from memory — the reverted-to section's elements may not be
    /// re-registered until later in this render pass, and setting `focusedID`
    /// non-nil now both targets the right element and stops the first
    /// re-registered element from grabbing focus (see `register(_:inSection:)`).
    /// `endRenderPass` validates the result once registration completes.
    public func deactivateSection(id: String) {
        guard activeSectionID == id else { return }
        rememberFocusForActiveSection()
        let target = sectionRevertTarget[id] ?? Self.defaultSectionID
        sectionRevertTarget[id] = nil
        activeSectionID = target
        focusedID = sectionFocusMemory[target]
        onFocusChange?()
    }

    /// Saves the active section's currently focused element so it can be
    /// restored when that section is next activated.
    private func rememberFocusForActiveSection() {
        if let active = activeSectionID, let focused = focusedID {
            sectionFocusMemory[active] = focused
        }
    }

    /// Focuses the active section's remembered element if it is still present
    /// and focusable; otherwise focuses the section's first focusable element.
    private func restoreFocusForActiveSection() {
        guard let section = activeSection else { return }
        if let saved = sectionFocusMemory[section.id],
            let element = section.focusables.first(where: { $0.focusID == saved && $0.canBeFocused })
        {
            focusPreservingPendingIntent(element)
        } else if let firstFocusable = section.focusables.first(where: { $0.canBeFocused }) {
            focusPreservingPendingIntent(firstFocusable)
        }
    }

    /// Focuses the active section's boundary element for a directional move:
    /// the first focusable when moving `.forward`, the last when moving
    /// `.backward`.
    ///
    /// Used when Tab / Shift+Tab crosses a section boundary, so the new section
    /// is entered at its edge rather than at whatever element was remembered
    /// from a previous visit — otherwise the ring collapses into a two-element
    /// oscillation between adjacent sections' remembered elements.
    private func focusBoundaryOfActiveSection(direction: FocusDirection) {
        guard let section = activeSection else { return }
        let available = section.focusables.filter { $0.canBeFocused }
        guard let boundary = direction == .forward ? available.first : available.last else { return }
        focusedID = boundary.focusID
        boundary.onFocusReceived()
    }

    /// Prepares the focus manager for a new render pass.
    ///
    /// Clears all sections and focusable elements so they can be re-registered
    /// from the current view tree. The active section ID and focused element ID
    /// are **preserved** — if they still exist after the render pass, focus
    /// continues seamlessly. If they don't, the first available element is
    /// auto-focused.
    ///
    /// Call this at the start of each render pass instead of ``clear()``.
    func beginRenderPass() {
        sections.removeAll()
        // Modal sections are re-marked each render by the presentation modifiers;
        // clearing here means a dismissed modal (which no longer renders, so no
        // longer re-marks) stops grabbing input on the very next frame.
        modalSectionIDs.removeAll()
        optionalFocusSectionIDs.removeAll()
        // A new generation so this pass's @FocusState registrations can be told
        // apart from prior ones (see `pruneFocusRegistry`). The registry itself
        // is NOT cleared here — a body-top read must resolve against last frame's
        // mapping before this frame's `.focused` modifiers re-register.
        focusRenderGeneration &+= 1
        // activeSectionID and focusedID are intentionally preserved.
        // They will be validated after the render pass re-registers sections.
    }

    /// Validates focus state after a render pass.
    ///
    /// If the previously active section no longer exists, the first
    /// registered section is activated. If the previously focused element
    /// no longer exists, the first focusable in the active section is focused.
    ///
    /// Every focus decision here — drop-the-dead, restore-the-remembered,
    /// resolve-the-default, focus-the-first — has to happen at the END of the
    /// pass, because only then is the set of registered elements complete. But
    /// that means the frame those decisions apply to has ALREADY been drawn:
    /// the newly focused control rendered itself as unfocused, and in a
    /// demand-driven loop nothing would ever draw it again. So any focus this
    /// pass assigns MUST announce itself, which is what schedules the repaint
    /// (``onFocusChange`` → `appState.setNeedsRender()`). Without it a page
    /// whose focus lands here — anything with no `.defaultFocus` — sits there
    /// showing no focus indicator at all until the user presses a key, and that
    /// keypress then moves focus off the element the user never saw it on.
    func endRenderPass() {
        let focusOnEntry = focusedID
        // Validate active section. If the active section vanished (e.g. a modal
        // overlay that activated its own section was dismissed), remember its
        // focus, fall back to the first section, and restore THAT section's
        // remembered focus — so the page returns to where it was, not its top.
        if let activeID = activeSectionID,
            !sections.contains(where: { $0.id == activeID })
        {
            rememberFocusForActiveSection()
            activeSectionID = sections.first?.id
            focusedID = nil
            restoreFocusForActiveSection()
        }

        // Drop focus that is gone or no longer focusable. "Present but not
        // focusable" is treated like "gone": some elements register with a
        // dynamic `canBeFocused` (a ScrollView is focusable only while its
        // content overflows), and focus resting on one would silently eat key
        // events while showing no focus indicator anywhere.
        if let focusID = focusedID, let section = activeSection {
            let focused = section.focusables.first { $0.focusID == focusID }
            if focused == nil || focused?.canBeFocused == false {
                self.focusedID = nil
            }
        }

        // `.defaultFocus` overrides the automatic first-focusable choice for the
        // INITIAL focus — applied here, after this pass's `.focused` bindings
        // have all registered (so there is no first-frame flash) and BEFORE the
        // first-focusable fallback (so the default target takes focus directly,
        // never via a transient focus on the wrong control). `register` holds
        // off auto-focusing while a default is unresolved, so `focusedID` is
        // still nil here on that first frame.
        resolvePendingDefaultFocus()

        // Auto-focus the first focusable if, after validation and any default,
        // nothing holds focus.
        if focusedID == nil, let section = activeSection,
            !optionalFocusSectionIDs.contains(section.id),
            let firstFocusable = section.focusables.first(where: { $0.canBeFocused })
        {
            focusPreservingPendingIntent(firstFocusable)
        }

        // Drop `@FocusState` entries whose control left the tree this pass.
        pruneFocusRegistry()

        // A pending intent unresolved by this pass either just triggered its
        // routing render (give it that one) or matches nothing — bound it.
        if pendingFocusID != nil {
            pendingFocusPassesRemaining -= 1
            if pendingFocusPassesRemaining <= 0 {
                pendingFocusID = nil
            }
        }

        // Repaint the frame that was drawn before these decisions were made —
        // see the note on this method. Guarded on an actual change, or a steady
        // frame would request another one forever and the loop would never idle.
        // (The helpers above announce their own moves; this catches the paths
        // that only DROP focus, which is just as invisible.)
        if focusedID != focusOnEntry { onFocusChange?() }
    }
}

// MARK: - Private Helpers

/// The direction in which focus moves.
enum FocusDirection {
    case forward, backward
}

extension FocusManager {
    /// Cycles the active section in the given direction.
    fileprivate func cycleSection(direction: FocusDirection) {
        guard sections.count > 1 else { return }

        let startIndex: Int
        if let activeID = activeSectionID,
            let currentIndex = sections.firstIndex(where: { $0.id == activeID })
        {
            startIndex = currentIndex
        } else {
            // No active section: enter the ring just "before" the first
            // candidate in the travel direction, so the walk below starts at
            // the first / last section exactly as the old fixed pick did.
            startIndex = direction == .forward ? sections.count - 1 : 0
        }

        // Walk the ring in the travel direction, skipping sections with no
        // currently-focusable element — activating one would strand the app
        // with nothing focused (the boundary entry has nothing to land on),
        // making the focus indicator vanish for a keypress. A section whose
        // controls are all disabled (or all gone this frame) is simply not a
        // Tab stop, matching desktop focus-ring conventions.
        var index = startIndex
        for _ in 1..<sections.count {
            switch direction {
            case .forward:
                index = (index + 1) % sections.count
            case .backward:
                index = index == 0 ? sections.count - 1 : index - 1
            }
            if sections[index].focusables.contains(where: { $0.canBeFocused }) {
                activateSection(id: sections[index].id, focusBoundary: direction)
                return
            }
        }
        // No other section has anything focusable; stay where we are.
    }

    /// Moves focus within the active section.
    ///
    /// - Parameters:
    ///   - direction: The direction in which to move focus.
    ///   - wrap: When `true`, focus wraps around from the last element to the
    ///     first (and vice versa). When `false`, focus stops at the boundary
    ///     and the method returns `false`.
    /// - Returns: `true` if focus moved to a new element, `false` if the
    ///   boundary was reached (and `wrap` is `false`) or no element is available.
    @discardableResult
    fileprivate func moveFocusInSection(direction: FocusDirection, wrap: Bool = true) -> Bool {
        guard let section = activeSection else { return false }

        let available = section.focusables.filter { $0.canBeFocused }
        guard !available.isEmpty else { return false }

        if let currentID = focusedID,
            let currentIndex = available.firstIndex(where: { $0.focusID == currentID })
        {
            let targetIndex: Int
            switch direction {
            case .forward:
                if currentIndex == available.count - 1 {
                    guard wrap else { return false }
                    targetIndex = 0
                } else {
                    targetIndex = currentIndex + 1
                }
            case .backward:
                if currentIndex == 0 {
                    guard wrap else { return false }
                    targetIndex = available.count - 1
                } else {
                    targetIndex = currentIndex - 1
                }
            }
            focus(available[targetIndex])
            return true
        } else {
            let fallbackIndex = direction == .forward ? 0 : available.count - 1
            focus(available[fallbackIndex])
            return true
        }
    }

    /// The active section's registered focus IDs in ring order — the
    /// per-frame enumeration (§5d of "Locating things without drawing
    /// them"). Internal: tests assert exactly what the last walk registered.
    func registeredFocusIDsInActiveSection() -> [String] {
        activeSection?.focusables.map(\.focusID) ?? []
    }

    /// The active section's focus IDs that can actually BE focused, in ring
    /// order — what an arrow or a jump key walks.
    ///
    /// Distinct from ``registeredFocusIDsInActiveSection()``, which reports
    /// everything that registered: a disabled row registers but declines focus,
    /// and a menu that overflows also registers its `ScrollView`. Either would
    /// make "jump to the last item" land somewhere that is not an item.
    func focusableIDsInActiveSection() -> [String] {
        activeSection?.focusables.filter(\.canBeFocused).map(\.focusID) ?? []
    }

    /// Diagnostic one-line summary of the focus manager's section
    /// state. Used by the gated logging across the framework when
    /// `TUIKIT_DEBUG_FOCUS=1`; not part of the public API.
    internal func debugSectionsSummary() -> String {
        let parts = sections.map { section -> String in
            let active = section.id == activeSectionID ? "*" : ""
            let ids = section.focusables.map(\.focusID).joined(separator: ",")
            return "\(active)\(section.id)[\(ids)]"
        }
        return parts.joined(separator: " | ")
    }

    /// Notifies the currently focused element that it lost focus.
    fileprivate func notifyFocusLost() {
        guard let currentID = focusedID else { return }
        for section in sections {
            if let current = section.focusables.first(where: { $0.focusID == currentID }) {
                current.onFocusLost()
                return
            }
        }
    }
}

// MARK: - Focus Manager Environment Key

/// Environment key for the focus manager.
private struct FocusManagerKey: EnvironmentKey {
    // No shared default instance — consistent with the other runtime services
    // (lifecycle, keyEventDispatcher, mouseEventDispatcher are all nil-default
    // Optionals). A single shared default would let every context that doesn't
    // install its own focus manager register into the SAME manager, leaking
    // focus state across isolated renders (and across parallel test contexts).
    // The real app installs one via `RenderLoop.makeRenderContext`; a nil manager
    // means "no focus system", so controls render unfocused and nothing
    // auto-focuses.
    static let defaultValue: FocusManager? = nil
}

extension EnvironmentValues {
    /// The focus manager for managing keyboard focus, or `nil` when no focus
    /// system is installed (an isolated/measure render, a dimmed backdrop, or a
    /// test that doesn't exercise focus). The live app always installs one.
    ///
    /// Access via `context.environment.focusManager` in `renderToBuffer(context:)`.
    public var focusManager: FocusManager? {
        get { self[FocusManagerKey.self] }
        set { self[FocusManagerKey.self] = newValue }
    }
}
