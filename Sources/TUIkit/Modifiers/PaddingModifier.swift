//  🖥️ TUIkit — Terminal UI Kit for Swift
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

        /// Creates a set containing the one edge given.
        ///
        /// SwiftUI's `Edge.Set(_:)`, and the reason to have it is that generic
        /// code holding an `Edge` has no other way to reach the set: the
        /// statics below are spelled the same but are a different type, so
        /// `Edge.Set(edge)` is what any `for edge in Edge.allCases` loop needs.
        ///
        /// - Parameter edge: The edge the set contains.
        public init(_ edge: Edge) {
            switch edge {
            case .top: self = .top
            case .leading: self = .leading
            case .bottom: self = .bottom
            case .trailing: self = .trailing
            }
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
    ///
    /// A `var` so an animation can substitute it — see the `Animatable`
    /// conformance below.
    var insets: EdgeInsets

    public func adjustContext(_ context: RenderContext) -> RenderContext {
        var adjusted = context
        // Padding never takes the LAST cell from its content. Where there is
        // room for anything at all, the content keeps at least one cell of it
        // and the padding is what overflows — decoration losing to the thing it
        // decorates, which is the only order that degrades legibly.
        //
        // Clamped flat at zero, a `.padding(1).border()` in three rows offered
        // its text -1 lines, which became 0, which rendered nothing, which
        // collapsed the box to an empty 6×3 frame — the width gone too, because
        // a view with no content has no width to report. A height constraint
        // must not decide a width.
        adjusted.availableWidth = Self.remaining(
            context.availableWidth, less: insets.leading + insets.trailing)
        adjusted.availableHeight = Self.remaining(
            context.availableHeight, less: insets.top + insets.bottom)
        return adjusted
    }

    /// `available` less `taken`, but never below one cell while `available` has
    /// one to give.
    private static func remaining(_ available: Int, less taken: Int) -> Int {
        available <= 0 ? 0 : max(1, available - taken)
    }

    public func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        var result: [String] = []
        result.reserveCapacity(insets.top + buffer.lines.count + insets.bottom)

        let leadingCount = insets.leading
        let trailingCount = insets.trailing

        // Calculate line width
        let lineWidth = buffer.width + insets.leading + insets.trailing
        // The full-width blank pad rows are all identical, so build one and reuse
        // its value for every top/bottom row (cheaper than re-slicing per row).
        let emptyLine = String(asciiSpaces(lineWidth))

        // Top padding (full lines)
        for _ in 0..<insets.top {
            result.append(emptyLine)
        }

        // Content lines with horizontal padding. Each padded line is built in
        // place — reserve once, then append the leading spaces, the line, and the
        // trailing spaces as borrowed runs — byte-identical to
        // `leadingPad + line + trailingPad` without the `+`-chain intermediates.
        for line in buffer.lines {
            var padded = ""
            padded.reserveCapacity(line.utf8.count + leadingCount + trailingCount)
            if leadingCount > 0 { padded += asciiSpaces(leadingCount) }
            padded += line
            if trailingCount > 0 { padded += asciiSpaces(trailingCount) }
            result.append(padded)
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
        //
        // The output is uniform-width exactly when the input is: each content
        // line becomes `leading + line + trailing`, so equal-width input lines
        // give equal-width output lines (all `lineWidth`, matching the pad rows).
        // Propagating this lets an enclosing border skip re-measuring in turn.
        return buffer.replacingLines(
            result, width: lineWidth, uniformWidth: buffer.linesAreUniformWidth,
            overlayShiftX: insets.leading, overlayShiftY: insets.top)
    }
}

// MARK: - Animating padding

extension PaddingModifier: Animatable {
    /// The insets are what moves, so a change to them inside
    /// ``withAnimation(_:_:)`` opens or closes the gap rather than jumping it.
    ///
    /// Padding is a *layout* change, so this is the expensive shape: the
    /// subtree is re-measured and re-laid-out on every frame of the animation.
    /// Bounded by the animation's duration, and not something to put on
    /// ``Animation/repeatForever(autoreverses:)``.
    public var animatableData: EdgeInsets.AnimatableData {
        get { insets.animatableData }
        set { insets.animatableData = newValue }
    }
}
