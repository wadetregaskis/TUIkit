//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Focusable.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Focusable Protocol

/// A protocol for views that can receive focus.
///
/// Focusable views can receive keyboard input when focused.
/// The focus system manages which view currently has focus and
/// routes keyboard events accordingly.
public protocol Focusable: AnyObject {
    /// The unique identifier for this focusable element.
    var focusID: String { get }

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool { get }

    /// Called when this element receives focus.
    func onFocusReceived()

    /// Called when this element loses focus.
    func onFocusLost()

    /// Handles a key event when focused.
    ///
    /// - Parameter event: The key event to handle.
    /// - Returns: True if the event was consumed, false to propagate.
    func handleKeyEvent(_ event: KeyEvent) -> Bool
}

/// Defaults so a conformer only writes what it actually needs.
///
/// ``Focusable/handleKeyEvent(_:)`` has no default and must be implemented —
/// it is the whole reason to be focusable. Everything else is optional.
extension Focusable {
    /// Whether this handler will accept focus. `true` by default.
    ///
    /// Override — or set the stored property where the type has one — to drop
    /// out of the Tab ring dynamically: a disabled control, or a `ScrollView`
    /// whose content does not overflow, is a stop that can do nothing and so
    /// is only an obstacle. The focus manager reads this each pass, so the
    /// answer may change from frame to frame.
    public var canBeFocused: Bool { true }

    /// Called when this handler takes focus. Does nothing by default.
    ///
    /// The hook for focus-time side effects — a list scrolling its cursor row
    /// back into view, a field seeding its draft text. It runs during the
    /// render pass that assigns focus, so anything it changes must also be
    /// reflected by that same frame.
    public func onFocusReceived() {}

    /// Called when this handler loses focus. Does nothing by default.
    ///
    /// The counterpart to ``onFocusReceived()``: commit a pending edit, close
    /// a dropdown, stop a caret blinking.
    public func onFocusLost() {}
}

/// A ``Focusable`` that is kept in `StateStorage` and so outlives the frame
/// that built it.
///
/// Its ``Focusable/focusID`` is settable for exactly one reason. A control
/// re-resolves its declared id every frame — `.focusID(_:)` is an ordinary
/// modifier and its argument may be computed from state — while a persisted
/// handler is built ONCE, inside a `storage(for:default:)` autoclosure, from
/// whatever id was in force the first time the control drew. The focus ring
/// files a control under `handler.focusID` and nothing else, so from the second
/// frame on the ring knew it by its old name while the view drew and queried
/// focus under the new one, and the two could never agree again.
///
/// Handlers rebuilt every frame (``ActionHandler``) already agree with the
/// declaration by construction, and deliberately do not conform.
protocol PersistedFocusable: Focusable {
    var focusID: String { get set }
}

/// A control whose focus shows only in what it draws ITSELF, never in the
/// content below it.
///
/// A focus move drops the cached buffers at both ends of it (see
/// `FocusManager.invalidateCachedRender(of:)`). For most controls that has to
/// include everything below the control's identity, because that is where the
/// control draws itself: a core view renders its own label, or tells it how to
/// look. A `ScrollView`'s focus shows only in its scrollbar, which its core
/// draws after the content, and it passes the content nothing focus-dependent.
/// A focusable view INSIDE the content registers and clears for itself. So
/// only the scroll view's own identity and the buffers containing it are
/// dropped. Before this, tabbing onto a scroll view, or away from it, dropped
/// every row it held, and the next frame measured and drew them all again:
/// 6.8 ms for a 200-message chat.
///
/// Conform only when that is true of everything the control will ever put
/// below itself, including through the environment. A `List` does not qualify:
/// its rows draw the selection differently while it holds the focus.
protocol FocusDrawnOnlyAtItself: Focusable {}
