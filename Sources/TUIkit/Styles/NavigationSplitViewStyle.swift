//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - NavigationSplitViewVisibility

/// The visibility of the leading columns in a navigation split view.
///
/// Use a value of this type to control the visibility of the columns of a
/// ``NavigationSplitView``. Create a ``State`` property with a value of this
/// type, and pass a ``Binding`` to that state to the appropriate initializer.
///
/// ## Example
///
/// ```swift
/// @State private var visibility = NavigationSplitViewVisibility.all
///
/// NavigationSplitView(columnVisibility: $visibility) {
///     List(items, selection: $selected) { ... }
/// } detail: {
///     DetailView(item: selected)
/// }
/// ```
///
/// ## Visibility Options
///
/// - ``automatic``: Use the default visibility for the current context.
/// - ``all``: Show all columns.
/// - ``doubleColumn``: Show content and detail (hide sidebar in 3-column).
/// - ``detailOnly``: Show only the detail column.
public struct NavigationSplitViewVisibility: Equatable, Hashable, Sendable, Codable {
    /// The raw value representing the visibility state.
    private let rawValue: Int

    /// Use the default leading column visibility for the current context.
    ///
    /// In TUIkit, this resolves to ``all`` since terminal width is typically
    /// sufficient to display all columns.
    public static var automatic: Self {
        Self(rawValue: 0)
    }

    /// Show all columns of a navigation split view.
    ///
    /// For a two-column split view, this shows sidebar and detail.
    /// For a three-column split view, this shows sidebar, content, and detail.
    public static var all: Self {
        Self(rawValue: 1)
    }

    /// Show the content column and detail area of a three-column navigation
    /// split view, or the sidebar column and detail area of a two-column
    /// navigation split view.
    ///
    /// For a two-column navigation split view, `doubleColumn` is equivalent
    /// to ``all``.
    public static var doubleColumn: Self {
        Self(rawValue: 2)
    }

    /// Hide the leading columns, showing only the detail area.
    ///
    /// For a two-column split view, this hides the sidebar.
    /// For a three-column split view, this hides both sidebar and content.
    public static var detailOnly: Self {
        Self(rawValue: 3)
    }
}

// MARK: - NavigationSplitViewColumn

/// A column in a navigation split view.
///
/// Use this type to identify which column should be displayed when the
/// navigation split view collapses or to programmatically control column
/// focus.
///
/// ## Example
///
/// ```swift
/// @State private var preferredColumn = NavigationSplitViewColumn.sidebar
///
/// NavigationSplitView(preferredCompactColumn: $preferredColumn) {
///     SidebarView()
/// } detail: {
///     DetailView()
/// }
/// ```
public struct NavigationSplitViewColumn: Equatable, Hashable, Sendable {
    /// The raw value identifying the column.
    private let rawValue: Int

    /// The sidebar column (leftmost).
    ///
    /// This is the first column in both two-column and three-column layouts.
    public static var sidebar: Self {
        Self(rawValue: 0)
    }

    /// The content column (middle).
    ///
    /// This column only exists in three-column layouts. In a two-column
    /// layout, use ``sidebar`` or ``detail``.
    public static var content: Self {
        Self(rawValue: 1)
    }

    /// The detail column (rightmost).
    ///
    /// This is the last column in both two-column and three-column layouts.
    public static var detail: Self {
        Self(rawValue: 2)
    }
}

// MARK: - NavigationSplitViewStyle

/// A type that specifies the appearance and interaction of navigation split
/// views within a view hierarchy.
///
/// To configure the navigation split view style for a view hierarchy, use the
/// ``View/navigationSplitViewStyle(_:)`` modifier.
///
/// ## Built-in Styles
///
/// - ``AutomaticNavigationSplitViewStyle``: Resolves based on context.
/// - ``BalancedNavigationSplitViewStyle``: Columns share space proportionally.
/// - ``ProminentDetailNavigationSplitViewStyle``: Detail gets more space.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/navigationSplitViewStyle(_:)`` puts the style into the
/// environment, and the render cache keeps memoized subtrees honest by comparing
/// each injected value with the one applied there last frame. A value it cannot
/// compare may have changed under a buffer it is about to serve with nothing
/// able to notice, so every memo below one declines to cache at all — and what
/// sits below this modifier is a whole split view, all of its columns.
///
/// All four built-in styles are therefore `Equatable`. This protocol is pure
/// data: it builds no view and has no `makeBody(configuration:)`, only the three
/// read-only requirements below, and ``NavigationSplitView`` consults nothing
/// else. None of the four holds anything either, so `==` within a type is
/// vacuously true, and two instances of one type really do size the columns
/// identically — there is no state for them to differ in, and the numbers they
/// answer with depend only on the type they share.
///
/// Equality is per-type, and that is load-bearing rather than incidental here.
/// ``SizeToFitFromLeftNavigationSplitViewStyle`` carries exactly
/// ``AutomaticNavigationSplitViewStyle``'s proportions and differs only in
/// ``sizesToFit``, which selects a different sizing algorithm outright. A
/// comparison written structurally across the protocol — matching the
/// proportions, or a shared `==` on an extension — would call those two equal
/// and let a split laid out one way be served where the other was asked for. The
/// per-type conformance cannot: the comparison downcasts to `Self` first, so two
/// different styles are never equal whatever they hold.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's navigation split view styles declare no such conformance,
///   and this is one of the places a terminal renderer has to differ. SwiftUI
///   diffs the view graph the compiler builds for it and never has to ask
///   whether an environment value changed; TUIkit re-runs `body` and compares
///   values, so here the question must be answerable.
public protocol NavigationSplitViewStyle: Sendable {
    /// The proportion of width allocated to the sidebar in a two-column layout.
    ///
    /// Value between 0 and 1. For example, 0.33 means sidebar gets 1/3 of width.
    var sidebarProportion: Double { get }

    /// The proportion of width allocated to each column in a three-column layout.
    ///
    /// Returns (sidebar, content, detail) proportions that sum to 1.0.
    var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) { get }

    /// When `true`, columns are sized to fit their content from the left rather
    /// than by proportion: a column whose content is naturally narrow (it hugs
    /// its width) is given just that width, and the width-flexible columns
    /// (Lists, filling VStacks) share what's left — the rightmost absorbing the
    /// remainder. Default `false` (proportional sizing).
    var sizesToFit: Bool { get }
}

extension NavigationSplitViewStyle {
    /// Proportional styles don't size to fit; ``SizeToFitFromLeftNavigationSplitViewStyle``
    /// overrides this.
    public var sizesToFit: Bool { false }
}

// MARK: - AutomaticNavigationSplitViewStyle

/// A navigation split style that resolves its appearance automatically based
/// on the current context.
///
/// In TUIkit this resolves to a sensible, detail-favoured default: the leading
/// column(s) take a modest share and the detail column gets the larger
/// remainder — wider than ``BalancedNavigationSplitViewStyle`` (which keeps the
/// columns comparable) but not as detail-dominant as
/// ``ProminentDetailNavigationSplitViewStyle``.
///
/// Use the ``NavigationSplitViewStyle/automatic`` static property to access
/// this style.
///
/// `Equatable` for the reason given under ``NavigationSplitViewStyle``: a memo
/// below a value the render cache cannot compare declines to cache.
public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates an automatic navigation split view style.
    public init() {}

    public var sidebarProportion: Double { 0.33 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.25, 0.25, 0.50)
    }
}

// MARK: - BalancedNavigationSplitViewStyle

/// A navigation split style that reduces the size of the detail content to
/// make room when showing the leading column or columns.
///
/// This style distributes space so the sidebar and detail are *comparable* in
/// width (the detail shrinks to make room for the leading columns), rather than
/// favouring the detail. The leading columns therefore take a larger share than
/// under ``AutomaticNavigationSplitViewStyle``.
///
/// Use the ``NavigationSplitViewStyle/balanced`` static property to access
/// this style.
///
/// `Equatable` on the same terms as ``AutomaticNavigationSplitViewStyle``.
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates a balanced navigation split view style.
    public init() {}

    public var sidebarProportion: Double { 0.42 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.30, 0.30, 0.40)
    }
}

// MARK: - ProminentDetailNavigationSplitViewStyle

/// A navigation split style that attempts to maintain the size of the detail
/// content when hiding or showing the leading columns.
///
/// This style gives more space to the detail column, making leading columns
/// narrower.
///
/// Use the ``NavigationSplitViewStyle/prominentDetail`` static property to
/// access this style.
///
/// `Equatable` on the same terms as ``AutomaticNavigationSplitViewStyle``.
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates a prominent detail navigation split view style.
    public init() {}

    public var sidebarProportion: Double { 0.22 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.18, 0.18, 0.64)
    }
}

// MARK: - SizeToFitFromLeftNavigationSplitViewStyle

/// A navigation split style that sizes columns to fit their content, biased to
/// the left, rather than by fixed proportion.
///
/// A column whose content is naturally narrow — it hugs its width, e.g. a
/// sidebar of short labels — is given just that width. The width-flexible
/// columns (Lists, filling VStacks) split the remaining space, with the
/// rightmost column absorbing the remainder. When the terminal is too narrow,
/// columns shrink and their content truncates, honouring each column's minimum.
///
/// Use the ``NavigationSplitViewStyle/sizeToFitFromLeft`` static property to
/// access this style.
///
/// `Equatable` on the same terms as ``AutomaticNavigationSplitViewStyle``, and
/// this is the one that earns the per-type comparison: its proportions are that
/// style's exactly, so only the type tells them apart — see
/// ``NavigationSplitViewStyle``.
public struct SizeToFitFromLeftNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates a size-to-fit-from-left navigation split view style.
    public init() {}

    public var sizesToFit: Bool { true }

    // Proportional fallbacks (used only if a caller reads them directly); the
    // real sizing is content-driven when `sizesToFit` is honoured.
    public var sidebarProportion: Double { 0.33 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.25, 0.25, 0.50)
    }
}

// MARK: - Style Static Properties

extension NavigationSplitViewStyle where Self == SizeToFitFromLeftNavigationSplitViewStyle {
    /// A navigation split style that sizes columns to fit their content from the
    /// left: naturally-narrow columns hug their width, flexible columns share
    /// the rest.
    public static var sizeToFitFromLeft: Self {
        Self()
    }
}

extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle {
    /// A navigation split style that resolves its appearance automatically
    /// based on the current context.
    public static var automatic: Self {
        Self()
    }
}

extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle {
    /// A navigation split style that reduces the size of the detail content
    /// to make room when showing the leading column or columns.
    public static var balanced: Self {
        Self()
    }
}

extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle {
    /// A navigation split style that attempts to maintain the size of the
    /// detail content when hiding or showing the leading columns.
    public static var prominentDetail: Self {
        Self()
    }
}

// MARK: - Environment Key

/// Environment key for the navigation split view style.
private struct NavigationSplitViewStyleKey: EnvironmentKey {
    static let defaultValue: any NavigationSplitViewStyle = AutomaticNavigationSplitViewStyle()
}

extension EnvironmentValues {
    /// The navigation split view style for this environment.
    ///
    /// The built-in styles are `Equatable` so that a memo below one can still
    /// store — see ``NavigationSplitViewStyle`` for why the render cache has to
    /// ask.
    public var navigationSplitViewStyle: any NavigationSplitViewStyle {
        get { self[NavigationSplitViewStyleKey.self] }
        set { self[NavigationSplitViewStyleKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Sets the style for navigation split views within this view.
    ///
    /// Use this modifier to specify how columns in a ``NavigationSplitView``
    /// should be sized and displayed.
    ///
    /// ```swift
    /// NavigationSplitView {
    ///     SidebarView()
    /// } detail: {
    ///     DetailView()
    /// }
    /// .navigationSplitViewStyle(.prominentDetail)
    /// ```
    ///
    /// ## Available Styles
    ///
    /// - ``AutomaticNavigationSplitViewStyle/automatic``: Resolves based on context.
    /// - ``BalancedNavigationSplitViewStyle/balanced``: Columns share space proportionally.
    /// - ``ProminentDetailNavigationSplitViewStyle/prominentDetail``: Detail gets more space.
    ///
    /// - Parameter style: The navigation split view style to apply.
    /// - Returns: A view with the specified navigation split view style.
    public func navigationSplitViewStyle<S: NavigationSplitViewStyle>(_ style: S) -> some View {
        environment(\.navigationSplitViewStyle, style)
    }
}
