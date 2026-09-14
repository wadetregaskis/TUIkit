//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewToggle.swift
//
//  The sidebar toggle of ``NavigationSplitView``: the ▶ edge column that brings
//  a hidden leading column back, the ◀ on the leftmost divider that hides one,
//  the ⌃S and ⌥⌃S chords, the visibility steps behind all three, and the focus
//  hand-over between a handle and the one that undoes it. Split out of `NavigationSplitView.swift`, which
//  holds the columns and dividers.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Visibility steps

/// The visibility changes the split view's own handles make.
///
/// The handles STEP, one column at a time: ◀ hides the leftmost visible column,
/// ▶ brings back the nearest hidden one. Every function takes the value as the
/// binding holds it and reads `.automatic` as `.all`, as the split view draws it.
enum SplitViewToggle {
    /// The visibility after ◀ hides the leftmost visible column, or `nil` when
    /// only the detail column is showing.
    ///
    /// Two columns: `.all` → `.detailOnly` (a two-column split draws
    /// `.doubleColumn` as `.all` too). Three columns: `.all` → `.doubleColumn` →
    /// `.detailOnly`.
    static func hidingLeading(
        _ visibility: NavigationSplitViewVisibility, isThreeColumn: Bool
    ) -> NavigationSplitViewVisibility? {
        switch visibility {
        case .detailOnly: nil
        case .doubleColumn: .detailOnly
        default: isThreeColumn ? .doubleColumn : .detailOnly
        }
    }

    /// The visibility after ▶ reveals the nearest hidden column, or `nil` when
    /// no column is hidden.
    ///
    /// Two columns: `.detailOnly` → `.all`. Three columns: `.detailOnly` →
    /// `.doubleColumn` → `.all`. A two-column split reveals to `.all` rather than
    /// to whatever it held before hiding, which SwiftUI does not document either.
    /// The visibility after a sidebar chord (⌃S, ⌥⌃S): the sidebar alone
    /// toggles, as macOS's View ▸ Show Sidebar does, and anything that hides it
    /// comes back to every column.
    ///
    /// Two columns: `.detailOnly` ⇄ `.all`. Three columns: `.all` ⇄
    /// `.doubleColumn`, and `.detailOnly` → `.all`.
    static func togglingSidebar(
        _ visibility: NavigationSplitViewVisibility, isThreeColumn: Bool
    ) -> NavigationSplitViewVisibility {
        switch visibility {
        case .detailOnly: .all
        case .doubleColumn where isThreeColumn: .all
        default: isThreeColumn ? .doubleColumn : .detailOnly
        }
    }

    static func revealing(
        _ visibility: NavigationSplitViewVisibility, isThreeColumn: Bool
    ) -> NavigationSplitViewVisibility? {
        switch visibility {
        case .detailOnly: isThreeColumn ? .doubleColumn : .all
        case .doubleColumn where isThreeColumn: .all
        default: nil
        }
    }
}

// MARK: - Sidebar chord registration

/// A split view's sidebar chords, as registered by its render and by a value
/// memo replaying one — see `EffectJournal`.
enum SidebarChordRegistrar {
    /// The journal kind of a split view's sidebar chords.
    static let kind = EffectJournal.Kind("sidebarChords")

    /// Registers `action` as the framework default for each of `shortcuts`.
    ///
    /// The registry is looked up in `context`, not handed in, so a replay
    /// registers into the registry of the walk that serves it.
    @MainActor
    static func register(
        _ shortcuts: [KeyboardShortcut], holdsFocus: Bool, action: @escaping () -> Void,
        context: RenderContext
    ) {
        guard let registry = context.environment.keyboardShortcutRegistry else { return }
        for shortcut in shortcuts {
            registry.registerDefault(shortcut, holdsFocus: holdsFocus, action: action)
        }
    }
}

// MARK: - State

/// Where the keyboard goes once a handle's change has been drawn.
enum SplitViewFocusTarget {
    /// The divider that follows the leftmost visible column — whose ◀ hides that
    /// column again — else that column itself.
    case leadingDivider
    /// The ▶ edge column, which brings the hidden column back, else the leftmost
    /// visible column.
    case edge
}

/// What the sidebar toggle keeps between frames, at
/// ``SplitViewStateIndex/toggle``.
final class SplitViewToggleState {
    /// The visibility of a split with no `columnVisibility` binding, which the
    /// handles write here instead. A split with a binding never reads it.
    var visibility = NavigationSplitViewVisibility.all

    /// The handle the keyboard moves to on the split's next render.
    ///
    /// A handle's change cannot move the focus when it happens: the section it
    /// should land on belongs to a layout that has not been drawn yet, and
    /// `FocusManager.activateSection(id:)` ignores a section that is not
    /// registered. So the change records where the focus goes, and the next
    /// render activates it once its sections are registered. Without that, the
    /// vanished handle's section made `endRenderPass` fall back to the first
    /// section on the page.
    var pendingFocus: SplitViewFocusTarget?

    /// The section that held the keyboard when the split's last render ended,
    /// if the split registered it: a column, a section inside one, a divider or
    /// the edge column. `nil` when the keyboard was elsewhere.
    ///
    /// A column hidden while it holds the keyboard — `columnVisibility` written
    /// from outside, or a chord — takes its sections with it, and
    /// `endRenderPass` then sends the focus to the first section on the page,
    /// which is usually outside the split. Remembering the section lets the next
    /// render see it has gone and keep the keyboard in the split.
    var heldFocusSectionID: String?

    /// How many focus sections were registered when the current render began,
    /// so its end can tell which sections the split registered.
    var sectionsAtRenderStart = 0

    /// Whether each column removed the toggle with `.toolbar(removing:)` the last
    /// time it was measured or rendered. Kept per column because a hidden column
    /// is neither, and a sidebar that removed the toggle must not bring back the
    /// ▶ the moment it hides. A column not yet seen has no entry.
    var removedByColumn: [NavigationSplitViewColumn: Bool] = [:]
}

// MARK: - Edge handler

/// Drives the ▶ edge column: Return or Space brings the nearest hidden column
/// back, as a click on it does.
final class _SplitEdgeHandler: Focusable {
    let focusID: String
    var canBeFocused = true

    /// Whether the cursor is over the column, which pulses the arrow.
    var isHovered = false

    /// How many rows the column was drawn with, so a release can tell whether
    /// it is still on the column.
    var height = 0

    /// Reveals the nearest hidden column. Rebuilt every render, so it writes
    /// through the binding in force.
    var reveal: () -> Void = {}

    init(focusID: String) {
        self.focusID = focusID
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .enter, .space:
            reveal()
            return true
        default:
            return false
        }
    }
}

// MARK: - Edge column

extension _NavigationSplitViewCore {
    /// The edge column's wiring for one render: how to draw it, and the handler
    /// behind it when it has one.
    struct EdgeWiring {
        let info: DividerRenderInfo
        let handler: _SplitEdgeHandler?
    }

    /// Starts the sidebar toggle's part of a render, and returns its state.
    ///
    /// - Marks this split's identity active, so the state outlives the per-frame
    ///   `StateStorage` GC whether or not the split is resizable.
    /// - Notes how many focus sections are registered so far, so the end of the
    ///   render can tell which ones the split registered.
    /// - Registers the sidebar chords, before any column renders (see
    ///   ``registerSidebarChords(context:toggleState:holdsFocus:)``).
    ///
    /// `nil` without state storage (a bare measurement).
    func beginToggleRender(context: RenderContext) -> SplitViewToggleState? {
        guard let stateStorage = context.stateStorage else { return nil }
        stateStorage.markActive(context.identity)
        let state = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: SplitViewStateIndex.toggle),
            default: SplitViewToggleState()
        ).value
        if !context.isMeasuring, let focusManager = context.environment.focusManager {
            state.sectionsAtRenderStart = focusManager.sections.count
        }
        registerSidebarChords(context: context, toggleState: state, holdsFocus: false)
        return state
    }

    /// Registers SwiftUI's two sidebar chords, View ▸ Show Sidebar
    /// `("s", [.command, .control])` and the hidden Toggle Sidebar
    /// `("s", [.command, .option])`, each resolved through `commandKey`: ⌃S and
    /// ⌥⌃S under the default `.control`, none under `.unavailable`.
    ///
    /// They work wherever the focus is, as framework defaults
    /// (`KeyboardShortcutRegistry.registerDefault`), so an app shortcut on the
    /// same keys wins, and anything that consumes the key earlier in the input
    /// chain (`onKeyPress`, a focused sortable Table) does too. Every split
    /// registers them twice: at the start of its render, which makes the first
    /// split in render order the one that toggles when no split holds the focus;
    /// and, if it holds the focus, again once its columns have rendered, which
    /// makes the innermost focus-holding split win.
    ///
    /// A disabled split registers nothing, as a disabled `Button` registers no
    /// shortcut. `.toolbar(removing: .sidebarToggle)` leaves the chords alone, as
    /// SwiftUI's menu items stay when its toolbar button goes.
    func registerSidebarChords(
        context: RenderContext, toggleState: SplitViewToggleState, holdsFocus: Bool
    ) {
        guard !context.isMeasuring, context.environment.isEnabled,
            context.environment.keyboardShortcutRegistry != nil
        else { return }
        // The registry is emptied every walk. Declared as REPLAYABLE: a memo
        // serving the split registers the chords again from the entry below.
        // The split's own sections declare separately, in `renderToBuffer`.
        context.environment.volatileReadTracker?.recordReplayableEffect()
        let action = stepAction(toggleState: toggleState, focus: nil) { visibility, isThreeColumn in
            SplitViewToggle.togglingSidebar(visibility, isThreeColumn: isThreeColumn)
        }
        let modifierSets: [EventModifiers] = [[.command, .control], [.command, .option]]
        let shortcuts = modifierSets.compactMap {
            KeyboardShortcut("s", modifiers: $0).resolved(commandKey: context.environment.commandKey)
        }
        SidebarChordRegistrar.register(shortcuts, holdsFocus: holdsFocus, action: action, context: context)
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: SidebarChordRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    SidebarChordRegistrar.register(
                        shortcuts, holdsFocus: holdsFocus, action: action, context: replay)
                })
        }
    }

    /// The edge column for this render, if there is one, and the context the
    /// columns lay out in beside it.
    ///
    /// There is one while a leading column is hidden, unless
    /// `.toolbar(removing: .sidebarToggle)` took it away. It is wired here, before
    /// any column registers, so Tab reaches it first, and the columns share what
    /// is left of the width. Leading chrome yields its cell when the columns
    /// would be left none to draw in: at one cell per visible column or fewer,
    /// the edge would push every column's content out of the split.
    func layOutEdge(
        visibleColumns: [NavigationSplitViewColumn], context: RenderContext,
        focusManager: FocusManager?, toggleState: SplitViewToggleState?
    ) -> (EdgeWiring?, RenderContext) {
        probeToggleRemoval(visibleColumns: visibleColumns, context: context, toggleState: toggleState)
        guard showsToggle(context: context, toggleState: toggleState),
            visibleColumns.count < (isThreeColumn ? 3 : 2),
            context.availableWidth > visibleColumns.count
        else { return (nil, context) }
        let edge = wireEdge(context: context, focusManager: focusManager, toggleState: toggleState)
        let columnsContext = context.withAvailableSize(
            width: RenderContext.extent(context.availableWidth, insideChrome: 1),
            height: context.availableHeight)
        return (edge, columnsContext)
    }

    /// Whether the split shows its toggle handles: no `.toolbar(removing:
    /// .sidebarToggle)` on or above it, and none in any column as last seen.
    func showsToggle(context: RenderContext, toggleState: SplitViewToggleState?) -> Bool {
        !context.environment.sidebarToggleRemoved
            && !(toggleState?.removedByColumn.values.contains(true) ?? false)
    }

    /// Measures each visible column the split has not seen yet, to learn whether
    /// it removes the toggle before the handles are laid out. The split already
    /// measures its leading columns for their widths, but not the trailing one
    /// under a proportional style, and a modifier in the detail column of a split
    /// that starts hidden would otherwise draw ▶ on the first frame. Once seen, a
    /// column is kept current by its render (`renderColumn`), so this costs one
    /// measure per column per split.
    func probeToggleRemoval(
        visibleColumns: [NavigationSplitViewColumn], context: RenderContext,
        toggleState: SplitViewToggleState?
    ) {
        guard let toggleState, !context.isMeasuring,
            let preferences = context.environment.preferenceStorage
        else { return }
        for column in visibleColumns where toggleState.removedByColumn[column] == nil {
            preferences.push()
            _ = measureColumn(column, proposal: ProposedSize(width: nil, height: nil), context: context)
            recordToggleRemoval(
                of: column, from: preferences.pop(), toggleState: toggleState, context: context)
        }
    }

    /// Records whether `column` removed the toggle, from the preferences it just
    /// published. A change to a column already seen can only be learnt after the
    /// handles were laid out for this frame, so it asks for another frame.
    ///
    /// It asks the way a `@State` write does: it invalidates the split's identity
    /// through the context's render cache, which asks the run loop for a frame
    /// and, at that frame's start, drops the cached buffers of the split and of
    /// everything above it, so no memo serves the handles drawn this frame.
    /// Under `TUIKIT_DIAGNOSE_BODY_MUTATION` this is reported as a write during
    /// the walk, which it is; it happens once per change of answer, not per frame.
    func recordToggleRemoval(
        of column: NavigationSplitViewColumn, from scope: PreferenceValues,
        toggleState: SplitViewToggleState, context: RenderContext
    ) {
        let removed = scope[SidebarToggleRemovedKey.self]
        let previous = toggleState.removedByColumn.updateValue(removed, forKey: column)
        if let previous, previous != removed {
            context.renderCache?.invalidateRender(for: context.identity)
        }
    }

    /// The edge column's focus section ID.
    func edgeSectionID(context: RenderContext) -> String {
        "nav-split-edge-\(context.identity.path)"
    }

    /// Sets up the edge column for this render: its focus section, registered
    /// before any column's so Tab reaches it first; its handler; and the mouse
    /// handler that reveals on a click.
    ///
    /// Under `.disabled()` or `.hidden()` the column is drawn blank and is no
    /// Tab stop, but it keeps its cell: removing it would move every column one
    /// cell whenever the enabled state flips, where the dividers only change
    /// glyphs.
    func wireEdge(
        context: RenderContext, focusManager: FocusManager?, toggleState: SplitViewToggleState?
    ) -> EdgeWiring {
        guard context.environment.isEnabled, !context.environment.isFocusSuppressed else {
            return EdgeWiring(
                info: DividerRenderInfo(
                    isActive: false, isHovered: false, mouseHandlerID: nil, isInteractive: false),
                handler: nil)
        }
        guard !context.isMeasuring, let focusManager, let toggleState,
            let stateStorage = context.stateStorage
        else {
            return EdgeWiring(
                info: DividerRenderInfo(isActive: false, isHovered: false, mouseHandlerID: nil),
                handler: nil)
        }

        let sectionID = edgeSectionID(context: context)
        focusManager.registerSection(id: sectionID)
        let handler = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: SplitViewStateIndex.edge),
            default: _SplitEdgeHandler(focusID: sectionID)
        ).value
        handler.reveal = revealAction(toggleState: toggleState)
        focusManager.register(handler, inSection: sectionID)
        // The same two things `wireDivider` repeats from
        // `FocusRegistration.register`, which this bypasses for the same reason.
        FocusRegistration.publishHelpText(context: context, focusID: sectionID)
        FocusRegistration.publishActivationLabel(
            LocalizationService.shared.string(for: LocalizationKey.StatusBar.showColumn),
            context: context, isFocused: focusManager.isFocused(id: sectionID))

        var mouseHandlerID: HitTestRegion.HandlerID?
        if let mouseDispatcher = context.environment.mouseEventDispatcher {
            mouseDispatcher.requestFeature(.motion)
            let captureHandler = handler
            mouseHandlerID = mouseDispatcher.register { event in
                switch event.phase {
                case .entered:
                    captureHandler.isHovered = true
                    return true
                case .exited:
                    captureHandler.isHovered = false
                    return true
                default:
                    break
                }
                guard event.button == .left else { return false }
                switch event.phase {
                case .pressed, .dragged:
                    return true
                case .released:
                    // Coordinates are local to the column. A press dragged off it
                    // and let go elsewhere is a change of mind, as on a button.
                    if event.x == 0, (0..<captureHandler.height).contains(event.y) {
                        captureHandler.reveal()
                    }
                    return true
                default:
                    return false
                }
            }
        }

        // Drawing only, as the divider's — see `RenderContext.indicatesFocus(_:)`.
        return EdgeWiring(
            info: DividerRenderInfo(
                isActive: context.indicatesFocus(focusManager.isActiveSection(sectionID)),
                isHovered: handler.isHovered,
                mouseHandlerID: mouseHandlerID, focusID: sectionID),
            handler: handler)
    }

    /// What ▶ does: write the next visibility, and send the keyboard to the
    /// divider that hides the column again.
    private func revealAction(toggleState: SplitViewToggleState) -> () -> Void {
        stepAction(toggleState: toggleState, focus: .leadingDivider, step: SplitViewToggle.revealing)
    }

    /// What ◀ does: write the next visibility, and send the keyboard to the ▶
    /// that brings the column back.
    func hideAction(toggleState: SplitViewToggleState) -> () -> Void {
        stepAction(toggleState: toggleState, focus: .edge, step: SplitViewToggle.hidingLeading)
    }

    /// A handle's or chord's action: `step` the visibility the split is drawing
    /// and write the result through the binding, or into the split's own state
    /// when there is none, recording where the keyboard goes once it is drawn
    /// (`nil` for a chord, which leaves the keyboard where it is). Reads the
    /// visibility when it runs, not when the handle was drawn, so several key
    /// presses in one input batch each take a step.
    private func stepAction(
        toggleState: SplitViewToggleState, focus: SplitViewFocusTarget?,
        step: @escaping (NavigationSplitViewVisibility, Bool) -> NavigationSplitViewVisibility?
    ) -> () -> Void {
        let binding = columnVisibility
        let isThreeColumn = isThreeColumn
        return {
            let current = binding?.wrappedValue ?? toggleState.visibility
            guard let next = step(current, isThreeColumn) else { return }
            if let focus { toggleState.pendingFocus = focus }
            if let binding {
                binding.wrappedValue = next
            } else {
                toggleState.visibility = next
            }
        }
    }

    /// `columns` with the edge column in front of it: ▶ on the centre row, or a
    /// blank cell when the column is not interactive.
    func prependEdgeColumn(
        _ edge: EdgeWiring, to columns: FrameBuffer, palette: any Palette, cycle: SelectionEmphasisCycle
    ) -> FrameBuffer {
        let height = max(0, columns.height)
        edge.handler?.height = height
        var result = edge.info.isInteractive && height > 0
            ? buildHandleColumn(info: edge.info, height: height, palette: palette, cycle: cycle) { row in
                row == height / 2 ? TerminalSymbols.rightArrow : nil
            }
            : FrameBuffer(lines: Array(repeating: " ", count: height))
        result.appendHorizontally(columns, spacing: 0)
        return result
    }

    /// Ends the sidebar toggle's part of a render, now that it has registered
    /// every section the split owns: settles where the keyboard is, then records
    /// it, and registers the chords again if the split holds the keyboard.
    ///
    /// - A handle pressed last frame asked for the handle that undoes it (see
    ///   ``SplitViewToggleState/pendingFocus``). The first of its candidates
    ///   that registered wins: a split too narrow for the edge has no edge, so
    ///   the column takes the keyboard instead.
    /// - Otherwise, if a section of this split held the keyboard at the end of
    ///   the last render and is gone now — its column was hidden — the leftmost
    ///   visible column takes it (see ``SplitViewToggleState/heldFocusSectionID``).
    ///
    /// Either way it then records which of this split's sections holds the
    /// keyboard, for the next render, and a split that holds it registers the
    /// chords as the focus-holding default.
    func endToggleRender(
        toggleState: SplitViewToggleState?, visibleColumns: [NavigationSplitViewColumn],
        context: RenderContext, focusManager: FocusManager?
    ) {
        guard let toggleState, let focusManager, let leading = visibleColumns.first else { return }
        defer {
            toggleState.heldFocusSectionID = focusManager.activeSectionID(
                registeredSince: toggleState.sectionsAtRenderStart)
            if toggleState.heldFocusSectionID != nil {
                registerSidebarChords(context: context, toggleState: toggleState, holdsFocus: true)
            }
        }
        guard let target = toggleState.pendingFocus else {
            if let held = toggleState.heldFocusSectionID,
                focusManager.activeSectionIdentifier == held, focusManager.section(id: held) == nil
            {
                focusManager.activateSection(id: focusSectionID(for: leading, context: context))
            }
            return
        }
        toggleState.pendingFocus = nil
        let candidates: [String]
        switch target {
        case .leadingDivider:
            candidates = [
                dividerSectionID(after: leading, context: context),
                focusSectionID(for: leading, context: context),
            ]
        case .edge:
            candidates = [edgeSectionID(context: context), focusSectionID(for: leading, context: context)]
        }
        guard let id = candidates.first(where: { focusManager.section(id: $0) != nil }) else { return }
        focusManager.activateSection(id: id)
    }
}
