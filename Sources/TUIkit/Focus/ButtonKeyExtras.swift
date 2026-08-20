//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonKeyExtras.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// Keys the focused button should answer beyond Return and Space, supplied by
/// whatever built a control out of it.
///
/// A disclosure header is a `Button` — the triangle and the label are one
/// control, as they are on macOS — and it also answers Left and Right, which
/// *set* the disclosure closed and open rather than toggling it. A button knows
/// nothing about disclosure, and a disclosure has no way to reach a focused
/// button's key handling from the outside, so the keys travel down the
/// environment and the button hands them to its focus handler along with its
/// own.
///
/// Focus-gating comes free: a `Focusable`'s `handleKeyEvent` is only ever
/// called for the element that has focus, so every other disclosure on the page
/// ignores the same keystroke without anyone testing for it.
///
/// ## Scope
///
/// The environment reaches everything below the write, so attach it to the
/// button and not to a subtree containing one. Both callers here wrap exactly
/// the header button, whose label is text. A `Button` nested inside another
/// button's *label* would inherit these keys; there is no such thing in this
/// framework, and the alternative — a mechanism that could name one button —
/// would need an identity the composing view does not have.
/// Main-actor by discipline rather than by annotation, as ``DepartureStore``
/// is: the closure is built during a render pass and called from key dispatch,
/// both of which run on the single run loop. The `@unchecked` is what lets it
/// sit in ``EnvironmentValues``, which every view copies.
struct ButtonKeyExtras: @unchecked Sendable {
    /// The keys to intercept. Anything outside this set is not offered.
    let keys: Set<Key>

    /// Handles one of ``keys``. Returning `false` lets the key fall through to
    /// the button's own triggers and then out of the control entirely, which is
    /// how "Left on an already-closed group" reaches whatever is outside it.
    let handle: (KeyEvent) -> Bool
}

private struct ButtonKeyExtrasKey: EnvironmentKey {
    static let defaultValue: ButtonKeyExtras? = nil
}

extension EnvironmentValues {
    /// Extra keys the button below this write should answer. See
    /// ``ButtonKeyExtras``.
    var buttonKeyExtras: ButtonKeyExtras? {
        get { self[ButtonKeyExtrasKey.self] }
        set { self[ButtonKeyExtrasKey.self] = newValue }
    }
}

extension View {
    /// Gives the button in this view extra keys to answer while it is focused.
    ///
    /// - Parameters:
    ///   - keys: Which keys to intercept.
    ///   - handle: What to do with one. `false` lets it fall through.
    /// - Returns: A view whose button answers those keys too.
    func buttonKeyExtras(
        keys: Set<Key>, handle: @escaping (KeyEvent) -> Bool
    ) -> some View {
        environment(\.buttonKeyExtras, ButtonKeyExtras(keys: keys, handle: handle))
    }
}
