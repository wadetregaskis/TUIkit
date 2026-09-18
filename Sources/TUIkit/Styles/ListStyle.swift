//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A style that customizes the appearance of lists.
///
/// List styles control how lists render: whether the list draws a border, the
/// padding around its rows, and whether rows alternate backgrounds. TUIkit
/// provides two built-in styles that match SwiftUI's behavior:
/// - ``PlainListStyle``: Minimal appearance with no borders or background
/// - ``InsetGroupedListStyle``: Bordered container with inset padding
///
/// # Usage
///
/// ```swift
/// List {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// .listStyle(.plain)
///
/// List {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// .listStyle(.insetGrouped)
/// ```
///
/// ## Styles and the render cache
///
/// ``View/listStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all.
///
/// Both built-in styles are therefore `Equatable`. Without that, a single
/// `.listStyle(...)` turned the cache off for the whole list below it — every
/// row of it, and the list's own hug-width measurement with them. Neither style
/// holds anything, and all three of what a style says about a list are literal
/// constants on both, so the conformance is a formality here: every instance of
/// one styles a list identically. A custom style need not conform: one that does
/// not simply turns memoization off below itself, which costs render time rather
/// than correctness.
///
/// - Note: SwiftUI's list styles declare no such conformance, and this is one of
///   the places a terminal renderer has to differ. SwiftUI diffs the view graph
///   the compiler builds for it and never has to ask whether an environment
///   value changed; TUIkit re-runs `body` and compares values, so here the
///   question must be answerable.
public protocol ListStyle: Sendable {
    /// Whether the list should display borders around the container.
    var showsBorder: Bool { get }

    /// The padding applied to list rows.
    var rowPadding: EdgeInsets { get }

    /// Whether rows alternate backgrounds.
    ///
    /// The style says *whether*, and the palette says *which*: when this is
    /// true, `_ListCore` tints every even-indexed row within a section with
    /// the palette's accent at low opacity and leaves the odd rows untinted,
    /// so an app's theme keeps control of the colour. The index belongs to
    /// the row, not to where it happens to be drawn: it counts from the
    /// section's first row however far the list has scrolled, so the stripes
    /// stay on their rows. A focused or selected row keeps its own highlight
    /// either way. Both built-in styles return
    /// false, so this is a hook for a conforming style rather than something
    /// TUIkit's own styles turn on.
    var alternatingRowColors: Bool { get }
}

// MARK: - Plain List Style

/// A list style that uses minimal visual styling with no borders or backgrounds.
///
/// PlainListStyle renders lists with no border, no padding insets,
/// and no row background colors. This matches SwiftUI's `.listStyle(.plain)`.
///
/// # Rendering
/// - Rows display full width without padding
/// - No border around the list
/// - No row separators or backgrounds
/// - Content takes full available space
///
/// `Equatable` for the reason given under ``ListStyle``: a memo below a value
/// the render cache cannot compare declines to cache. It holds nothing, and its
/// three answers are literal constants, so every instance styles a list
/// identically.
public struct PlainListStyle: ListStyle, Equatable {
    /// Creates a plain list style.
    public init() {}

    public var showsBorder: Bool {
        false
    }

    public var rowPadding: EdgeInsets {
        EdgeInsets(all: 0)
    }

    public var alternatingRowColors: Bool {
        false
    }
}

// MARK: - Inset Grouped List Style

/// A list style that uses borders and inset padding.
///
/// InsetGroupedListStyle renders lists with a border and inset padding. This
/// matches SwiftUI's `.listStyle(.insetGrouped)`.
///
/// # Rendering
/// - Rows have inset padding (1 character on each side)
/// - Border surrounds the entire list
/// - No alternating row backgrounds: ``alternatingRowColors`` is false, so a
///   row's background comes from focus and selection alone
///
/// `Equatable` on the same terms as ``PlainListStyle``, and a list spelling
/// `.listStyle(.insetGrouped)` explicitly needs it as much: the default value of
/// the environment key is an instance of this type, but a default is only read
/// out of the environment, never injected into it, so it is the explicit
/// modifier that the cache has to be able to compare.
public struct InsetGroupedListStyle: ListStyle, Equatable {
    /// Creates an inset grouped list style.
    public init() {}

    public var showsBorder: Bool {
        true
    }

    public var rowPadding: EdgeInsets {
        // No container padding - row backgrounds need to extend to the borders.
        // Row padding is handled in List's renderRow() method.
        EdgeInsets(all: 0)
    }

    public var alternatingRowColors: Bool {
        false
    }
}

// MARK: - List Style Convenience

extension ListStyle where Self == PlainListStyle {
    /// The plain list style with no borders or backgrounds.
    ///
    /// Usable with leading-dot syntax: `.listStyle(.plain)`.
    public static var plain: PlainListStyle {
        PlainListStyle()
    }
}

extension ListStyle where Self == InsetGroupedListStyle {
    /// The inset grouped list style: a bordered, inset container.
    ///
    /// Usable with leading-dot syntax: `.listStyle(.insetGrouped)`.
    public static var insetGrouped: InsetGroupedListStyle {
        InsetGroupedListStyle()
    }
}
