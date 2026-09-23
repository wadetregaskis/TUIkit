//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NaturalExtent.swift
//
//  Measuring how big a view WANTS to be, with no ceiling.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Why this exists
//
// A view's measure is clamped to the space it is offered. Every stack ends its
// `sizeThatFits` with `min(total, proposal.height ?? context.availableHeight)`,
// and every view that measures by rendering (`measureFixedByRendering` — Button,
// Form, Section, Menu, …) reports the height of a buffer built inside
// `availableHeight`. That clamp is right for layout: over-reporting would make a
// parent reserve room that does not exist.
//
// It is wrong for the handful of callers that need the opposite answer — "how
// tall would you be if nothing stopped you?" A ScrollView sizes its scrollable
// extent from it; a dialog decides whether it needs to scroll at all; a pop-up
// menu decides whether it overflows its cap. Those callers used to fake it by
// offering a fixed, enormous budget (`max(viewport * 64, 4096)`), which does not
// remove the clamp — it just moves it somewhere the author hoped no content
// would reach. Content taller than the budget measured EXACTLY the budget, and a
// ScrollView silently stopped 4,096 lines in: the rows past it existed, rendered
// nowhere, and could not be scrolled to.
//
// The fix is to stop guessing. Offer a budget, and if the content comes back
// filling it exactly — the signature of a clamp, not of a natural size — offer a
// bigger one and ask again. The ladder ends when the content reports a size it
// chose rather than one it was given, so no fixed number bounds the answer.

/// Measures `view`'s natural extent along `axis` against a budget that GROWS
/// until the content stops filling it, so no constant caps the result.
///
/// Two answers end the ladder:
///
/// - **The content came back smaller than the budget.** It reported a size it
///   chose, so the budget never bound it. Done.
/// - **The content came back flexible along `axis`.** A view that fills whatever
///   it is offered (`.frame(maxHeight: .infinity)`, a `List`, a nested
///   `ScrollView`) will report every budget it is ever given, so growing the
///   budget only inflates the answer — it never converges. Its natural extent
///   *is* what it was offered, and the caller's own viewport is the honest
///   value; `ViewSize.isHeightFlexible` / `isWidthFlexible` is how such a view
///   says so. (A `Spacer` needs no special case: it already collapses to its
///   minimum under an unspecified proposal, so it comes back under budget.)
///
/// Otherwise the content is *saturated* — it wanted at least the budget and may
/// want more — and the budget grows by ``growthFactor``.
///
/// - Note: There is no ceiling and no round limit beyond the guard that keeps
///   the budget from overflowing `Int`. What bounds tall content now is memory:
///   an eager `VStack` of a million rows measures honestly and then renders a
///   million-line buffer every frame. `LazyVStack` is the answer to that — it
///   reports its extent analytically and renders only the visible band — but
///   that is a cost the app author can now see and choose, rather than a silent
///   truncation the framework imposed.
///
/// - Parameters:
///   - view: The view to measure.
///   - axis: The axis whose extent is wanted; the other axis is left as the
///     context has it.
///   - proposal: The proposal to measure under. Its `axis` component should be
///     `nil` — a specified extent is the caller declaring a bound, which is
///     exactly what this function exists to avoid.
///   - context: The measuring context. Its `availableWidth`/`availableHeight`
///     along `axis` is replaced by each rung of the ladder.
///   - startingBudget: The first rung. Sized so ordinary content resolves in a
///     single measure; content taller than it costs one extra measure per
///     ``growthFactor``.
@MainActor
func measureNaturalExtent<V: View>(
    _ view: V,
    along axis: Axis,
    proposal: ProposedSize,
    context: RenderContext,
    startingBudget: Int
) -> ViewSize {
    /// How much bigger each rung of the ladder is than the last. Every doubling
    /// costs one more full measure of the content, and the resolved budget can
    /// overshoot the true extent by up to this factor — a budget nothing fills
    /// is harmless to measure against but not free, so this trades rounds
    /// against overshoot rather than maximising either.
    let growthFactor = 8

    // The horizontal ladder is the ideal-width ask, and says so; the vertical
    // one is not, and clears the mark an enclosing horizontal probe may have
    // set, since its content's height is its own question. See
    // ``RenderContext/asksIdealWidth``.
    let context = context.askingIdealWidth(axis == .horizontal)

    func measure(at budget: Int) -> ViewSize {
        var probe = context
        switch axis {
        case .vertical: probe.availableHeight = budget
        case .horizontal: probe.availableWidth = budget
        }
        return measureChild(view, proposal: proposal, context: probe)
    }

    var budget = max(1, startingBudget)
    while true {
        let size = measure(at: budget)
        let extent = axis == .vertical ? size.height : size.width
        let fills = axis == .vertical ? size.isHeightFlexible : size.isWidthFlexible

        // `>=`, not `==`: a report that lands exactly on the budget is what a
        // clamp looks like, and a report above it can still be a clamped subtree
        // plus a border's two rows, so neither is proof the content is done.
        guard extent >= budget, !fills else { return size }

        // How far to step. A report ABOVE the budget came from something that
        // declined to clamp — a wrapping `Text`, a stack reporting its true total
        // — and is therefore a real lower bound on the answer, so clearing it
        // settles the question next rung. A report EQUAL to the budget carries no
        // information whatsoever (that is precisely what being cut off looks
        // like), and there the step has nothing to go on but geometry.
        let informed = extent > budget && extent < Int.max ? extent + 1 : 0
        let geometric = budget <= Int.max / growthFactor ? budget * growthFactor : 0
        let next = max(informed, geometric)
        guard next > budget else { return size }  // no headroom left in `Int`
        budget = next
    }
}

/// The first rung of the ladder for content being offered `extent` cells of
/// visible space.
///
/// Generous on purpose: everything that fits resolves in one measure, which is
/// what the old fixed budget bought and what the ladder must not give up. It is
/// no longer a ceiling — content taller than this now grows past it instead of
/// being cut off at it.
@MainActor
func naturalExtentStartingBudget(forVisible extent: Int) -> Int {
    max(extent * 64, 4096)
}

/// Whether `budget` cells along an axis came from the ladder above rather than
/// from anything real.
///
/// The floor is the ladder's own: `naturalExtentStartingBudget` never offers
/// less than 4,096, and nothing that is actually bounding a view offers that
/// much — a terminal is tens of lines tall, and a container that means to
/// constrain a child says so in the PROPOSAL. So a subtree handed at least this
/// much, with no proposal along the axis, is being asked "how big would you be
/// if nothing stopped you" and may answer for all of itself rather than for the
/// prefix a budget reaches.
///
/// A predicate rather than a comparison at each call site because the constant
/// is the ladder's, and the two must not drift: a windowed stack that decided
/// "unbounded" at a different number than the ladder offers would answer the
/// prefix question to the natural-size ask, which is the bug
/// `ScrollTwoAxisWindowTests` pins.
///
/// HALF the floor, not the floor itself, because what arrives is the floor
/// minus whatever sits between the probe and the view: a `.padding(.horizontal)`
/// or a border takes its cells off the budget before the stack sees it. At the
/// floor exactly, a two-cell inset turned 4,096 into 4,094 — a real terminal's
/// width, by this test — and a padded stack in a pane up to 64 columns wide
/// stopped answering for its rows out of sight. Half the floor is still two
/// thousand cells, which no terminal is.
@MainActor
func isNaturalExtentBudget(_ budget: Int) -> Bool {
    budget >= naturalExtentStartingBudget(forVisible: 0) / 2
}

// MARK: - Which question a width ask is

/// What a windowed stack is being asked for its width, decided once from
/// explicit marks rather than from how big the offer happens to be.
enum ContentWidthAsk {
    /// The ordinary layout question — how wide are the rows this height
    /// budget reaches — answered from those rows.
    case prefix
    /// How wide are ALL the rows, answered from the kept record if there is
    /// one, and never by walking: a render, or a probe under a real bound.
    case serve
    /// The horizontal natural-extent probe itself: how wide are all the rows,
    /// and it may pay to walk them and keep the answer.
    case probe
}

private struct AsksWholeContentWidthKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this subtree is laid out on a horizontally unbounded canvas —
    /// the content of a `ScrollView` that scrolls horizontally — so a windowed
    /// stack's width means ALL its rows, at the probe and at render alike.
    /// Without it a sibling of the stack would be placed by the rows on screen
    /// while the canvas was sized by every row. Set by the scroll view for its
    /// content, and to `false` by one that does not scroll horizontally, since
    /// its content's width is its own viewport's question.
    var asksWholeContentWidth: Bool {
        get { self[AsksWholeContentWidthKey.self] }
        set { self[AsksWholeContentWidthKey.self] = newValue }
    }
}

extension RenderContext {
    /// Which question a windowed stack's width ask is — the one classifier,
    /// so the arms that answer it cannot disagree about it.
    ///
    /// Recognised by MARKS, not by the size of the offer. It used to be the
    /// size — at least half the ladder's floor with no proposal meant "the
    /// probe" — and an ordinary `.unspecified` layout ask inside content over
    /// two thousand cells on both axes met that test at render, walked every
    /// row, and filed the widths it found there. The size survives only as a
    /// BOUND DETECTOR: a probe that reaches the stack under a real width or
    /// height bound is not asking for its natural width, so it may read the
    /// kept answer but must not walk and file one.
    ///
    /// - Parameters:
    ///   - proposal: The stack's proposal.
    ///   - widthLimit: `proposal.width ?? availableWidth`.
    ///   - heightLimit: `proposal.height ?? availableHeight`.
    @MainActor
    func contentWidthAsk(proposal: ProposedSize, widthLimit: Int, heightLimit: Int)
        -> ContentWidthAsk
    {
        guard proposal.height == nil else { return .prefix }
        if asksIdealWidth {
            return proposal.width == nil && isNaturalExtentBudget(widthLimit)
                && isNaturalExtentBudget(heightLimit) ? .probe : .serve
        }
        return environment.asksWholeContentWidth ? .serve : .prefix
    }
}
