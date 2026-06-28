//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitViewResize.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Resizable Environment Value

/// Whether ``NavigationSplitView`` dividers can be resized.
private struct NavigationSplitViewResizableKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a ``NavigationSplitView`` lets the user resize its columns by
    /// dragging the divider (mouse) or focusing it and pressing the arrow keys.
    ///
    /// `true` by default — matching AppKit/SwiftUI, where split columns are
    /// draggable. Set with ``View/navigationSplitViewResizable(_:)``.
    public var navigationSplitViewResizable: Bool {
        get { self[NavigationSplitViewResizableKey.self] }
        set { self[NavigationSplitViewResizableKey.self] = newValue }
    }
}

extension View {
    /// Controls whether a ``NavigationSplitView`` in this view can have its
    /// columns resized.
    ///
    /// Split views are resizable by default. Pass `false` to pin the columns
    /// to their configured widths (no divider handle, no drag, no keyboard
    /// resize). This is a terminal-specific affordance — SwiftUI's split
    /// columns are always resizable — so it is a modifier rather than an
    /// `init` parameter, keeping ``NavigationSplitView``'s initializer matched
    /// to SwiftUI.
    ///
    /// ```swift
    /// NavigationSplitView { Sidebar() } detail: { Detail() }
    ///     .navigationSplitViewResizable(false)
    /// ```
    ///
    /// - Parameter resizable: Whether columns can be resized (default `true`).
    /// - Returns: A view with the resizability preference applied.
    public func navigationSplitViewResizable(_ resizable: Bool = true) -> some View {
        environment(\.navigationSplitViewResizable, resizable)
    }
}

// MARK: - Persistent Column Widths

/// The width of each resizable (non-trailing) column of a
/// ``NavigationSplitView``, keyed by column index. Persisted in
/// `StateStorage` so a drag / keyboard resize survives across renders. The
/// trailing column is always flexible and absorbs the remaining width, so it
/// is never stored here.
///
/// A column is either **style-derived** (its width comes from the active
/// ``NavigationSplitViewStyle``'s proportions, recomputed each frame and stored
/// only so a first drag/keyboard resize has a seed) or **user-set** (the user
/// dragged or keyed it, after which it is pinned to that intent and no longer
/// follows the style). ``isUserSet(_:)`` distinguishes them. This is what lets
/// changing the style re-flow the columns that the user hasn't touched, while
/// still honouring an explicit resize.
///
/// Stored values are the *effective* width after the previous frame: the split
/// view clamps the raw intent / style default to the viable range each render
/// and writes the clamped result back via ``setClamped(_:for:)``.
final class SplitViewWidths {
    private var widths: [Int: Int] = [:]
    /// Columns the user has explicitly resized (drag / keyboard). These override
    /// the style default; columns absent here track the style.
    private var userSet: Set<Int> = []

    func value(for column: Int) -> Int? { widths[column] }

    /// Whether `column` has been explicitly resized by the user (so it should
    /// override the style default).
    func isUserSet(_ column: Int) -> Bool { userSet.contains(column) }

    /// Records an explicit user resize: stores the width *and* pins the column
    /// to user intent so it no longer follows the style. Called by the drag and
    /// keyboard handlers.
    func set(_ width: Int, for column: Int) {
        widths[column] = width
        userSet.insert(column)
    }

    /// Stores the clamped effective width for a frame *without* marking the
    /// column as user-set. Used by the split view's per-frame write-back so a
    /// style-derived column keeps a valid drag/keyboard seed while still
    /// re-deriving from the style when the style changes.
    func setClamped(_ width: Int, for column: Int) { widths[column] = width }
}

// MARK: - Divider Handler (keyboard + drag)

/// Drives one resizable divider of a ``NavigationSplitView``.
///
/// As a ``Focusable`` it is reachable in the Tab order (each divider lives in
/// its own focus section, interleaved between the column sections) and resizes
/// the column to its left with the arrow keys: ←/→ by one cell (Shift by five),
/// Home/End to the narrowest / widest the layout allows. It also carries the
/// drag anchor for the mouse path — the split view's divider hit-test region
/// reads ``dragStartWidth`` so a drag adjusts the column relative to where the
/// press began.
///
/// It only mutates the shared ``SplitViewWidths`` (raw intent); the split
/// view's width calculation clamps and writes back the effective value, so the
/// arrow keys always step from the real current width. A consumed key /
/// mouse event makes the run loop repaint, so no explicit render request is
/// needed here (same model as ``ItemListHandler``).
final class _SplitDividerHandler: Focusable {
    let focusID: String

    /// The index of the column this divider resizes (the one on its left).
    let columnIndex: Int

    /// Shared, persisted column widths.
    let widths: SplitViewWidths

    /// The smallest a column may become.
    let minimumColumnWidth: Int

    var canBeFocused: Bool

    /// The column's width when the current mouse drag began, or `nil` when no
    /// drag is in progress. Set on `.pressed`, read on `.dragged`/`.released`.
    var dragStartWidth: Int?

    /// Whether the cursor is currently over the divider. Drives the subtle
    /// hover pulse of the grip dots. Set on `.entered`/`.exited`.
    var isHovered: Bool = false

    init(
        focusID: String,
        columnIndex: Int,
        widths: SplitViewWidths,
        minimumColumnWidth: Int,
        canBeFocused: Bool = true
    ) {
        self.focusID = focusID
        self.columnIndex = columnIndex
        self.widths = widths
        self.minimumColumnWidth = minimumColumnWidth
        self.canBeFocused = canBeFocused
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        let step = event.shift ? 5 : 1
        let current = widths.value(for: columnIndex) ?? minimumColumnWidth
        switch event.key {
        case .left:
            widths.set(current - step, for: columnIndex)
            return true
        case .right:
            widths.set(current + step, for: columnIndex)
            return true
        case .home:
            // Narrowest — the render clamp pins it to minimumColumnWidth.
            widths.set(minimumColumnWidth, for: columnIndex)
            return true
        case .end:
            // Widest — a large value the render clamp pins to the layout max.
            widths.set(Int.max / 4, for: columnIndex)
            return true
        default:
            return false
        }
    }
}
