//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyEvent.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Key Event Handler

/// Global key event handler.
///
/// Views can register handlers that are called when keys are pressed.
/// Handlers are processed in reverse order (most recent first).
final class KeyEventDispatcher: @unchecked Sendable {
    /// One registration: the handler and the focus section it rendered in.
    private struct Entry {
        /// The focus section that was active where this handler registered, or
        /// `nil` for a handler outside any section.
        let sectionID: String?
        let handler: (KeyEvent) -> Bool
    }

    /// Registered key handlers, in render (outside-in) order.
    private var handlers: [Entry] = []

    /// The section that currently owns the keyboard, if any.
    ///
    /// A presented surface — an alert, a modal, a context menu — sets this
    /// while it is up, and only handlers registered inside it run. The focus
    /// system already has this notion (``FocusManager/markSectionModal(id:)``),
    /// and a ROOT-attached presentation also gets it for free by rendering the
    /// page beneath through ``RenderContext/isolatedForBackground()``, which
    /// swaps in a throwaway dispatcher. But a popover attached to a LEAF — a
    /// `.contextMenu` on one `Text` — can only isolate its own subtree; its
    /// siblings still render into this dispatcher every frame and keep their
    /// handlers. `Menu`'s arrow handler is registered unconditionally and
    /// answers `true` to Up/Down, so it swallowed the arrows meant for an open
    /// context menu while Tab (which goes through the focus system, and WAS
    /// captured) worked. Cleared with the handlers each render pass.
    private var grabbingSectionID: String?

    /// Creates a new key event dispatcher.
    init() {}
}

// MARK: - Internal API

extension KeyEventDispatcher {
    /// Registers a key handler.
    ///
    /// - Parameters:
    ///   - sectionID: The focus section this handler renders in — pass
    ///     `context.environment.activeFocusSectionID`. A handler outside any
    ///     section passes `nil` and is silenced whenever some section holds the
    ///     keyboard.
    ///   - handler: A closure that returns true if the key was handled.
    func addHandler(sectionID: String? = nil, _ handler: @escaping (KeyEvent) -> Bool) {
        handlers.append(Entry(sectionID: sectionID, handler: handler))
    }

    /// The number of currently-registered handlers. Used by tests to assert
    /// that measure passes register nothing.
    var handlerCount: Int { handlers.count }

    /// Declares that `id` owns the keyboard for the rest of this frame — see
    /// ``grabbingSectionID``. Called by a presented surface as it renders.
    func grabInput(sectionID id: String) {
        grabbingSectionID = id
    }

    /// Clears all handlers, and any input grab.
    func clearHandlers() {
        handlers.removeAll()
        grabbingSectionID = nil
    }

    /// Dispatches a key event to handlers.
    ///
    /// - Parameter event: The key event to dispatch.
    /// - Returns: True if any handler consumed the event.
    @discardableResult
    func dispatch(_ event: KeyEvent) -> Bool {
        // Process in reverse order (most recent handlers first) — and, while a
        // surface holds the keyboard, only the handlers registered inside it.
        for entry in handlers.reversed()
        where grabbingSectionID == nil || entry.sectionID == grabbingSectionID {
            if entry.handler(event) { return true }
        }
        return false
    }
}
