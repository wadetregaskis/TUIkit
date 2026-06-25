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

    /// For each section that was activated *over* another, the section to revert
    /// to when it is deactivated (e.g. a modal section reverts to the page's).
    private var sectionRevertTarget: [String: String] = [:]

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
        let targetID = sectionID ?? activeSectionID ?? Self.defaultSectionID

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
        if targetID == activeSectionID && focusedID == nil && element.canBeFocused {
            focus(element)
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
    }

    /// Focuses a specific element.
    ///
    /// - Parameter element: The element to focus.
    public func focus(_ element: Focusable) {
        guard element.canBeFocused else { return }

        notifyFocusLost()

        focusedID = element.focusID
        element.onFocusReceived()
        onFocusChange?()
    }

    /// Focuses an element by ID (searches all sections).
    ///
    /// - Parameter id: The focus ID of the element to focus.
    public func focus(id: String) {
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
                focusedInteractionGeneration &+= 1
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
    /// - Parameter id: The section identifier to activate.
    func activateSection(id: String) {
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

        // Restore the new section's remembered focus, else its first element.
        restoreFocusForActiveSection()

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
            focusedID = element.focusID
            element.onFocusReceived()
        } else if let firstFocusable = section.focusables.first(where: { $0.canBeFocused }) {
            focusedID = firstFocusable.focusID
            firstFocusable.onFocusReceived()
        }
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
        // activeSectionID and focusedID are intentionally preserved.
        // They will be validated after the render pass re-registers sections.
    }

    /// Validates focus state after a render pass.
    ///
    /// If the previously active section no longer exists, the first
    /// registered section is activated. If the previously focused element
    /// no longer exists, the first focusable in the active section is focused.
    func endRenderPass() {
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

        // Validate focused element
        if let focusID = focusedID, let section = activeSection {
            if !section.focusables.contains(where: { $0.focusID == focusID }) {
                // Previously focused element is gone — auto-focus first available
                self.focusedID = nil
                if let firstFocusable = section.focusables.first(where: { $0.canBeFocused }) {
                    self.focusedID = firstFocusable.focusID
                    firstFocusable.onFocusReceived()
                }
            }
        } else if focusedID == nil, let section = activeSection,
            let firstFocusable = section.focusables.first(where: { $0.canBeFocused })
        {
            self.focusedID = firstFocusable.focusID
            firstFocusable.onFocusReceived()
        }
    }
}

// MARK: - Private Helpers

/// The direction in which focus moves.
private enum FocusDirection {
    case forward, backward
}

extension FocusManager {
    /// Cycles the active section in the given direction.
    fileprivate func cycleSection(direction: FocusDirection) {
        guard sections.count > 1 else { return }

        let sectionIndex: Int
        if let activeID = activeSectionID,
            let currentIndex = sections.firstIndex(where: { $0.id == activeID })
        {
            switch direction {
            case .forward:
                sectionIndex = (currentIndex + 1) % sections.count
            case .backward:
                sectionIndex = currentIndex == 0 ? sections.count - 1 : currentIndex - 1
            }
        } else {
            sectionIndex = direction == .forward ? 0 : sections.count - 1
        }

        activateSection(id: sections[sectionIndex].id)
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
