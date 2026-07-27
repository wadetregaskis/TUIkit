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
@MainActor
final class ContextMenuState {
    /// Whether the menu is currently shown.
    var isOpen = false
    /// The open menu's highlight and its rows — see ``MenuPopupController``.
    let controller = MenuPopupController()
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
    static let focusID = 1
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
            // The keyboard trigger runs FIRST, because it is what registers the
            // focus stop — and the content has to be told whether that stop
            // holds the focus before it draws itself. Nobody else can say so:
            // the focusable thing here is the caller's own view, so only the
            // caller can decide what part of it shows the focus (see
            // `EnvironmentValues.isFocused`).
            var contentContext = contentContext
            if !context.isMeasuring {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
                context.environment.focusManager?.deactivateSection(id: sectionID)
                contentContext.environment.isFocused = attachKeyboardTrigger(
                    state: state, context: context)
            }
            var buffer = TUIkit.renderToBuffer(content, context: contentContext)
            if !context.isMeasuring {
                attachTrigger(to: &buffer, state: state, context: context)
            }
            return buffer
        }

        // OPEN: render the content beneath as an inert backdrop (isolated from
        // focus / key / state) so its controls can't steal the menu's focus. NOT
        // dimmed — a context menu is a popover, not a modal.
        var baseBuffer = TUIkit.renderToBuffer(
            content, context: contentContext.isolatedForBackground())
        // The presentation itself is shared with the pop-up `Menu`: same
        // bordered column of Buttons, same focus/keyboard grab, same dismiss
        // backdrop. Only the trigger and the anchor differ — here, the cell the
        // secondary click landed on (content-local; composition makes it
        // absolute).
        presentMenuPopover(
            items: menuItems, over: &baseBuffer, controller: state.controller,
            sectionID: sectionID, itemsIndex: 1,
            anchor: (state.anchorX, state.anchorY),
            dismiss: {
                state.isOpen = false
                state.controller.closed()
            }, context: context)
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
                // Opened by the pointer: nothing is chosen yet.
                state.controller.opened(withSelection: false)
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

    /// Makes the content a focus stop and opens the menu on **Shift+F10** while
    /// it holds focus — the keyboard route to a menu that otherwise only a
    /// right-click can reach.
    ///
    /// Shift+F10 because it is the one binding every platform with a keyboard
    /// context-menu route agrees on (Windows, GTK, every browser); macOS has no
    /// native equivalent, and a Mac keyboard has no Menu key to offer instead.
    /// It arrives as `ESC[21;2~` in iTerm2, Ghostty, Warp and xterm. Apple
    /// Terminal has no modifier encoding for function keys and sends `ESC[32~`
    /// (its alias for F18) instead; `Terminal.finalize` normalises that back to
    /// Shift+F10 — see `Documentation/Terminal-compatibility.md`.
    ///
    /// The focus stop is the price of the feature: you cannot key a menu open on
    /// a view you cannot reach. It consumes no keys of its own
    /// (`triggerKeys: []`), so content that is already interactive keeps every
    /// binding it had.
    ///
    /// - Returns: Whether that focus stop currently holds the focus, for the
    ///   content to publish as ``EnvironmentValues/isFocused``.
    @discardableResult
    private func attachKeyboardTrigger(state: ContextMenuState, context: RenderContext) -> Bool {
        guard context.environment.focusManager != nil, context.environment.isEnabled else {
            return false
        }
        let focusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil,
            defaultPrefix: "contextmenu-target", propertyIndex: StateIndex.focusID)
        FocusRegistration.register(
            context: context,
            handler: ActionHandler(focusID: focusID, action: {}, triggerKeys: []))

        context.environment.keyEventDispatcher!.addHandler(
            sectionID: context.environment.activeFocusSectionID
        ) { event in
            guard event.key == .f10, event.shift,
                FocusRegistration.isFocused(context: context, focusID: focusID)
            else { return false }
            // Anchored at the view's own top-left: there is no pointer to
            // anchor to, and a menu that appears ON the thing it belongs to is
            // the least surprising place for it.
            state.anchorX = 0
            state.anchorY = 0
            state.isOpen = true
            // Opened from the keyboard, which has no other way to point at a
            // row: start on the first item so the arrows have somewhere to go.
            state.controller.opened(withSelection: true)
            return true
        }
        return FocusRegistration.isFocused(context: context, focusID: focusID)
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
    /// From the keyboard: the modified view becomes a focus stop, and
    /// **Shift+F10** opens the menu while it is focused — the binding every
    /// platform that has a keyboard context-menu route agrees on (macOS has
    /// none of its own, and Mac keyboards have no Menu key). TUI-specific: it
    /// is the reason a `.contextMenu` adds a Tab stop, which SwiftUI's does
    /// not, because a menu reachable only by mouse is not reachable at all.
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
