//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TooltipStyle.swift
//
//  Whether tooltips appear, how they are presented, and how long the pointer
//  must rest first — three subtree settings, so a panel can differ from the app.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - TooltipStyle

/// How a tooltip is presented.
///
/// TUI-specific: SwiftUI has one presentation because a desktop has one, and a
/// terminal has a genuine choice between spending a row of chrome and floating
/// a panel over the content. Both are drawn from the same ``TooltipState``, so
/// an app can switch between them without touching a single `help(_:)`.
public enum TooltipStyle: Sendable, Equatable, CaseIterable {
    /// A row in the status bar, above the shortcut items.
    ///
    /// Costs a row of the content area while a tooltip is up, and never covers
    /// anything. The bar grows and shrinks with the tooltip rather than
    /// reserving the row permanently: the shift is synchronous with the tooltip
    /// — the content moves and the text appears in the same frame — which reads
    /// as one event rather than two.
    case statusBar

    /// A panel attached to the control, floated over the content.
    ///
    /// Costs no layout and covers whatever is beside the control. Placed by the
    /// same flip-and-clamp rule a drop-down menu uses.
    case popover
}

// MARK: - TooltipVisibility

/// Whether tooltips are shown at all.
public enum TooltipVisibility: Sendable, Equatable, CaseIterable {
    /// Shown — on hover after the delay, or on the help key.
    case automatic

    /// Never shown. `help(_:)` still compiles and still publishes; nothing
    /// draws it.
    case hidden
}

// MARK: - Environment

private struct TooltipStyleKey: EnvironmentKey {
    static let defaultValue: TooltipStyle = .statusBar
}

private struct TooltipVisibilityKey: EnvironmentKey {
    static let defaultValue: TooltipVisibility = .automatic
}

private struct TooltipDelayKey: EnvironmentKey {
    /// macOS's own tooltip delay, near enough. Long enough that crossing a
    /// control on the way somewhere else does not flash a tooltip, short enough
    /// that resting on one deliberately does not feel broken.
    static let defaultValue: Double = 0.6
}

extension EnvironmentValues {
    /// How tooltips in this subtree are presented. Default ``TooltipStyle/statusBar``.
    public var tooltipStyle: TooltipStyle {
        get { self[TooltipStyleKey.self] }
        set { self[TooltipStyleKey.self] = newValue }
    }

    /// Whether tooltips in this subtree are shown. Default ``TooltipVisibility/automatic``.
    public var tooltipVisibility: TooltipVisibility {
        get { self[TooltipVisibilityKey.self] }
        set { self[TooltipVisibilityKey.self] = newValue }
    }

    /// How long the pointer must rest before a hover tooltip appears, in
    /// seconds. Default 0.6.
    public var tooltipDelay: Double {
        get { self[TooltipDelayKey.self] }
        set { self[TooltipDelayKey.self] = newValue }
    }
}

// MARK: - Modifiers

extension View {
    /// Sets how tooltips in this subtree are presented.
    ///
    /// ```swift
    /// ContentView().tooltipStyle(.popover)
    /// ```
    public func tooltipStyle(_ style: TooltipStyle) -> some View {
        environment(\.tooltipStyle, style)
    }

    /// Sets whether tooltips in this subtree are shown.
    ///
    /// `help(_:)` still compiles and still publishes under
    /// `TooltipVisibility.hidden`; nothing draws it. That is deliberate — the
    /// alternative is a modifier whose effect depends on where in the tree the
    /// reader happens to look.
    public func tooltips(_ visibility: TooltipVisibility) -> some View {
        environment(\.tooltipVisibility, visibility)
    }

    /// Sets how long the pointer must rest on a view before its tooltip
    /// appears.
    ///
    /// Does not affect the help key, which reveals the focused view's tooltip
    /// at once — a key press has already waited.
    ///
    /// - Parameter seconds: The delay. Clamped at zero when read.
    public func tooltipDelay(_ seconds: Double) -> some View {
        environment(\.tooltipDelay, seconds)
    }
}
