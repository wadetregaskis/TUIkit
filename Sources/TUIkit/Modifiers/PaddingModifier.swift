//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PaddingModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Edge insets defining padding on each side.
public struct EdgeInsets: Sendable, Equatable {
    /// Padding above the content.
    public var top: Int

    /// Padding to the left of the content.
    public var leading: Int

    /// Padding below the content.
    public var bottom: Int

    /// Padding to the right of the content.
    public var trailing: Int

    /// Creates edge insets with individual values.
    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// Creates uniform edge insets.
    ///
    /// - Parameter value: The padding on all four sides.
    public init(all value: Int) {
        self.top = value
        self.leading = value
        self.bottom = value
        self.trailing = value
    }

    /// Creates horizontal and vertical edge insets.
    ///
    /// - Parameters:
    ///   - horizontal: The padding on leading and trailing sides.
    ///   - vertical: The padding on top and bottom sides.
    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.top = vertical
        self.leading = horizontal
        self.bottom = vertical
        self.trailing = horizontal
    }
}

/// An edge of a view.
///
/// Mirrors SwiftUI's `Edge`: the type itself is a single edge, and the
/// nested ``Edge/Set-swift.struct`` is an efficient set of edges.
public enum Edge: Int8, Sendable, CaseIterable {
    /// The top edge.
    case top

    /// The leading (left) edge.
    case leading

    /// The bottom edge.
    case bottom

    /// The trailing (right) edge.
    case trailing

    /// An efficient set of edges.
    public struct Set: OptionSet, Sendable {
        /// The raw bitmask value for this edge set.
        public let rawValue: UInt8

        /// Creates an edge set from a raw bitmask value.
        ///
        /// - Parameter rawValue: The bitmask value.
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// The top edge.
        public static let top = Self(rawValue: 1 << 0)

        /// The leading (left) edge.
        public static let leading = Self(rawValue: 1 << 1)

        /// The bottom edge.
        public static let bottom = Self(rawValue: 1 << 2)

        /// The trailing (right) edge.
        public static let trailing = Self(rawValue: 1 << 3)

        /// All four edges.
        public static let all: Set = [.top, .leading, .bottom, .trailing]

        /// The leading and trailing edges.
        public static let horizontal: Set = [.leading, .trailing]

        /// The top and bottom edges.
        public static let vertical: Set = [.top, .bottom]
    }
}

/// A modifier that adds padding around a view.
///
/// - Important: This is framework infrastructure. Use `.padding()` on any
///   ``View`` instead of instantiating this type directly.
public struct PaddingModifier: ViewModifier {
    /// The padding insets.
    let insets: EdgeInsets

    public func adjustContext(_ context: RenderContext) -> RenderContext {
        var adjusted = context
        adjusted.availableWidth = max(0, context.availableWidth - insets.leading - insets.trailing)
        adjusted.availableHeight = max(0, context.availableHeight - insets.top - insets.bottom)
        return adjusted
    }

    public func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        var result: [String] = []

        let leadingPad = String(repeating: " ", count: insets.leading)
        let trailingPad = String(repeating: " ", count: insets.trailing)

        // Calculate line width
        let lineWidth = buffer.width + insets.leading + insets.trailing
        let emptyLine = String(repeating: " ", count: lineWidth)

        // Top padding (full lines)
        for _ in 0..<insets.top {
            result.append(emptyLine)
        }

        // Content lines with horizontal padding
        for line in buffer.lines {
            result.append(leadingPad + line + trailingPad)
        }

        // Bottom padding (full lines)
        for _ in 0..<insets.bottom {
            result.append(emptyLine)
        }

        // Content shifted right by `leading` and down by `top`; carry any
        // overlay layers by the same amount so they stay anchored. The padded
        // width is exactly `lineWidth` (the widest input line is `buffer.width`,
        // and the empty pad lines are built to `lineWidth`), so pass it and skip
        // re-measuring every line — a hot recompute in deeply-nested layouts.
        return buffer.replacingLines(
            result, width: lineWidth, overlayShiftX: insets.leading, overlayShiftY: insets.top)
    }
}
