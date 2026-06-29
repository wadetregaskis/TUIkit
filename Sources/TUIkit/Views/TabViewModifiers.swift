//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewModifiers.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// The TUI-specific environment modifiers for ``TabView`` (header alignment,
// header wrapping, content sizing, content padding). SwiftUI has no equivalent
// for any of these, so they are kept separate from the SwiftUI-parity
// ``View/tabViewStyle(_:)`` (which lives with the core in TabView.swift).

// MARK: - Header alignment (TUI-specific)

private struct TabViewHeaderAlignmentKey: EnvironmentKey {
    static let defaultValue: HorizontalAlignment = .center
}

extension EnvironmentValues {
    /// How the tab strip is aligned across the width of a `TabView`.
    public var tabViewHeaderAlignment: HorizontalAlignment {
        get { self[TabViewHeaderAlignmentKey.self] }
        set { self[TabViewHeaderAlignmentKey.self] = newValue }
    }
}

extension View {
    /// Aligns the tab headers (leading, centre, or trailing) within `TabView`s
    /// in this view. Defaults to ``HorizontalAlignment/center``.
    ///
    /// TUI-specific: SwiftUI has no equivalent, so this is kept separate from the
    /// SwiftUI-parity ``tabViewStyle(_:)``.
    public func tabViewHeaderAlignment(_ alignment: HorizontalAlignment) -> some View {
        environment(\.tabViewHeaderAlignment, alignment)
    }
}

// MARK: - Header wrapping (TUI-specific)

/// How eagerly a `TabView` wraps its header strip onto multiple rows.
public enum TabViewHeaderWrap: Sendable {
    /// Keep the headers on as few rows as fit the available width — wrap only
    /// when a single row would overflow. The panel may be as wide as the
    /// one-row strip. The default.
    case minimal
    /// Fold the headers to the width of the widest tab's content, even when
    /// there's room for fewer rows — so a many-tabbed view (a colour picker)
    /// stays as narrow as its content instead of being stretched wide by a long
    /// header strip.
    case toContentWidth
}

private struct TabViewHeaderWrapKey: EnvironmentKey {
    static let defaultValue: TabViewHeaderWrap = .minimal
}

extension EnvironmentValues {
    /// How `TabView`s in this view wrap their header strip.
    public var tabViewHeaderWrap: TabViewHeaderWrap {
        get { self[TabViewHeaderWrapKey.self] }
        set { self[TabViewHeaderWrapKey.self] = newValue }
    }
}

extension View {
    /// Controls how eagerly `TabView`s in this view wrap their header strip.
    /// Defaults to ``TabViewHeaderWrap/minimal`` (wrap only on overflow).
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    public func tabViewHeaderWrap(_ wrap: TabViewHeaderWrap) -> some View {
        environment(\.tabViewHeaderWrap, wrap)
    }
}

// MARK: - Content sizing (TUI-specific)

/// How a ``TabView`` sizes its content panel's height across tabs.
public enum TabViewContentSizing: Sendable {
    /// Size the panel to the *tallest* tab, so the panel height is stable and
    /// switching tabs doesn't resize it vertically. The default — it mirrors how
    /// the panel width already sizes to the widest tab.
    case largestTab
    /// Size the panel to the *active* tab only, so the panel shrinks/grows to
    /// each tab's content as you switch. The historical behaviour.
    case activeTab
}

private struct TabViewContentSizingKey: EnvironmentKey {
    static let defaultValue: TabViewContentSizing = .largestTab
}

extension EnvironmentValues {
    /// How `TabView`s in this view size their content panel's height.
    public var tabViewContentSizing: TabViewContentSizing {
        get { self[TabViewContentSizingKey.self] }
        set { self[TabViewContentSizingKey.self] = newValue }
    }
}

extension View {
    /// Controls how `TabView`s in this view size their content panel's height.
    /// Defaults to ``TabViewContentSizing/largestTab`` (size to the tallest tab,
    /// so switching tabs doesn't resize the panel vertically).
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    public func tabViewContentSizing(_ sizing: TabViewContentSizing) -> some View {
        environment(\.tabViewContentSizing, sizing)
    }
}

// MARK: - Content padding (TUI-specific)

private struct TabViewContentPaddingKey: EnvironmentKey {
    /// `nil` means "use the per-style default" (none for ``TabViewStyle/compact``,
    /// a comfortable inset for ``TabViewStyle/bordered``).
    static let defaultValue: EdgeInsets? = nil
}

extension EnvironmentValues {
    /// The interior padding applied around every tab's content. `nil` resolves
    /// to the per-style default.
    public var tabViewContentPadding: EdgeInsets? {
        get { self[TabViewContentPaddingKey.self] }
        set { self[TabViewContentPaddingKey.self] = newValue }
    }
}

extension View {
    /// Sets the interior padding around the content of every tab in `TabView`s
    /// within this view. Applied to the full content subtree, so a single
    /// application on the `TabView` covers all of its tabs.
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    public func tabViewContentPadding(_ insets: EdgeInsets) -> some View {
        environment(\.tabViewContentPadding, insets)
    }

    /// Sets a uniform interior padding around every tab's content.
    public func tabViewContentPadding(_ length: Int) -> some View {
        environment(\.tabViewContentPadding, EdgeInsets(all: length))
    }
}
