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

// MARK: - TooltipTrigger

/// When a subtree's tooltips appear.
///
/// One axis rather than two — a "shown at all" flag beside a "when" would
/// spell some states twice and others not at all — and the cases are ordered by
/// eagerness, each showing strictly more than the one above it.
///
/// TUI-specific. SwiftUI has no equivalent because it needs none: a pointer is
/// always present there, so hover is the whole of the answer.
public enum TooltipTrigger: Sendable, Equatable, CaseIterable {
    /// Never shown. `help(_:)` still compiles and still publishes; nothing
    /// draws it.
    case never

    /// On hover after ``EnvironmentValues/tooltipDelay``, or on the help key
    /// for whatever holds the focus.
    case automatic

    /// Everything ``TooltipTrigger/automatic`` shows, and additionally whenever
    /// a control takes the focus — a "beginner mode", where moving through a
    /// page explains it, with no help key to know about.
    ///
    /// The delay applies here too, and a control that keeps the focus across
    /// frames keeps its original deadline rather than restarting it, so tabbing
    /// briskly through a row of controls shows nothing and resting on one shows
    /// its help.
    case onFocus

    /// Every tooltip in the subtree, all at once, for as long as the subtree is on
    /// screen — a first-launch tour, or a "show me what all this is" key.
    ///
    /// Always as popovers, whatever ``EnvironmentValues/tooltipStyle`` says,
    /// because the status bar has one row and this mode has many tooltips.
    ///
    /// - Important: Panels are placed independently and do **not** avoid one
    ///   another. On a page with several nearby controls they will overlap. See
    ///   `Documentation/Tooltips.md` §5 — rules 4 and 5 are unbuilt, and mutual
    ///   avoidance is a further rule nobody has designed. Reach for this on a
    ///   sparse page, or one panel at a time.
    case always
}

extension TooltipTrigger {
    /// Whether a focus candidate shows without being asked for by the help key.
    ///
    /// Not `.always`: that mode does not route through the candidate slots at all
    /// — every `help(_:)` draws its own panel where it stands — so a focus
    /// candidate would be a second, redundant presentation of one of them.
    var revealsOnFocus: Bool { self == .onFocus }

    /// Whether every `help(_:)` in the subtree draws its own panel unprompted.
    var showsEverything: Bool { self == .always }

    /// How a candidate published under this trigger must be presented.
    ///
    /// ``always`` forces ``TooltipStyle/popover``, which is what keeps the status
    /// bar from ALSO showing the hovered one: the run loop decides the bar's
    /// content from the candidate's own style, having only the root environment to
    /// read, so the override has to travel on the candidate. That is the same
    /// reason `Candidate.style` exists at all.
    func presentation(_ style: TooltipStyle) -> TooltipStyle {
        showsEverything ? .popover : style
    }
}

// MARK: - Environment

private struct TooltipStyleKey: EnvironmentKey {
    static let defaultValue: TooltipStyle = .statusBar
}

private struct TooltipTriggerKey: EnvironmentKey {
    static let defaultValue: TooltipTrigger = .automatic
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

    /// When tooltips in this subtree appear. Default ``TooltipTrigger/automatic``.
    public var tooltipTrigger: TooltipTrigger {
        get { self[TooltipTriggerKey.self] }
        set { self[TooltipTriggerKey.self] = newValue }
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

    /// Sets when tooltips in this subtree appear.
    ///
    /// `help(_:)` still compiles and still publishes under
    /// ``TooltipTrigger/never``; nothing draws it. That is deliberate — the
    /// alternative is a modifier whose effect depends on where in the tree the
    /// reader happens to look.
    public func tooltips(_ trigger: TooltipTrigger) -> some View {
        environment(\.tooltipTrigger, trigger)
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
