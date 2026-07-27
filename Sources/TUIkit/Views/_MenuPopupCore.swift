//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _MenuPopupCore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The open/closed state of one pop-up ``Menu`` — a manual StateStorage box
/// (not `@State`) marked active each frame, the same pattern the context menu
/// and the Picker drop-down use.
@MainActor
final class MenuPopupState {
    /// Whether the menu is currently shown.
    var isOpen = false
    /// The open menu's highlight and its rows — see ``MenuPopupController``.
    let controller = MenuPopupController()
}

/// The body of ``DefaultMenuStyle``: a collapsed label that opens the items as
/// a floating menu.
///
/// The label is an ordinary ``Button`` — so it takes focus, activates on Enter
/// or a click, and picks up whatever ``ButtonStyle`` is in force — and the open
/// menu is the same presentation `.contextMenu` uses, anchored directly beneath
/// it. Clicking the label while the menu is open closes it: the presentation's
/// dismiss backdrop covers the whole screen and takes that press first, which is
/// exactly the toggle behaviour a pop-up button has everywhere else.
struct _MenuPopupCore: View, Renderable, Layoutable {
    let label: MenuStyleConfiguration.Label
    let content: MenuStyleConfiguration.Content

    /// StateStorage property indices. A free enum on the type because the
    /// state box is fetched from two different methods.
    private enum StateIndex {
        static let state = 0
    }

    /// Child-identity indices, so the trigger's `@State` and focus slots never
    /// collide with the items'.
    private enum ChildIndex {
        static let trigger = 0
        static let items = 1
    }

    var body: Never {
        fatalError("_MenuPopupCore renders via Renderable")
    }

    /// The menu floats *over* the page, so the layout footprint is the
    /// collapsed label — open or closed.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            trigger(state(in: context), focusManager: context.environment.focusManager),
            proposal: proposal, context: triggerContext(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let state = state(in: context)
        let sectionID = "menu-\(context.identity.path)"
        // Keep the box alive across the run loop's per-frame StateStorage GC.
        if !context.isMeasuring { context.environment.stateStorage?.markActive(context.identity) }

        var buffer = TUIkit.renderToBuffer(
            trigger(state, focusManager: context.environment.focusManager),
            context: triggerContext(context))
        guard state.isOpen, !context.isMeasuring else {
            // Tear down a section left over from a just-dismissed menu so the
            // page's focus is restored rather than stranded.
            if !context.isMeasuring {
                context.environment.focusManager?.deactivateSection(id: sectionID)
            }
            return buffer
        }
        // Anchored on the row below the label, like every other drop-down;
        // `presentMenuPopover` nudges it back on-screen at the edges.
        presentMenuPopover(
            items: content, over: &buffer, controller: state.controller, sectionID: sectionID,
            itemsIndex: ChildIndex.items,
            anchor: MenuAnchor(x: 0, y: buffer.height, controlHeight: buffer.height),
            dismiss: {
                state.isOpen = false
                state.controller.closed()
            }, context: context)
        return buffer
    }

    /// The collapsed control: the caller's label plus the closed/open caret
    /// every TUIkit drop-down uses.
    private func trigger(_ state: MenuPopupState, focusManager: FocusManager?) -> some View {
        Button {
            state.isOpen.toggle()
            // A `Button` erases how it was pressed (a click and a Return both
            // just run the action), so ask the focus manager which device drove
            // the event — that is what decides whether the menu opens with a row
            // highlighted.
            if state.isOpen {
                state.controller.opened(withSelection: focusManager?.lastInputSource != .pointer)
            }
        } label: {
            HStack(spacing: 1) {
                label
                Text(state.isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret)
            }
        }
    }

    private func triggerContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(
            erasedType: MenuStyleConfiguration.Label.self, index: ChildIndex.trigger)
    }

    /// The persisted open/closed state, or a throwaway one outside a running
    /// app (no StateStorage — the menu then simply never opens).
    private func state(in context: RenderContext) -> MenuPopupState {
        guard let stateStorage = context.environment.stateStorage else { return MenuPopupState() }
        let box: StateBox<MenuPopupState> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.state),
            default: MenuPopupState())
        return box.value
    }
}
