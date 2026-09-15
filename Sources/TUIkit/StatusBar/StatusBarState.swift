//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarState.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Quit Behavior

/// Controls when the quit shortcut (`q`) is active.
public enum QuitBehavior: Sendable {
    /// Quit works from any screen.
    ///
    /// Pressing `q` will always exit the application, regardless of
    /// the current navigation state.
    case always

    /// Quit only works from the root/main screen.
    ///
    /// Pressing `q` will only exit when no context is pushed onto the
    /// status bar stack. On subpages, `q` does nothing, allowing the
    /// app to handle navigation (e.g., ESC to go back).
    case rootOnly
}

// MARK: - Status Bar State

/// Manages the status bar state for the running application.
///
/// This class is created by the `AppRunner` and injected into the
/// environment for views to access.
///
/// # Usage
///
/// ```swift
/// // In renderToBuffer(context:):
/// let statusBar = context.environment.statusBar
/// statusBar.setItems([
///     StatusBarItem(shortcut: "⎋", label: "cancel")
/// ])
/// ```
public final class StatusBarState: @unchecked Sendable {
    // MARK: - Render Invalidation

    /// The app state used to trigger re-renders when status bar items change.
    private let appState: AppState

    // MARK: - User Items

    /// Stack of user contexts with their items (legacy push/pop API).
    private var userContextStack: [(context: String, items: [any StatusBarItemProtocol])] = []

    /// Global user items that are always shown (lowest priority).
    private var userGlobalItems: [any StatusBarItemProtocol] = []

    /// Global items a `.statusBarItems` modifier declared during THIS render
    /// pass, cleared at the start of every one.
    ///
    /// Kept apart from ``userGlobalItems``, which an app sets imperatively and
    /// expects to persist. A declaration in the view tree is only true while
    /// the view is in the tree, and the tree is rebuilt every frame — so items
    /// declared by a page that has gone away have to go with it. They did not:
    /// pressing Escape back to the Example's menu left every shortcut of the
    /// page just left sitting on the bar, because the modifier wrote straight
    /// into `userGlobalItems` and nothing ever cleared it.
    ///
    /// (Section items were already right — ``registerSectionItems`` is cleared
    /// per pass, and has been since the modifier's own comment was written. It
    /// is the branch for a page NOT inside a `.focusSection()` that leaked, and
    /// that is the common one.)
    private var declaredGlobalItems: [any StatusBarItemProtocol] = []

    /// The global items in force: this pass's declaration when there is one,
    /// and the app's own standing set otherwise.
    ///
    /// Precedence rather than a merge, because that is what the modifier did
    /// when it wrote into the same property — it replaced.
    private var globalItems: [any StatusBarItemProtocol] {
        declaredGlobalItems.isEmpty ? userGlobalItems : declaredGlobalItems
    }

    // MARK: - Section Items (Declarative API)

    /// Items registered per focus section during rendering.
    ///
    /// Each entry maps a section ID to its declared items and composition strategy.
    /// Rebuilt every render pass by ``StatusBarItemsModifier``.
    private var sectionItems: [(sectionID: String, items: [any StatusBarItemProtocol], composition: StatusBarItemComposition)] = []

    /// The focus manager used to determine the active section.
    ///
    /// Set by `RenderLoop` at the start of each render pass.
    weak var focusManager: FocusManager?

    /// The ID of the currently active focus section, read from the FocusManager.
    private var activeFocusSectionID: String? {
        focusManager?.activeSectionIdentifier
    }

    // MARK: - System Items Configuration

    /// Whether system items are shown at all.
    ///
    /// Set to `false` to hide all system items (quit, help, theme).
    /// Default is `true`.
    public var showSystemItems: Bool = true

    /// Whether the appearance item (`a`) is shown.
    ///
    /// When `true`, pressing `a` cycles through available appearances (border styles).
    /// Default is `false`.
    public var showAppearanceItem: Bool = false

    /// Whether the theme item (`t`) is shown.
    ///
    /// When `true`, pressing `t` cycles through available themes.
    /// Default is `false`.
    public var showThemeItem: Bool = false

    /// Whether the bar carries an Escape entry when something claims the key.
    ///
    /// Return and Escape are the two keys common enough — and special
    /// enough — to be worth a permanent place, so both are on by default. An
    /// app that wants the space back turns them off with
    /// ``View/statusBarSystemItems(theme:appearance:returnKey:escapeKey:)``.
    ///
    /// Presence only. Turning this off changes nothing about what the key
    /// DOES: the claim that labels the entry is also what routes Escape to the
    /// surface that claimed it, and that is independent of whether the bar
    /// shows anything.
    public var showEscapeItem: Bool = true

    /// Whether the bar carries a Return entry when something claims the key.
    /// See ``showEscapeItem``.
    public var showReturnItem: Bool = true

    /// Controls when the quit shortcut is active.
    ///
    /// - `.always`: Quit works from any screen (default).
    /// - `.rootOnly`: Quit only works when no context is pushed (main screen).
    ///
    /// When set to `.rootOnly`, pressing the quit key on a subpage does nothing,
    /// allowing the app to handle navigation (e.g., go back) instead.
    public var quitBehavior: QuitBehavior = .always

    /// The keyboard shortcut used to quit the application.
    ///
    /// Defaults to `.q` (pressing `q` quits). Change this to use a different key:
    ///
    /// ```swift
    /// statusBar.quitShortcut = .escape   // ⎋ quit
    /// statusBar.quitShortcut = .ctrlQ    // ⌃q quit
    /// ```
    ///
    /// The status bar display updates automatically.
    public var quitShortcut: QuitShortcut = .q

    // MARK: - Appearance

    /// The current status bar style.
    ///
    /// Defaults to ``ChromeStyle/bordered`` — a box, like a container view —
    /// which the app header now matches. Set both at once with
    /// ``Scene/chromeStyle(_:)``.
    public var style: ChromeStyle = .bordered

    /// The horizontal alignment of items.
    public var alignment: StatusBarAlignment = .justified

    /// The color for shortcut keys, or `nil` (the default) for the palette's
    /// accent.
    ///
    /// Resolved against the palette each time the bar is drawn, so a palette role
    /// follows a change of theme. Any colour set here is drawn as set.
    public var highlightColor: Color?

    /// The color for labels, or `nil` (the default) for the palette's foreground.
    ///
    /// Resolved against the palette each time the bar is drawn, like
    /// ``highlightColor``.
    public var labelColor: Color?

    // MARK: - Transient Modal Overrides

    /// While non-nil, any rendered status-bar item bound to the escape key
    /// (an item whose shortcut is ``Shortcut/escape``) displays this label
    /// in place of its declared one.
    ///
    /// Useful for transient modes — an open drop-down menu, an inline
    /// editor — where ESC should still fire the same handler the page set
    /// up (`back`, `cancel`, …) but the user should be told that *right
    /// now* the key closes the transient surface.
    ///
    /// Setting the property goes through this accessor so the active label
    /// pulled by the renderer always reflects the most recent caller.
    /// Clearing the modal (set to nil) restores the underlying item label.
    public var escapeLabelOverride: String?

    /// Whether the surface that claimed ESC (``escapeLabelOverride``) is an
    /// input-grabbing transient surface — an open drop-down menu, a
    /// suggestions pop-up — whose presence should also suppress the global
    /// app-chrome shortcuts (theme/appearance cycling), exactly like a modal.
    ///
    /// `true` (the default, restored every frame) preserves that modal
    /// behaviour. A lightweight claim — a multi-selection list offering ESC
    /// to clear its selection — sets this `false` alongside the label: only
    /// the ESC key itself is re-routed, everything else behaves normally.
    /// Meaningless while ``escapeLabelOverride`` is `nil`.
    public var escapeClaimGrabsInput = true

    /// Whether item ACTIONS are suppressed for this frame — set, alongside
    /// ``escapeLabelOverride``, by an open transient surface that does NOT
    /// switch the active focus section (the Picker drop-down): the items on
    /// the bar still describe the page BEHIND the surface, and firing them
    /// under it is how typing a lettered shortcut over an open drop-down
    /// navigated the page out from under it. Surfaces that switch sections
    /// (modals, popovers) never need this — the section switch already swaps
    /// the bar's items for their own. Reset every frame with the override.
    public var itemActionsSuppressed = false

    /// What Return would do to whatever holds the focus right now, or `nil`
    /// when nothing has said.
    ///
    /// The Return counterpart of ``escapeLabelOverride``, and it exists for the
    /// same reason: a page declares one item for the key and the key means
    /// something different depending on what is focused. "show" is right over
    /// the row that opens a dialog and wrong over the toggle beside it, and the
    /// page cannot know which is which.
    ///
    /// Published by the focused control each render (see
    /// `FocusRegistration.publishActivationLabel(_:context:isFocused:)`) and
    /// cleared at the top of every frame, so a control that lost the focus
    /// never leaves its verb behind. A control that does nothing with Return —
    /// a slider, a stepper — publishes nothing, and the page's own label
    /// stands.
    public var activationLabelOverride: String?

    /// The `id` of the status-bar item the mouse cursor is
    /// currently hovering over, or `nil` if the cursor isn't on
    /// any item.
    ///
    /// Flipped by `_StatusBarCore`'s per-item mouse handler in
    /// response to the dispatcher's synthetic `.entered` /
    /// `.exited` events. The renderer reads it to apply a
    /// hover-bumped tint on the matching item.
    public var hoveredItemID: String?

    /// Creates a new status bar state.
    ///
    /// - Parameter appState: The app state instance for triggering re-renders.
    public init(appState: AppState) {
        self.appState = appState
    }

    /// Creates a status bar state with a default `AppState` instance.
    ///
    /// Used for environment key defaults and testing only.
    internal convenience init() {
        self.init(appState: AppState())
    }

    /// Whether we are at the root level (no context pushed).
    public var isAtRoot: Bool {
        userContextStack.isEmpty
    }

    /// Whether quit is currently allowed based on `quitBehavior`.
    public var isQuitAllowed: Bool {
        switch quitBehavior {
        case .always: return true
        case .rootOnly: return isAtRoot
        }
    }

    /// The current system items based on configuration flags.
    public var currentSystemItems: [StatusBarItem] {
        guard showSystemItems else { return [] }

        var items: [StatusBarItem] = []
        if isQuitAllowed {
            // Localize the displayed quit label only when it's the framework
            // default; a custom `QuitShortcut` (e.g. label "exit") keeps its
            // own label verbatim. Resolving here (not at construction) means a
            // runtime language switch re-localizes it live.
            let quitLabel = quitShortcut.label == QuitShortcut.q.label
                ? LocalizationService.shared.string(for: LocalizationKey.StatusBar.quit)
                : quitShortcut.label
            items.append(
                StatusBarItem(
                    shortcut: quitShortcut.shortcutSymbol,
                    label: quitLabel,
                    order: .quit
                )
            )
        }
        if showAppearanceItem { items.append(SystemStatusBarItem.appearance) }
        if showThemeItem { items.append(SystemStatusBarItem.theme) }
        // The two common keys appear only while something has said what they
        // do this frame — a focused control's verb, a presented surface's
        // claim. Nothing said, nothing shown: an entry for a key that will not
        // be handled is worse than no entry, and the bar cannot tell what an
        // undeclared `onKeyPress` closure would do with the key.
        //
        // A page that publishes its OWN escape or return item wins the shortcut
        // dedup below and keeps its action; these are the fallback for a page
        // that has not.
        if showEscapeItem, let label = escapeLabelOverride {
            items.append(SystemStatusBarItem.escape(label: label))
        }
        if showReturnItem, let label = activationLabelOverride {
            items.append(SystemStatusBarItem.returnKey(label: label))
        }
        return items
    }

    /// The current user items resolved from focus sections, context stack, or global items.
    public var currentUserItems: [any StatusBarItemProtocol] {
        if !sectionItems.isEmpty, let activeSectionID = activeFocusSectionID {
            return resolvedSectionItems(for: activeSectionID)
        }
        if let topContext = userContextStack.last { return topContext.items }
        return globalItems
    }

    /// All currently active items for rendering and event handling.
    public var currentItems: [any StatusBarItemProtocol] {
        let userShortcuts = Set(currentUserItems.map { $0.shortcut })
        let filteredSystemItems = currentSystemItems.filter { !userShortcuts.contains($0.shortcut) }
        let sortedUserItems = currentUserItems.sorted { $0.order < $1.order }
        return sortedUserItems + filteredSystemItems
    }

    /// Whether the status bar has any items to display.
    public var hasItems: Bool { !currentItems.isEmpty }

    /// Whether there are any user items (ignoring system items).
    public var hasUserItems: Bool { !currentUserItems.isEmpty }

    /// Whether the bar has anything to draw this frame: an item, or a tooltip row.
    ///
    /// The one question `height` and the run loop's decision to build the bar
    /// both ask, so it is asked in one place. It used to be spelled twice, and
    /// only one spelling learned about the tooltip: an item-less bar showing one
    /// took its rows from the page and was never built to draw in them, so they
    /// were erased to the terminal's own background and the tooltip showed
    /// nowhere.
    var hasContent: Bool { hasItems || !tooltipLines.isEmpty }

    /// The height of the status bar in lines, or 0 when it has nothing to show.
    ///
    /// A tooltip row counts, and counts even with no items: a bar that is
    /// otherwise empty still has to make room for one, or the tooltip is
    /// computed and then drawn nowhere.
    public var height: Int {
        guard hasContent else { return 0 }
        return style.barHeight(contentRows: (hasItems ? 1 : 0) + tooltipLines.count)
    }

    /// This frame's tooltip, wrapped to the bar's content width — empty when no
    /// tooltip is showing or the showing one is a popover.
    ///
    /// Resolved by the run loop BEFORE ``height`` is read, which is what makes
    /// the row cost one pass rather than two. That works because the tooltip's
    /// triggers all land between frames: a mouse event, a key press, and a
    /// scheduled wake for the hover delay. What the render publishes is the
    /// `.onHover` REGISTRATION; the invocation has already happened. (The one
    /// case that does lag a frame is a help string that changes while the
    /// pointer is stationary, which is not worth a second pass.)
    public internal(set) var tooltipLines: [String] = []
}

// MARK: - Public API

extension StatusBarState {
    /// Sets the global user items. Triggers a re-render.
    public func setItems(_ items: [any StatusBarItemProtocol]) {
        userGlobalItems = items
        appState.setNeedsRender()
    }

    /// Sets the global user items using a builder. Triggers a re-render.
    public func setItems(@StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]) {
        userGlobalItems = builder()
        appState.setNeedsRender()
    }

    /// Pushes a new user context with its items onto the stack. Triggers a re-render.
    public func push(context: String, items: [any StatusBarItemProtocol]) {
        userContextStack.removeAll { $0.context == context }
        userContextStack.append((context, items))
        appState.setNeedsRender()
    }

    /// Pushes a new user context using a builder. Triggers a re-render.
    public func push(context: String, @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]) {
        push(context: context, items: builder())
    }

    /// Pops a user context from the stack. Triggers a re-render.
    public func pop(context: String) {
        userContextStack.removeAll { $0.context == context }
        appState.setNeedsRender()
    }

    /// Clears all user contexts (keeps global user items and system items). Triggers a re-render.
    public func clearContexts() {
        userContextStack.removeAll()
        appState.setNeedsRender()
    }

    /// Clears all user items (global and contexts). System items remain.
    public func clearUserItems() {
        userContextStack.removeAll()
        userGlobalItems.removeAll()
        declaredGlobalItems.removeAll()
    }

    /// Clears everything including user items and hides system items.
    public func clear() {
        userContextStack.removeAll()
        userGlobalItems.removeAll()
        declaredGlobalItems.removeAll()
        showSystemItems = false
    }

    /// Handles a key event, checking if any current item matches.
    @discardableResult
    public func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // An open sectionless surface holds the keyboard: nothing on the bar
        // is its own, so nothing on the bar may fire. See
        // ``itemActionsSuppressed``; ESC still works via the pre-route.
        guard !itemActionsSuppressed else { return false }
        // While a modal surface (open Picker drop-down, etc.) has claimed
        // ESC via ``escapeLabelOverride``, leave that key to the focus
        // dispatch chain so the surface's own handler actually fires —
        // otherwise a page-level "ESC: back" would close the page out
        // from under it. The label printed in the status bar already tells
        // the user what ESC does *right now*; here we make the behaviour
        // match.
        let escapeIsClaimedByModal = escapeLabelOverride != nil && event.key == .escape

        for item in currentItems where item.matches(event) {
            // Any item matching an Escape event IS an Escape binding —
            // whatever its display string. This used to compare the display
            // glyph (`item.shortcut == "⎋"`), so an item spelled differently
            // (`shortcut: "esc"` with an explicit `key: .escape`) fired out
            // from under the modal's claim.
            if escapeIsClaimedByModal {
                continue
            }
            if let statusBarItem = item as? StatusBarItem {
                if statusBarItem.hasAction {
                    statusBarItem.execute()
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Internal API

extension StatusBarState {
    /// Sets the global user items without triggering a re-render.
    func setItemsSilently(_ items: [any StatusBarItemProtocol]) {
        declaredGlobalItems = items
    }

    /// Registers status bar items for a focus section.
    func registerSectionItems(
        sectionID: String,
        items: [any StatusBarItemProtocol],
        composition: StatusBarItemComposition
    ) {
        sectionItems.removeAll { $0.sectionID == sectionID }
        sectionItems.append((sectionID, items, composition))
    }

    /// Drops everything the view tree declared last pass, at the start of the
    /// next one.
    ///
    /// Both kinds: a section's items and a page's global ones. Anything still
    /// in the tree re-declares itself as it renders; anything that left takes
    /// its shortcuts with it, which is the whole point.
    func beginRenderPass() {
        sectionItems.removeAll()
        declaredGlobalItems.removeAll()
    }

    /// Everything a walk of the scene republishes, emptied before the walk:
    /// the items (``beginRenderPass()``) and the per-frame claims below.
    ///
    /// One method so the render loop and a headless renderer reset the same
    /// things.
    func beginSceneRender() {
        beginRenderPass()
        // The transient escape-label override is published by whichever
        // open modal surface (Picker drop-down, etc.) renders in this
        // frame; clearing it here makes the default the absence of any
        // override, so a surface that disappeared on the previous frame
        // never leaves its stale label behind on the next page. The
        // grabs-input flag travels with it (modal by default; a list's
        // lightweight selection claim lowers it each frame it applies).
        escapeLabelOverride = nil
        escapeClaimGrabsInput = true
        itemActionsSuppressed = false
        // Same contract for the Return verb: published by whichever control
        // holds the focus this frame, so its absence has to be the default or a
        // control that lost the focus would leave its verb on the bar.
        activationLabelOverride = nil
    }

    /// Pushes a new user context without triggering a re-render.
    func pushSilently(context: String, items: [any StatusBarItemProtocol]) {
        userContextStack.removeAll { $0.context == context }
        userContextStack.append((context, items))
    }
}

// MARK: - Private Helpers

extension StatusBarState {
    /// Resolves items for a given section using its composition strategy.
    fileprivate func resolvedSectionItems(for sectionID: String) -> [any StatusBarItemProtocol] {
        guard let entry = sectionItems.first(where: { $0.sectionID == sectionID }) else {
            return globalItems
        }

        switch entry.composition {
        case .replace:
            return entry.items
        case .merge:
            let sectionShortcuts = Set(entry.items.map { $0.shortcut })
            let filteredGlobal = globalItems.filter { !sectionShortcuts.contains($0.shortcut) }
            return entry.items + filteredGlobal
        }
    }
}

// MARK: - StatusBar Environment Key

/// Environment key for accessing the status bar state.
private struct StatusBarKey: EnvironmentKey {
    static let defaultValue: StatusBarState? = nil
}

extension EnvironmentValues {
    /// The status bar state for the current application.
    ///
    /// Use this to set status bar items from within your views:
    ///
    /// ```swift
    /// context.environment.statusBar?.setItems([
    ///     StatusBarItem(shortcut: "q", label: "quit")
    /// ])
    /// ```
    ///
    /// `nil` outside a running application. These are the app's own objects,
    /// created by `AppRunner` and published by `RenderLoop.buildEnvironment()`
    /// — so a bare `EnvironmentValues()` (a headless render, a test) has none,
    /// which is the truth. It used to hand out a SHARED instance instead, and
    /// every such render mutated the same object: two tests rendering sheets in
    /// parallel both registered their ESC item into it and read each other's
    /// back. The convention here is the one `focusManager` and
    /// `keyEventDispatcher` already follow — a runtime service is Optional, and
    /// absent means absent.
    public var statusBar: StatusBarState? {
        get { self[StatusBarKey.self] }
        set { self[StatusBarKey.self] = newValue }
    }
}
