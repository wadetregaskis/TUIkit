//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UserResizable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Axes

/// Which directions a view may be resized in by the person using the app.
public struct ResizableAxes: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Width, dragged from the view's right edge.
    public static let horizontal = Self(rawValue: 1 << 0)

    /// Height, dragged from the view's bottom edge.
    public static let vertical = Self(rawValue: 1 << 1)

    /// Both.
    public static let all: Self = [.horizontal, .vertical]
}

// MARK: - Bounds

/// How large a user may make a view on one axis.
///
/// Built from any Swift range over `Int`, which is what makes "no maximum" and
/// "no minimum" spellable without an extra vocabulary: `20...80` is both ends,
/// `20...` is a floor with no ceiling, `...80` a ceiling with no floor.
public struct ResizeBounds: Sendable, Equatable {
    /// The smallest the view may be. Never below 1 — a zero-cell view cannot be
    /// grabbed to make it larger again, which would be a one-way door.
    public let minimum: Int

    /// The largest the view may be, or `nil` for no limit beyond what the
    /// layout offers.
    public let maximum: Int?

    /// Anything from one cell up.
    public static let unbounded = Self(minimum: 1, maximum: nil)

    init(minimum: Int, maximum: Int?) {
        let floor = max(1, minimum)
        self.minimum = floor
        // A maximum below the minimum is a caller's mistake, not a range to
        // honour; the minimum wins, because a view too small to grab is the
        // worse failure.
        self.maximum = maximum.map { max(floor, $0) }
    }

    /// Reads a range's ends, whichever kind of range it is.
    ///
    /// `relative(to:)` is the standard library's own way of asking a partial
    /// range for concrete bounds, so `20...`, `...80`, `20...80` and `20..<81`
    /// all arrive here already normalised — no per-range-type overloads, and no
    /// sentinel values invented to mean "open".
    public init<R: RangeExpression>(_ range: R) where R.Bound == Int {
        let concrete = range.relative(to: 0..<Int.max)
        self.init(
            minimum: concrete.lowerBound,
            // A half-open range's upper bound is exclusive, and an open-ended
            // one lands on `Int.max` — which is not a maximum, it is the
            // absence of one.
            maximum: concrete.upperBound == Int.max ? nil : concrete.upperBound - 1
        )
    }

    /// `value`, brought inside these bounds.
    public func clamping(_ value: Int) -> Int {
        if let maximum { return min(maximum, max(minimum, value)) }
        return max(minimum, value)
    }
}

// MARK: - Modifier

extension View {

    /// Lets the person using the app resize this view, by dragging its bottom
    /// or right edge or with the arrow keys once it is focused.
    ///
    /// ## Naming an axis is what makes it resizable
    ///
    /// One rule covers every spelling: an axis the call names can be resized,
    /// and one it does not name cannot. `axes` names axes; the `width:` and
    /// `height:` overloads name an axis *and* bound it.
    ///
    /// ```swift
    /// content.userResizable()                            // both, unbounded
    /// content.userResizable(.horizontal)                 // width only
    /// content.userResizable(width: 20...80)              // width only, bounded
    /// content.userResizable(width: 20..., height: 5...30)// both; width has no ceiling
    /// ```
    ///
    /// Nothing contradictory is spellable — there is no overload that takes an
    /// axis set *and* a range, because `.userResizable(.vertical, width: 20...80)`
    /// has no honest meaning.
    ///
    /// ## What a resize is, and is not
    ///
    /// It is **intent, not law.** The layout still clamps: a terminal narrower
    /// than the size the user chose wins, and does so without destroying that
    /// size — widen the terminal again and the view returns to it. Bounds
    /// narrow what the user may ask for; they do not force the layout to
    /// provide it.
    ///
    /// The size lives as long as the view's identity does. Give the view a
    /// ``View/focusID(_:)`` to make it outlive a relayout that would otherwise
    /// change that identity.
    ///
    /// ## Reaching it
    ///
    /// The view takes a place in the Tab order. Focused, ←/→ and ↑/↓ resize by
    /// one cell (Shift by five), Home and End go to the smallest and largest
    /// allowed, and Escape returns the view to the size the layout wanted.
    ///
    /// With a mouse, the whole of the bottom edge and the right edge is a drag
    /// target — the mark is one cell in the corner, because a terminal cannot
    /// change the pointer's shape to say "you may drag here", but the target it
    /// stands for is the full run of both edges.
    ///
    /// - Parameter axes: Which directions may be resized. Defaults to both.
    public func userResizable(_ axes: ResizableAxes = .all) -> some View {
        _UserResizableCore(
            content: self, axes: axes,
            widthBounds: .unbounded, heightBounds: .unbounded)
    }

    /// Lets the user resize this view's WIDTH, within `width`.
    ///
    /// See ``View/userResizable(_:)``. Naming the axis is what makes it
    /// resizable, so this view's height stays the layout's business.
    public func userResizable<W: RangeExpression>(width: W) -> some View where W.Bound == Int {
        _UserResizableCore(
            content: self, axes: .horizontal,
            widthBounds: ResizeBounds(width), heightBounds: .unbounded)
    }

    /// Lets the user resize this view's HEIGHT, within `height`.
    ///
    /// See ``View/userResizable(_:)``.
    public func userResizable<H: RangeExpression>(height: H) -> some View where H.Bound == Int {
        _UserResizableCore(
            content: self, axes: .vertical,
            widthBounds: .unbounded, heightBounds: ResizeBounds(height))
    }

    /// Lets the user resize this view in both directions, each within its own
    /// range.
    ///
    /// See ``View/userResizable(_:)``. Either range may be open at one end, so
    /// "resizable both ways, but only the width has a ceiling" is
    /// `width: 20...80, height: 5...`.
    public func userResizable<W: RangeExpression, H: RangeExpression>(
        width: W, height: H
    ) -> some View where W.Bound == Int, H.Bound == Int {
        _UserResizableCore(
            content: self, axes: .all,
            widthBounds: ResizeBounds(width), heightBounds: ResizeBounds(height))
    }
}
