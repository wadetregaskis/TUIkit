//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewEnvironmentKeys.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Badge Environment Key

/// Environment key for badge values.
private struct BadgeKey: EnvironmentKey {
    static let defaultValue: BadgeValue? = nil
}

extension EnvironmentValues {
    /// The current badge value.
    ///
    /// Used to display decorative badges on list rows or other views.
    /// Set via `.badge()` modifier on views.
    var badgeValue: BadgeValue? {
        get { self[BadgeKey.self] }
        set { self[BadgeKey.self] = newValue }
    }
}

// MARK: - Terminal Height Environment Key

/// Environment key for the terminal's total height in rows.
private struct TerminalHeightKey: EnvironmentKey {
    static let defaultValue: Int = 24
}

/// Environment key for the terminal's total width in columns.
private struct TerminalWidthKey: EnvironmentKey {
    static let defaultValue: Int = 80
}

/// Environment key for the height of the content area available to overlays —
/// the screen minus the app header and the status bar.
private struct OverlayContentHeightKey: EnvironmentKey {
    static let defaultValue: Int = 24
}

extension EnvironmentValues {
    /// The terminal's total height in rows, published once at the render root.
    ///
    /// Unlike a context's `availableHeight` — which a ``ScrollView`` inflates to a
    /// tall measure budget — this stays the true screen height however deep the
    /// reader sits, letting an overlay (e.g. a ``Picker`` drop-down) size itself to
    /// the visible area. Defaults to a conservative 24 when no render loop has set
    /// it (e.g. in isolated tests).
    ///
    /// Public so an app can lay out responsively against the real screen size —
    /// e.g. switch a row of panels to a column when the terminal is short. It is
    /// published once per frame at the render root, so it is identical across a
    /// view's measure and render passes (branching on it never oscillates).
    public var terminalHeight: Int {
        get { self[TerminalHeightKey.self] }
        set { self[TerminalHeightKey.self] = newValue }
    }

    /// The terminal's total width in columns, published once at the render root.
    ///
    /// Like ``terminalHeight``, this is the true screen width however deep the
    /// reader sits — unlike a context's `availableWidth`, which is only whatever a
    /// leaf was offered. A screen-level overlay (e.g. a centred modal) renders
    /// against it so it isn't clipped to its attachment's local area. Defaults to 80.
    ///
    /// Public so an app can lay out responsively against the real screen width —
    /// e.g. place two panels side by side only when there is room, and stack
    /// them otherwise. It is published once per frame at the render root, so it
    /// is identical across a view's measure and render passes (branching on it
    /// never oscillates, unlike a context's `availableWidth`).
    public var terminalWidth: Int {
        get { self[TerminalWidthKey.self] }
        set { self[TerminalWidthKey.self] = newValue }
    }

    /// The height (in rows) of the content area that overlays composite into —
    /// the screen height minus the app header and status bar. Published once at
    /// the render root, alongside ``terminalHeight``.
    ///
    /// An anchored overlay (e.g. a ``Picker`` drop-down) must size itself to this,
    /// **not** ``terminalHeight``: the compositor clamps overlays to this area (so
    /// they never overlap the status bar), so a drop-down sized to the full screen
    /// height would have its bottom border and last rows shaved off — reading as
    /// "clipped behind the status bar". Defaults to 24 (no chrome reserved) for
    /// isolated tests with no render loop.
    var overlayContentHeight: Int {
        get { self[OverlayContentHeightKey.self] }
        set { self[OverlayContentHeightKey.self] = newValue }
    }
}

// MARK: - List Style Environment Key

/// Environment key for list styles.
private struct ListStyleKey: EnvironmentKey {
    static let defaultValue: any ListStyle = InsetGroupedListStyle()
}

extension EnvironmentValues {
    /// The current list style.
    ///
    /// Controls how lists render, including borders, padding, and row backgrounds.
    /// Set via `.listStyle()` modifier on List views.
    /// Default: ``InsetGroupedListStyle`` (bordered with alternating rows).
    var listStyle: any ListStyle {
        get { self[ListStyleKey.self] }
        set { self[ListStyleKey.self] = newValue }
    }
}

// MARK: - Selection Disabled Environment Key

/// Environment key for selection disabled state.
private struct SelectionDisabledKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Whether selection is disabled for this view.
    ///
    /// When true, the view cannot be selected in a List.
    /// Set via `.selectionDisabled()` modifier.
    var isSelectionDisabled: Bool {
        get { self[SelectionDisabledKey.self] }
        set { self[SelectionDisabledKey.self] = newValue }
    }
}

// MARK: - Unfocused Selection Visibility Environment Key

/// Environment key for unfocused-selection-visibility configuration.
private struct UnfocusedSelectionVisibilityKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether a List or Table renders its selection highlight
    /// when the list itself does not have focus.
    ///
    /// - `.automatic` (default): resolves to visible — the
    ///   selected row is rendered with a desaturated accent
    ///   background while the list is unfocused, matching
    ///   desktop list-view convention (Finder, Explorer, etc.).
    /// - `.visible`: same as `.automatic` for now. Reserved for
    ///   future per-style behaviour.
    /// - `.hidden`: the selected row blends in with non-selected
    ///   rows while the list is unfocused. The selection binding
    ///   is unaffected; only the visual indicator is suppressed.
    ///   Useful when the list is a transient picker rather than a
    ///   persistent surface where the user expects to see what
    ///   they have selected at all times.
    ///
    /// Set via ``View/unfocusedSelectionVisibility(_:)``.
    var unfocusedSelectionVisibility: Visibility {
        get { self[UnfocusedSelectionVisibilityKey.self] }
        set { self[UnfocusedSelectionVisibilityKey.self] = newValue }
    }
}
