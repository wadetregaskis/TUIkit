//  🖥️ TUIkit — Terminal UI Kit for Swift
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
///   use width up to its ideal (single-line) width — so the retired render-twice
///   "+8" probe saw the width grow when the proposal was *below* that ideal and
///   would wrongly call it flexible — but it never grows *past* the ideal, so it
///   does not fill arbitrary space. Flexibility means "fills unbounded available
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
/// For a `Layoutable` view, `sizeThatFits` is the **canonical** (and now sole)
/// source of this flag. `measureChild`'s fallback for the remaining
/// `Renderable`-only views reports **fixed** (a single render); a view that
/// fills its width must conform to `Layoutable` to advertise it. (The fallback
/// once guessed flexibility from a "+8" render probe, but that approximation
/// over-reported wrapping content and was retired — it was never the contract.)
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

    /// Whether this is the size the view *chose*, rather than one a budget
    /// imposed on it — the claim the per-pass measure memo needs to answer one
    /// query from another's measurement.
    ///
    /// A `sizeThatFits` may set this only when all three hold for the call that
    /// produced it, with the view value, its identity, the environment and
    /// `context.availableWidth` held fixed:
    ///
    /// 1. the answer is a function of `proposal.width ?? context.availableWidth`
    ///    — the same for a width that arrived as a proposal and one inherited
    ///    from the available extent (the value-preserving `??` idiom, not a
    ///    branch on `proposal.width == nil`);
    /// 2. no part of it read the vertical budget (`proposal.height`,
    ///    `context.availableHeight`, `context.hasExplicitHeight`), *except* a
    ///    top-level `min(natural, budget)` clamp that did not bite — a view that
    ///    clamps must test that at runtime and clear this when it did;
    /// 3. every child measurement it consumed reported this too. The flag is a
    ///    property of the *answer*, not of the type: the same view sets it under
    ///    one budget and clears it under another.
    ///
    /// The memo may then serve this size for any later query at the same
    /// identity, value, type, available width and effective width whose vertical
    /// budget is at least ``height`` — the one budget at which a clamp that did
    /// not bite here could not bite there either. Set inside the package only;
    /// a `Layout` written outside it reports `false` and is always re-measured,
    /// which is correct, just not saved.
    public private(set) var isNaturalSize: Bool = false

    /// Creates a view size with explicit flexibility flags.
    public init(width: Int, height: Int, isWidthFlexible: Bool = false, isHeightFlexible: Bool = false) {
        self.width = width
        self.height = height
        self.isWidthFlexible = isWidthFlexible
        self.isHeightFlexible = isHeightFlexible
    }

    /// This size, claiming (or disclaiming) ``isNaturalSize``.
    ///
    /// Written as a returned copy rather than a settable property so the claim
    /// is made where the size is returned, next to the reasoning that earns it.
    package func declaringNaturalSize(_ isNatural: Bool = true) -> Self {
        var copy = self
        copy.isNaturalSize = isNatural
        return copy
    }

    /// Two sizes are equal when they describe the same box with the same
    /// flexibility. ``isNaturalSize`` is deliberately *not* compared: it records
    /// what the measurement was allowed to depend on, not what it says, and two
    /// measurements that agree on the box agree — whatever budget each ran under.
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
            && lhs.isWidthFlexible == rhs.isWidthFlexible
            && lhs.isHeightFlexible == rhs.isHeightFlexible
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
