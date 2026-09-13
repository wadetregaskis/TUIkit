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
public struct PlainListStyle: ListStyle {
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
public struct InsetGroupedListStyle: ListStyle {
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
