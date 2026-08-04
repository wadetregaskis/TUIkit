//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NaturalExtent.swift
//
//  Measuring how big a view WANTS to be, with no ceiling.
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

        // `>=`, not `==`: a view that over-reports has already told us its true
        // extent and one more (redundant) rung will confirm it, whereas a view
        // that reports the budget exactly may have been cut off at it.
        guard extent >= budget, !fills, budget <= Int.max / growthFactor else { return size }
        budget *= growthFactor
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
