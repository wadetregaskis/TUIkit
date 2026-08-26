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
