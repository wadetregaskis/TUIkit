//  🖥️ TUIKit — Terminal UI Kit for Swift
//  InputHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Input Handler

/// Dispatches key events through a five-layer priority chain (layers 0–4).
///
/// The dispatch order is:
/// 0. **Text input** (conditional) — a focused `TextField`/`SecureField`
///    consumes the event first
/// 1. **Status bar** — items with actions
/// 2. **View handlers** — registered via `onKeyPress` modifiers
/// 3. **Focus system** (conditional) — Tab/Shift+Tab navigation, Enter/Space
///    on focused buttons
/// 4. **Default bindings** — `q` (quit), `t` (theme), `a` (appearance)
///
/// Layers 0 and 3 are mutually exclusive, gated on
/// `focusManager.hasTextInputFocus`: when a text-input element is focused,
/// layer 0 runs and layer 3 is skipped. If a layer consumes the event,
/// subsequent layers are skipped. (An open modal that has claimed Escape is a
/// special case routed through the focus system ahead of layer 1 — see
/// `handle(_:)`.)
internal struct InputHandler {
    /// The status bar state for item-level event handling.
    let statusBar: StatusBarState

    /// The key event dispatcher for view-registered handlers.
    let keyEventDispatcher: KeyEventDispatcher

    /// The focus manager for Tab navigation and focused element activation.
    let focusManager: FocusManager

    /// The palette manager for theme cycling (`t` key).
    let paletteManager: ThemeManager

    /// The appearance manager for appearance cycling (`a` key).
    let appearanceManager: ThemeManager

    /// Called when the user requests to quit the application.
    let onQuit: () -> Void
}

// MARK: - Internal API

extension InputHandler {
    /// Dispatches a key event through the five-layer priority chain.
    ///
    /// - Parameter event: The key event to handle.
    /// - Returns: `true` if some layer consumed the event. The run loop uses
    ///   this to request a render — a consumed key has, by definition, done
    ///   something (moved focus, activated a control, typed text, cycled the
    ///   theme), and much of that mutates state the demand-driven loop can't
    ///   otherwise observe. In particular `ItemListHandler`/`FocusManager` move
    ///   their focus/scroll position through plain stored properties, not
    ///   `@State`, so nothing calls `setNeedsRender()` for them; without this
    ///   signal arrow-key navigation in a `List` would change the selection but
    ///   never repaint. (Symmetric with the mouse path, which already re-renders
    ///   when a handler consumes an event.) An unconsumed key returns `false`
    ///   so a genuine no-op key doesn't wake the loop.
    @discardableResult
    func handle(_ event: KeyEvent) -> Bool {
        // Layer 0: Text input (conditional). When a text-input element
        // (TextField/SecureField) is focused, let it handle the event FIRST.
        // This ensures printable characters, backspace, delete, arrows, home,
        // end, and enter reach the text field before any other layer can
        // intercept them.
        //
        // Only structural/navigation keys that the text field does NOT consume
        // (Escape, Tab, unhandled Ctrl+shortcuts) fall through to other layers.
        // Mutually exclusive with Layer 3 (focus system), which is skipped
        // below when text input has focus.
        if focusManager.hasTextInputFocus {
            if focusManager.dispatchKeyEvent(event) {
                return true
            }
        }

        // Modal-claimed ESC: when an open Picker drop-down (or similar
        // transient surface) has signalled "I own ESC for this frame" by
        // setting `escapeLabelOverride`, route the key through the focus
        // system *before* the status bar or any view-registered handler
        // gets a shot. Otherwise a page-level onKeyPress that returns to
        // the menu (the example app's ContentView, for one) would close
        // the page out from under the open drop-down.
        if event.key == .escape, statusBar.escapeLabelOverride != nil,
            !focusManager.hasTextInputFocus
        {
            if focusManager.dispatchKeyEvent(event) {
                return true
            }
        }

        // Layer 1: Status bar items with actions
        if statusBar.handleKeyEvent(event) {
            return true
        }

        // Layer 2: View-registered key handlers (onKeyPress, Menu arrow keys)
        if keyEventDispatcher.dispatch(event) {
            return true
        }

        // Layer 3: Focus system (Tab navigation, Enter/Space on focused buttons)
        // Skipped when text-input has focus since it was already dispatched above.
        if !focusManager.hasTextInputFocus {
            if focusManager.dispatchKeyEvent(event) {
                return true
            }
        }

        // Layer 4: Default key bindings
        if statusBar.quitShortcut.matches(event) {
            if statusBar.isQuitAllowed {
                onQuit()
            }
            return true
        }

        switch event.key {
        case .character(let character) where character == "t" || character == "T":
            if statusBar.showThemeItem {
                paletteManager.cycleNext()
                return true
            }
            return false

        case .character(let character) where character == "a" || character == "A":
            appearanceManager.cycleNext()
            return true

        default:
            return false
        }
    }
}
