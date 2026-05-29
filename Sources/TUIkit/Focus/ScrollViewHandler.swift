//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ScrollViewHandler

/// A focus handler for ``ScrollView``.
///
/// `ScrollViewHandler` owns the scroll-position state and the
/// keyboard-driven scroll navigation for a `ScrollView`. It is a
/// peer of ``ItemListHandler`` for the no-selection,
/// no-row-structure case: there is just a viewport over a taller
/// content area, and the keys and the wheel move where that
/// viewport lands.
///
/// # Interaction model
///
/// - **Mouse wheel** scrolls by ``ViewConstants/mouseWheelScrollLines``
///   lines per tick. Wheel scrolling is independent of focus —
///   the wheel works whether or not the scroll view itself has
///   focus, matching the rest of TUIkit (see ``ItemListHandler``).
/// - **Arrow keys** scroll by one line at a time. **Page Up** /
///   **Page Down** scroll by one viewport height. **Home** /
///   **End** jump to the very top / bottom. All keyboard
///   scrolling requires the scroll view to have focus.
///
/// The handler does not track selection — there is no
/// "currently focused row" concept in a generic scroll view.
///
/// > Note: Like ``ItemListHandler`` and ``TextFieldHandler``,
///   `ScrollViewHandler` isn't marked `@MainActor`. The
///   framework guarantees handlers are only touched from the
///   render loop / event dispatch (both `@MainActor`), so the
///   nonisolated class conforms cleanly to the nonisolated
///   `Focusable` protocol without crossing an isolation
///   boundary.
public final class ScrollViewHandler: Focusable, ScrollableOffsetState {

    /// The unique focus identifier for this scroll view.
    public let focusID: String

    /// Whether this scroll view can currently receive focus.
    ///
    /// Disabled scroll views still scroll on wheel input (clicks
    /// reach them via the hit-test region), but cannot become
    /// the keyboard focus.
    public var canBeFocused: Bool

    /// The current scroll position, measured in lines from the
    /// top of the content. Always in `0...max(0, contentHeight -
    /// viewportHeight)`.
    public var scrollOffset: Int = 0

    /// The total natural height of the scroll view's content,
    /// computed during the layout pass.
    public var contentHeight: Int = 0

    /// The visible height of the scroll view's viewport.
    public var viewportHeight: Int = 0

    /// Creates a scroll-view handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - canBeFocused: Whether the handler can receive focus.
    public init(focusID: String, canBeFocused: Bool = true) {
        self.focusID = focusID
        self.canBeFocused = canBeFocused
    }
}

// MARK: - ScrollableOffsetState conformance

extension ScrollViewHandler {

    /// The extent that ``ScrollableOffsetState`` measures
    /// against. For ``ScrollViewHandler`` that's
    /// ``contentHeight`` — total natural lines.
    public var extent: Int { contentHeight }
}

// MARK: - Convenience

extension ScrollViewHandler {

    /// Jumps to the top of the content.
    public func scrollToTop() { scrollOffset = 0 }

    /// Jumps to the bottom of the content.
    public func scrollToBottom() { scrollOffset = maxOffset }
}

// MARK: - Key Event Handling

extension ScrollViewHandler {

    /// Handles a key event while the scroll view has focus.
    /// Up / Down scroll one line; Page Up / Page Down scroll one
    /// viewport; Home / End jump to top / bottom. Other keys are
    /// not consumed.
    ///
    /// - Parameter event: The incoming key event.
    /// - Returns: `true` if the key was a scroll command.
    public func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .up:
            scroll(by: -1)
            return true
        case .down:
            scroll(by: 1)
            return true
        case .pageUp:
            scroll(by: -max(1, viewportHeight))
            return true
        case .pageDown:
            scroll(by: max(1, viewportHeight))
            return true
        case .home:
            scrollToTop()
            return true
        case .end:
            scrollToBottom()
            return true
        default:
            return false
        }
    }
}
