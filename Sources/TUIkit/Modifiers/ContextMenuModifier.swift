//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContextMenuModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Context-menu state

/// The persisted open/anchor state of one ``ContextMenuModifier`` — a manual
/// StateStorage box (not `@State`) marked active each frame, the same pattern
/// ``Menu`` and the Picker drop-down use.
final class ContextMenuState {
    /// Whether the menu is currently shown.
    var isOpen = false
    /// The column of the click that opened it, in the modified content's local
    /// coordinate space (composition makes it absolute).
    var anchorX = 0
    /// The row of the opening click, content-local.
    var anchorY = 0
}

// MARK: - Context menu modifier

/// Attaches a right-click / secondary-click pop-up menu to a view — mirrors
/// SwiftUI's `contextMenu(menuItems:)`.
///
/// Right-click (or, where a terminal swallows that, **Ctrl-click**) the content
/// to open a floating menu of `Button`s anchored at the click point; selecting
/// one runs its action and closes the menu, and Escape or an outside click
/// dismisses it. Like the alert / modal presentation modifiers this is
/// *modifier infrastructure* rendered via ``Renderable`` (it is a `some View`
/// wrapper, never a public control with a `Never` body).
public struct ContextMenuModifier<Content: View, MenuItems: View>: View {
    let content: Content
    let menuItems: MenuItems

    public var body: Never {
        fatalError("ContextMenuModifier renders via Renderable")
    }
}

/// StateStorage property indices for ``ContextMenuModifier``. A free enum because
/// the modifier is generic (which can't hold static stored properties).
private enum StateIndex {
    static let state = 0
}

// MARK: - Renderable

extension ContextMenuModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let sectionID = "contextmenu-\(context.identity.path)"
        // Its own child identity, so the content's / menu's @State never collides
        // with this modifier's state slot (mirrors AlertPresentationModifier).
        let contentContext = context.withChildIdentity(type: Content.self, index: 0)

        guard let stateStorage = context.environment.stateStorage else {
            return TUIkit.renderToBuffer(content, context: contentContext)
        }
        let stateBox: StateBox<ContextMenuState> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.state),
            default: ContextMenuState())
        let state = stateBox.value
        // Keep the box alive across the run loop's per-frame StateStorage GC.
        if !context.isMeasuring { stateStorage.markActive(context.identity) }

        // CLOSED: render the content live and attach the right-click trigger. Tear
        // down a section left over from a just-dismissed menu so the page's focus
        // / scroll is restored rather than jumping.
        guard state.isOpen else {
            var buffer = TUIkit.renderToBuffer(content, context: contentContext)
            if !context.isMeasuring {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
                context.environment.focusManager?.deactivateSection(id: sectionID)
                attachTrigger(to: &buffer, state: state, context: context)
            }
            return buffer
        }

        // OPEN: grab focus into the menu's own section (so the page beneath can't
        // steal it), register an Escape-to-dismiss handler, and mark the section
        // input-grabbing so global chrome hotkeys don't fire behind the menu —
        // exactly like Alert/Modal. Render-pass only (a measure-by-render ancestor
        // must not register a phantom section).
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            let focusManager = context.environment.focusManager
            focusManager?.registerSection(id: sectionID)
            focusManager?.activateSection(id: sectionID)
            focusManager?.markSectionModal(id: sectionID)
            context.environment.keyEventDispatcher!.addHandler { event in
                if event.key == .escape {
                    state.isOpen = false
                    return true
                }
                return false
            }
        }

        // The content beneath becomes an inert backdrop (isolated from focus /
        // key / state), so its controls can't steal the menu's focus. NOT dimmed
        // (a context menu is a popover, not a modal), so no dimsBackground.
        var baseBuffer = TUIkit.renderToBuffer(content, context: contentContext.isolatedForBackground())

        // Build the menu: the ViewBuilder Buttons stacked vertically in a border,
        // with `dismissMenu` set so selecting any button closes the menu. Wrapped
        // in renderPresentedDialog so an over-tall menu scrolls instead of clipping
        // under the status bar.
        var menuContext = context
            .withChildIdentity(erasedType: MenuItems.self, index: 1)
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(context.environment.overlayContentHeight)
        menuContext.environment.activeFocusSectionID = sectionID
        menuContext.environment.dismissMenu = DismissMenuAction { state.isOpen = false }

        // The items are `Button`s (SwiftUI's API, which TUIkit matches), but a
        // menu's rows must not LOOK like buttons — `_MenuItemButtonStyle` draws
        // them as menu rows, the same idiom as the Picker drop-down.
        let menuView = VStack(alignment: .leading, spacing: 0) { menuItems }
            .buttonStyle(_MenuItemButtonStyle())
            .padding(.horizontal, 1)
            .border()
        // Size the menu to its own content before rendering it. Laying it out
        // against the whole screen made a menu of three short items span the
        // terminal: `Divider` MEASURES as one cell but RENDERS at the width it
        // is offered, and a VStack takes its width from what its children
        // actually drew — so one separator inflated the popover to whatever it
        // was handed. Measuring first (where the divider claims its true one
        // cell and the buttons hug their labels) yields the natural hug width;
        // rendering at that width then makes the divider span exactly the
        // menu's interior, which is the separator look we want anyway.
        //
        // Measured through the SAME context the render uses, so `@State` and
        // focus slots resolve to the same identities either way (362c8839).
        let natural = measureChild(
            menuView,
            proposal: ProposedSize(
                width: context.environment.terminalWidth,
                height: context.environment.overlayContentHeight),
            context: menuContext)
        let menuWidth = max(1, min(natural.width, context.environment.terminalWidth))
        menuContext = menuContext.withAvailableWidth(menuWidth)
        // Now that the width is known, hand it to the rows so their highlight
        // reads as a bar across the menu rather than a tag around the label.
        // Deliberately AFTER the measure: a row that knew its width up front
        // would report it, and the menu would size itself from its own guess.
        // (2 border columns + the 1-cell padding on each side.)
        menuContext.environment.menuRowWidth = max(1, menuWidth - 4)
        var menuBuffer = renderPresentedDialog(
            menuView, context: menuContext, capHeight: context.environment.overlayContentHeight)
        guard !menuBuffer.isEmpty else { return baseBuffer }

        attachDismissBackdrop(to: &menuBuffer, state: state, context: context)

        // Float the menu at the click point (content-local anchor → absolute in
        // composition). `.popover` level; `anchorHeight: 0` nudges it on-screen at
        // the edges rather than flipping above a control.
        baseBuffer.overlays.append(
            OverlayLayer(
                offsetX: state.anchorX, offsetY: state.anchorY, content: menuBuffer,
                level: .popover, anchorHeight: 0))
        return baseBuffer
    }

    /// Attaches the whole-content secondary-click trigger. Registered normally
    /// (so a right-click bubbling past the content's own regions reaches it —
    /// see `MouseEventDispatcher.dispatch`'s right-button fall-through); it opens
    /// on a right-click or Ctrl-click release and records the click cell as the
    /// menu anchor.
    private func attachTrigger(
        to buffer: inout FrameBuffer, state: ContextMenuState, context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        let handlerID = dispatcher.register { event in
            // Secondary click = right button, or Ctrl + left (the fallback where a
            // terminal claims right-click for itself, e.g. iTerm2 by default).
            let isSecondary =
                event.button == .right || (event.button == .left && event.ctrl)
            guard isSecondary else { return false }
            switch event.phase {
            case .pressed:
                return true  // claim so the matching release routes back here
            case .released:
                state.anchorX = event.x
                state.anchorY = event.y
                state.isOpen = true
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: max(1, buffer.width), height: max(1, buffer.height),
                handlerID: handlerID))
    }

    /// Inserts the screen-covering dismiss backdrop (as the drop-down menus do):
    /// a first-registered region that closes the menu on any non-wheel press
    /// outside it, while every region of the menu itself wins over it and the
    /// wheel still falls through to the page.
    private func attachDismissBackdrop(
        to buffer: inout FrameBuffer, state: ContextMenuState, context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher
        else { return }
        let dismissID = dispatcher.register { event in
            switch event.phase {
            case .pressed where !event.button.isWheel:
                state.isOpen = false
                return true
            case .released:
                return true  // the consumed press's matching release
            default:
                return false
            }
        }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: -4096, offsetY: -4096, width: 8192, height: 8192, handlerID: dismissID),
            at: 0)
    }
}

// MARK: - Layoutable

extension ContextMenuModifier: Layoutable {
    /// The menu is presented *over* the content, so the layout footprint is just
    /// the content — and forwarding keeps the focus-section / trigger side effects
    /// on the render pass, never a measure.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: context.withChildIdentity(type: Content.self, index: 0))
    }
}

// MARK: - View extension

extension View {
    /// Adds a context menu (right-click / Ctrl-click pop-up of `Button`s) to this
    /// view — mirrors SwiftUI's `contextMenu(menuItems:)`.
    ///
    /// ```swift
    /// Text("Right-click me")
    ///     .contextMenu {
    ///         Button("Cut") { … }
    ///         Button("Copy") { … }
    ///         Divider()
    ///         Button("Delete", role: .destructive) { … }
    ///     }
    /// ```
    ///
    /// Selecting an item runs its action and closes the menu; Escape or an
    /// outside click also dismisses it. The primary trigger is a right-click;
    /// where the terminal swallows that (iTerm2 does by default) a **Ctrl-click**
    /// opens it too. Right-clicking works reliably in Apple Terminal, Ghostty and
    /// Warp (see `Documentation/Terminal-compatibility.md`).
    ///
    /// - Parameter menuItems: A view builder of the menu's `Button`s (and
    ///   `Divider`s).
    /// - Returns: A view that shows the context menu on secondary-click.
    public func contextMenu<MenuItems: View>(
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        ContextMenuModifier(content: self, menuItems: menuItems())
    }
}
