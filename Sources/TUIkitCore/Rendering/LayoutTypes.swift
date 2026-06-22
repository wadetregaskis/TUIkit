//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutTypes.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Layout Types

/// How much space a parent proposes to a child view.
///
/// Similar to SwiftUI's `ProposedViewSize`. The parent suggests dimensions,
/// and the child can accept, ignore, or partially use them.
///
/// - `nil` means "use your ideal size" (no constraint)
/// - A specific value means "try to fit in this space"
public struct ProposedSize: Equatable, Sendable {
    /// The proposed width in characters, or nil for ideal width.
    public var width: Int?

    /// The proposed height in lines, or nil for ideal height.
    public var height: Int?

    /// No constraints - view should use its ideal size.
    public static let unspecified = Self(width: nil, height: nil)

    /// Creates a proposed size with specific dimensions.
    public init(width: Int?, height: Int?) {
        self.width = width
        self.height = height
    }

    /// Creates a proposed size with fixed dimensions.
    public static func fixed(_ width: Int, _ height: Int) -> Self {
        Self(width: width, height: height)
    }
}

/// The size a view needs and whether it can flex.
///
/// Views return this from `sizeThatFits` to communicate their space requirements.
///
/// ## Flexibility contract
///
/// An axis is **flexible** iff, when offered more space than the view's ideal
/// along that axis, the view's *rendered output fills the offered extent*. The
/// reported `width`/`height` is then a **minimum**. Examples: `Spacer`,
/// `.frame(maxWidth: .infinity)`, `List` (fills its column).
///
/// An axis is **fixed** iff the view renders at a specific size and does *not*
/// grow past its ideal when offered more. The reported `width`/`height` is then
/// **exactly** what it renders.
///
/// - Important: A *wrapping* `Text` is **fixed**, not flexible. It reflows to
///   use width up to its ideal (single-line) width — so a render-twice "+8"
///   probe sees the width grow when the proposal is *below* that ideal and may
///   wrongly call it flexible — but it never grows *past* the ideal, so it does
///   not fill arbitrary space. Flexibility means "fills unbounded available
///   space", not "reflows within it".
///
/// - Important: A few views — `ViewThatFits` above all — are **available-width
///   dependent**: their reported (and rendered) size is a function of the
///   *available* extent, not the proposal alone, because they switch which
///   candidate they present as the space changes. They still honour the contract
///   (measured == rendered *at a given width*), but their size is not constant
///   across widths the way an ordinary fixed view's is. A parent must therefore
///   measure and render such a child at the **same** available width; measuring
///   at one width and rendering at another can land on different candidates and
///   mis-size it.
///
/// This yields the invariant the measure/render equivalence harness asserts, for
/// available extent `E`:
/// - flexible axis ⟹ `rendered == E` (it fills) and `reported ≤ E` (a minimum);
/// - fixed axis ⟹ `rendered == reported` (exact).
///
/// For a `Layoutable` view, `sizeThatFits` is the **canonical** source of this
/// flag. The `measureChild` render-to-measure fallback (for `Renderable`-only
/// views) derives it from a "+8" probe, an approximation that can over-report
/// flexibility for wrapping content; that heuristic is *not* the contract.
public struct ViewSize: Equatable, Sendable {
    /// The width this view needs — a *minimum* when ``isWidthFlexible``, else exact.
    public var width: Int

    /// The height this view needs — a *minimum* when ``isHeightFlexible``, else exact.
    public var height: Int

    /// Whether this view fills extra horizontal space past its ideal (see the
    /// flexibility contract on ``ViewSize``). `true` ⟹ ``width`` is a minimum.
    public var isWidthFlexible: Bool

    /// Whether this view fills extra vertical space past its ideal (see the
    /// flexibility contract on ``ViewSize``). `true` ⟹ ``height`` is a minimum.
    public var isHeightFlexible: Bool

    /// Creates a view size with explicit flexibility flags.
    public init(width: Int, height: Int, isWidthFlexible: Bool = false, isHeightFlexible: Bool = false) {
        self.width = width
        self.height = height
        self.isWidthFlexible = isWidthFlexible
        self.isHeightFlexible = isHeightFlexible
    }

    /// Creates a fixed-size view that doesn't expand.
    public static func fixed(_ width: Int, _ height: Int) -> Self {
        Self(width: width, height: height, isWidthFlexible: false, isHeightFlexible: false)
    }

    /// Creates a flexible view that expands to fill available space.
    public static func flexible(minWidth: Int = 0, minHeight: Int = 0) -> Self {
        Self(width: minWidth, height: minHeight, isWidthFlexible: true, isHeightFlexible: true)
    }

    /// Creates a view that is flexible only horizontally.
    public static func flexibleWidth(minWidth: Int = 0, height: Int) -> Self {
        Self(width: minWidth, height: height, isWidthFlexible: true, isHeightFlexible: false)
    }

    /// Creates a view that is flexible only vertically.
    public static func flexibleHeight(width: Int, minHeight: Int = 0) -> Self {
        Self(width: width, height: minHeight, isWidthFlexible: false, isHeightFlexible: true)
    }
}
