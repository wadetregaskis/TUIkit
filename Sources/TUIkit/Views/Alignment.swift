//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alignment.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Horizontal Alignment

/// Horizontal alignment for VStack and similar containers.
public enum HorizontalAlignment: Sendable {
    /// Align to the leading (left) edge.
    case leading

    /// Align to the center.
    case center

    /// Align to the trailing (right) edge.
    case trailing
}

extension HorizontalAlignment {
    /// The leading-edge (x) offset at which to place a `childWidth`-wide element
    /// inside a `totalWidth`-wide region so that it sits at this alignment.
    ///
    /// Returns 0 for `.leading`, the centred offset for `.center`, and the
    /// right-flush offset for `.trailing`. Shared by every container that places
    /// a child on the horizontal axis (ZStack, stack alignment).
    func childOffset(childWidth: Int, in totalWidth: Int) -> Int {
        switch self {
        case .leading: return 0
        case .center: return max(0, (totalWidth - childWidth) / 2)
        case .trailing: return max(0, totalWidth - childWidth)
        }
    }
}

// MARK: - Vertical Alignment

/// Vertical alignment for HStack and similar containers.
public enum VerticalAlignment: Sendable {
    /// Align to the top edge.
    case top

    /// Align to the vertical center.
    case center

    /// Align to the bottom edge.
    case bottom
}

extension VerticalAlignment {
    /// The top-edge (y) offset at which to place a `childHeight`-tall element
    /// inside a `totalHeight`-tall region so that it sits at this alignment.
    ///
    /// Returns 0 for `.top`, the centred offset for `.center`, and the
    /// bottom-flush offset for `.bottom`. Shared by every container that places
    /// a child on the vertical axis (ZStack, HStack row alignment).
    func childOffset(childHeight: Int, in totalHeight: Int) -> Int {
        switch self {
        case .top: return 0
        case .center: return max(0, (totalHeight - childHeight) / 2)
        case .bottom: return max(0, totalHeight - childHeight)
        }
    }
}

// MARK: - Combined Alignment

/// Combined alignment for both axes.
public struct Alignment: Sendable, Equatable {
    /// The horizontal component.
    public let horizontal: HorizontalAlignment

    /// The vertical component.
    public let vertical: VerticalAlignment

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
}
