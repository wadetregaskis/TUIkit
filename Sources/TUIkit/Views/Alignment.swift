//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alignment.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Alignment ID

/// A type used to create custom alignment guides.
///
/// Conform a type to `AlignmentID` and use it to build a
/// ``HorizontalAlignment`` or ``VerticalAlignment``, exactly as in SwiftUI:
///
/// ```swift
/// private struct MenuBullet: AlignmentID {
///     static func defaultValue(in context: ViewDimensions) -> Double {
///         0  // the leading edge, unless a view overrides it
///     }
/// }
///
/// extension HorizontalAlignment {
///     static let menuBullet = HorizontalAlignment(MenuBullet.self)
/// }
/// ```
///
/// ## Why the guide is fractional when everything else is whole cells
///
/// Sizes and positions in TUIkit are `Int` — a terminal is a grid of cells and
/// there is no such thing as half of one. A *guide* is not a size: it is a
/// reference line **within** a view, and it is only ever subtracted from
/// another guide to produce a position, which is then floored to a cell.
///
/// That distinction is load-bearing rather than pedantic. Centring a
/// 3-cell view in a 10-cell space has always placed it at 3 —
/// `(10 - 3) / 2`. Whole-cell guides would compute `10/2 - 3/2 = 4`, because
/// flooring does not distribute over subtraction; **190 of 820** width
/// combinations would shift by one cell. Fractional guides give
/// `5.0 - 1.5 = 3.5`, floored to 3, and differ from today's arithmetic in
/// **none** of them.
///
/// So the fraction exists only between two guides and never survives to a
/// coordinate.
///
/// - Note: Refines `Sendable` because ``HorizontalAlignment`` and
///   ``VerticalAlignment`` store the conforming *metatype* and are themselves
///   `Sendable`; an existential metatype is only `Sendable` when its protocol
///   is. Costless in practice — an `AlignmentID` is a caseless enum or empty
///   struct, which is trivially `Sendable`.
public protocol AlignmentID: Sendable {
    /// The value of the corresponding guide when a view does not set it
    /// explicitly, measured from the view's leading or top edge.
    ///
    /// - Parameter context: The dimensions of the view being aligned.
    /// - Returns: The guide's position along its axis.
    static func defaultValue(in context: ViewDimensions) -> Double
}

// MARK: - View Dimensions

/// A view's size, and the position of its alignment guides.
///
/// The terminal counterpart of SwiftUI's `ViewDimensions`. ``width`` and
/// ``height`` are whole cells; guide values are fractional for the reason given
/// on ``AlignmentID``.
public struct ViewDimensions: Equatable, Sendable {
    /// The view's width in cells.
    public let width: Int

    /// The view's height in cells.
    public let height: Int

    /// Guides this view set explicitly with ``View/alignmentGuide(_:computeValue:)``.
    private let explicitGuides: [AlignmentKey: Double]

    init(width: Int, height: Int, explicitGuides: [AlignmentKey: Double] = [:]) {
        self.width = width
        self.height = height
        self.explicitGuides = explicitGuides
    }

    /// The position of a horizontal guide — the explicit value if the view set
    /// one, otherwise the guide's default.
    public subscript(guide: HorizontalAlignment) -> Double {
        explicitGuides[guide.key] ?? guide.id.defaultValue(in: self)
    }

    /// The position of a vertical guide — the explicit value if the view set
    /// one, otherwise the guide's default.
    public subscript(guide: VerticalAlignment) -> Double {
        explicitGuides[guide.key] ?? guide.id.defaultValue(in: self)
    }

    /// The explicitly set value of a horizontal guide, or `nil` if the view left
    /// it at its default.
    public subscript(explicit guide: HorizontalAlignment) -> Double? {
        explicitGuides[guide.key]
    }

    /// The explicitly set value of a vertical guide, or `nil` if the view left
    /// it at its default.
    public subscript(explicit guide: VerticalAlignment) -> Double? {
        explicitGuides[guide.key]
    }
}

/// Identifies one alignment guide, so guides compare and hash by the
/// `AlignmentID` that defines them.
public struct AlignmentKey: Hashable, Sendable {
    fileprivate let id: ObjectIdentifier

    fileprivate init(_ type: any AlignmentID.Type) {
        self.id = ObjectIdentifier(type)
    }
}

// MARK: - Horizontal Alignment

/// An alignment position along the horizontal axis.
public struct HorizontalAlignment: Equatable, Sendable {
    /// The type defining this guide's default position.
    let id: any AlignmentID.Type

    /// This guide's identity, for storing explicit values against.
    public let key: AlignmentKey

    /// Creates a horizontal alignment from a custom ``AlignmentID``.
    public init(_ id: any AlignmentID.Type) {
        self.id = id
        self.key = AlignmentKey(id)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
}

private enum LeadingID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

private enum HCenterID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { Double(context.width) / 2 }
}

private enum TrailingID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { Double(context.width) }
}

extension HorizontalAlignment {
    /// Aligned to the leading (left) edge.
    public static let leading = Self(LeadingID.self)

    /// Aligned to the horizontal centre.
    public static let center = Self(HCenterID.self)

    /// Aligned to the trailing (right) edge.
    public static let trailing = Self(TrailingID.self)
}

// MARK: - Vertical Alignment

/// An alignment position along the vertical axis.
public struct VerticalAlignment: Equatable, Sendable {
    /// The type defining this guide's default position.
    let id: any AlignmentID.Type

    /// This guide's identity, for storing explicit values against.
    public let key: AlignmentKey

    /// Creates a vertical alignment from a custom ``AlignmentID``.
    public init(_ id: any AlignmentID.Type) {
        self.id = id
        self.key = AlignmentKey(id)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
}

private enum TopID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

private enum VCenterID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { Double(context.height) / 2 }
}

private enum BottomID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { Double(context.height) }
}

private enum FirstTextBaselineID: AlignmentID {
    /// The first row of text. A terminal cell has no interior baseline, so the
    /// baseline of a line *is* that line.
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

private enum LastTextBaselineID: AlignmentID {
    /// The last row of text.
    static func defaultValue(in context: ViewDimensions) -> Double {
        Double(max(0, context.height - 1))
    }
}

extension VerticalAlignment {
    /// Aligned to the top edge.
    public static let top = Self(TopID.self)

    /// Aligned to the vertical centre.
    public static let center = Self(VCenterID.self)

    /// Aligned to the bottom edge.
    public static let bottom = Self(BottomID.self)

    /// Aligned to the first line of text.
    ///
    /// A terminal cell has no interior baseline, so a line's baseline is the
    /// line itself: this is the view's first row.
    public static let firstTextBaseline = Self(FirstTextBaselineID.self)

    /// Aligned to the last line of text — the view's last row.
    public static let lastTextBaseline = Self(LastTextBaselineID.self)
}

// MARK: - Placing a Child

extension HorizontalAlignment {
    /// The leading (x) offset at which to place a `childWidth`-wide element
    /// inside a `totalWidth`-wide region so that its guide meets the region's.
    ///
    /// Both guides are taken at their defaults, subtracted, and floored to a
    /// cell — see ``AlignmentID`` for why that last step is what preserves
    /// TUIkit's long-standing centring. Clamped so a child is never placed
    /// outside its region, which `.trailing` on an oversized child would
    /// otherwise do.
    func childOffset(childWidth: Int, in totalWidth: Int) -> Int {
        let region = ViewDimensions(width: totalWidth, height: 0)
        let child = ViewDimensions(width: childWidth, height: 0)
        let offset = Int((self[dimensions: region] - self[dimensions: child]).rounded(.down))
        return min(max(0, offset), max(0, totalWidth - childWidth))
    }

    /// This guide's position within the given dimensions.
    subscript(dimensions dimensions: ViewDimensions) -> Double {
        dimensions[self]
    }
}

extension VerticalAlignment {
    /// The top (y) offset at which to place a `childHeight`-tall element inside
    /// a `totalHeight`-tall region so that its guide meets the region's.
    ///
    /// The vertical twin of ``HorizontalAlignment/childOffset(childWidth:in:)``.
    func childOffset(childHeight: Int, in totalHeight: Int) -> Int {
        let region = ViewDimensions(width: 0, height: totalHeight)
        let child = ViewDimensions(width: 0, height: childHeight)
        let offset = Int((self[dimensions: region] - self[dimensions: child]).rounded(.down))
        return min(max(0, offset), max(0, totalHeight - childHeight))
    }

    /// This guide's position within the given dimensions.
    subscript(dimensions dimensions: ViewDimensions) -> Double {
        dimensions[self]
    }
}

// MARK: - Combined Alignment

/// Combined alignment for both axes.
public struct Alignment: Sendable, Equatable {
    /// The horizontal component.
    public var horizontal: HorizontalAlignment

    /// The vertical component.
    public var vertical: VerticalAlignment

    /// Creates a combined alignment.
    ///
    /// - Parameters:
    ///   - horizontal: The horizontal alignment.
    ///   - vertical: The vertical alignment.
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    // MARK: - Preset Alignments

    /// Top leading.
    public static let topLeading = Self(horizontal: .leading, vertical: .top)

    /// Top center.
    public static let top = Self(horizontal: .center, vertical: .top)

    /// Top trailing.
    public static let topTrailing = Self(horizontal: .trailing, vertical: .top)

    /// Center leading.
    public static let leading = Self(horizontal: .leading, vertical: .center)

    /// Center.
    public static let center = Self(horizontal: .center, vertical: .center)

    /// Center trailing.
    public static let trailing = Self(horizontal: .trailing, vertical: .center)

    /// Bottom leading.
    public static let bottomLeading = Self(horizontal: .leading, vertical: .bottom)

    /// Bottom center.
    public static let bottom = Self(horizontal: .center, vertical: .bottom)

    /// Bottom trailing.
    public static let bottomTrailing = Self(horizontal: .trailing, vertical: .bottom)

    // MARK: - Baseline presets

    // The nine above pair the edges with each other; these six pair them with
    // the two text baselines instead, which is what lines a label up with the
    // FIRST line of a paragraph beside it rather than with the paragraph's
    // box. They are ordinary combinations of alignments that already exist
    // (see ``VerticalAlignment/firstTextBaseline`` for what a baseline means
    // when a cell has no interior) — SwiftUI names them, so writing one must
    // not be a compile error.

    /// Leading edge, aligned to the first line of text.
    public static let leadingFirstTextBaseline =
        Self(horizontal: .leading, vertical: .firstTextBaseline)

    /// Horizontally centred, aligned to the first line of text.
    public static let centerFirstTextBaseline =
        Self(horizontal: .center, vertical: .firstTextBaseline)

    /// Trailing edge, aligned to the first line of text.
    public static let trailingFirstTextBaseline =
        Self(horizontal: .trailing, vertical: .firstTextBaseline)

    /// Leading edge, aligned to the last line of text.
    public static let leadingLastTextBaseline =
        Self(horizontal: .leading, vertical: .lastTextBaseline)

    /// Horizontally centred, aligned to the last line of text.
    public static let centerLastTextBaseline =
        Self(horizontal: .center, vertical: .lastTextBaseline)

    /// Trailing edge, aligned to the last line of text.
    public static let trailingLastTextBaseline =
        Self(horizontal: .trailing, vertical: .lastTextBaseline)
}

// MARK: - Text Alignment

/// How multiple lines of text align relative to each other within a text view.
///
/// Mirrors SwiftUI's `TextAlignment`. Applied with
/// ``View/multilineTextAlignment(_:)``, it controls only the *line-to-line*
/// alignment of wrapped (or explicitly multi-line) ``Text`` — where each line
/// sits within the text block's own width (the width of its longest line). A
/// single-line ``Text`` is unaffected; the block as a whole is still positioned
/// by its parent (a `.frame` alignment, a stack). The default is ``leading``.
public enum TextAlignment: Sendable, Hashable, CaseIterable {
    /// Lines are flush to the leading (left) edge; the right edge is ragged.
    case leading

    /// Lines are centred relative to the widest line; both edges are ragged.
    case center

    /// Lines are flush to the trailing (right) edge; the left edge is ragged.
    case trailing
}

extension TextAlignment {
    /// The leading (left) padding, in cells, to place a `lineWidth`-wide line
    /// inside a `blockWidth`-wide text block so it sits at this alignment. The
    /// trailing padding is `blockWidth - lineWidth - leadingPad`.
    func leadingPad(lineWidth: Int, blockWidth: Int) -> Int {
        let slack = max(0, blockWidth - lineWidth)
        switch self {
        case .leading: return 0
        case .center: return slack / 2
        case .trailing: return slack
        }
    }
}
