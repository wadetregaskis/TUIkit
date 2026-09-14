//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewToggle.swift
//
//  The sidebar toggle of ``NavigationSplitView``: the ▶ edge column that brings
//  a hidden leading column back, the ◀ on the leftmost divider that hides one,
//  the visibility steps behind both, and the focus hand-over between a handle
//  and the one that undoes it. Split out of `NavigationSplitView.swift`, which
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

    /// The sidebar toggle's state, having marked this split's identity active so
    /// it outlives the per-frame `StateStorage` GC whether or not the split is
    /// resizable. `nil` without state storage (a bare measurement).
    func resolveToggleState(context: RenderContext) -> SplitViewToggleState? {
        guard let stateStorage = context.stateStorage else { return nil }
        stateStorage.markActive(context.identity)
        return stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: SplitViewStateIndex.toggle),
            default: SplitViewToggleState()
        ).value
    }

    /// The edge column for this render, if there is one, and the context the
    /// columns lay out in beside it.
    ///
    /// There is one while a leading column is hidden. It is wired here, before
    /// any column registers, so Tab reaches it first, and the columns share what
    /// is left of the width. Leading chrome yields its cell when the columns
    /// would be left none to draw in: at one cell per visible column or fewer,
    /// the edge would push every column's content out of the split.
    func layOutEdge(
        visibleColumns: [NavigationSplitViewColumn], context: RenderContext,
        focusManager: FocusManager?, toggleState: SplitViewToggleState?
    ) -> (EdgeWiring?, RenderContext) {
        guard visibleColumns.count < (isThreeColumn ? 3 : 2),
            context.availableWidth > visibleColumns.count
        else { return (nil, context) }
        let edge = wireEdge(context: context, focusManager: focusManager, toggleState: toggleState)
        let columnsContext = context.withAvailableSize(
            width: RenderContext.extent(context.availableWidth, insideChrome: 1),
            height: context.availableHeight)
        return (edge, columnsContext)
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

        return EdgeWiring(
            info: DividerRenderInfo(
                isActive: focusManager.isActiveSection(sectionID), isHovered: handler.isHovered,
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

    /// A handle's action: `step` the visibility the split is drawing and write
    /// the result through the binding, or into the split's own state when there
    /// is none, recording where the keyboard goes once it is drawn. Reads the
    /// visibility when it runs, not when the handle was drawn, so several key
    /// presses in one input batch each take a step.
    private func stepAction(
        toggleState: SplitViewToggleState, focus: SplitViewFocusTarget,
        step: @escaping (NavigationSplitViewVisibility, Bool) -> NavigationSplitViewVisibility?
    ) -> () -> Void {
        let binding = columnVisibility
        let isThreeColumn = isThreeColumn
        return {
            let current = binding?.wrappedValue ?? toggleState.visibility
            guard let next = step(current, isThreeColumn) else { return }
            toggleState.pendingFocus = focus
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

    /// Activates the section a handle pressed last frame asked for (see
    /// ``SplitViewToggleState/pendingFocus``), now that this render has
    /// registered every section the split owns. The first of its candidates
    /// that registered wins: a split that cannot resize has no divider, and a
    /// split too narrow for the edge has no edge, so the column takes the
    /// keyboard instead.
    func activatePendingFocus(
        toggleState: SplitViewToggleState?, visibleColumns: [NavigationSplitViewColumn],
        context: RenderContext, focusManager: FocusManager?
    ) {
        guard let toggleState, let target = toggleState.pendingFocus, let focusManager,
            let leading = visibleColumns.first
        else { return }
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
