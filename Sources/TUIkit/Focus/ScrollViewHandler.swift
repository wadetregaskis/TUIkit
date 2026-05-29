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
@MainActor
public final class ScrollViewHandler: Focusable {

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

// MARK: - Scroll Position Helpers

extension ScrollViewHandler {

    /// The largest valid `scrollOffset` for the current content
    /// and viewport heights. Zero when the content fits entirely.
    public var maxOffset: Int {
        max(0, contentHeight - viewportHeight)
    }

    /// Whether the scroll view has content above the viewport
    /// (i.e. the user has scrolled down at least once).
    public var hasContentAbove: Bool {
        scrollOffset > 0
    }

    /// Whether the scroll view has content below the viewport.
    public var hasContentBelow: Bool {
        scrollOffset + viewportHeight < contentHeight
    }

    /// The half-open range of content rows currently visible.
    public var visibleRange: Range<Int> {
        guard contentHeight > 0 else { return 0..<0 }
        let end = min(contentHeight, scrollOffset + viewportHeight)
        return scrollOffset..<end
    }

    /// Moves the scroll position by `delta` rows. Negative values
    /// scroll up, positive values scroll down. Clamped to
    /// `0...maxOffset`. A no-op when the content already fits.
    ///
    /// - Parameter delta: The number of rows to scroll.
    public func scroll(by delta: Int) {
        guard delta != 0, viewportHeight > 0, contentHeight > viewportHeight else { return }
        scrollOffset = max(0, min(maxOffset, scrollOffset + delta))
    }

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
