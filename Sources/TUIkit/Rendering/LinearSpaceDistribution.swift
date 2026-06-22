//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LinearSpaceDistribution.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Linear Space Distribution

/// Distributes `available` cells across a row or column of children.
///
/// Shared by ``HStack`` (width) and ``VStack`` (height). The algorithm:
///
/// - **Everything fits** — fixed children keep their natural size and
///   flexible children absorb the surplus.
/// - **Space is short** — flexible children are shrunk first.
/// - **Even the fixed content overflows** — flexible children collapse to
///   zero and fixed children are placed in order (leftmost / topmost first)
///   until the space runs out, so the leading content stays visible and the
///   rest is clipped.
///
/// `spacing` is charged only *between children that are actually placed*. This
/// is the difference between clipping gracefully and going blank: reserving a
/// gap for every child up front means a stack with more gaps than fit (e.g. a
/// `VStack(spacing: 1)` of a dozen rows in a pane only a few rows tall) would
/// have **no** budget left for content and collapse every child to zero —
/// rendering nothing. Charging spacing per placed child instead shows the
/// children that fit and clips the rest, the way SwiftUI does.
///
/// The placed sizes plus the spacing between them always sum to at most
/// `max(0, available)` — which is what makes a stack unable to overflow the
/// space it was given.
///
/// - Parameters:
///   - naturalSizes: Each child's natural size along the layout axis.
///   - isFlexible: Whether each child can flex along the layout axis.
///     Must be the same length as `naturalSizes`.
///   - available: The total space to distribute, *including* the inter-child
///     spacing (which this function accounts for; callers pass the full extent).
///   - spacing: The gap rendered between adjacent non-empty children.
/// - Returns: One allocated size per child; placed sizes + their gaps sum to
///   `<= max(0, available)`.
func distributeLinearSpace(
    naturalSizes: [Int], isFlexible: [Bool], available: Int, spacing: Int = 0
) -> [Int] {
    let total = max(0, available)
    var result = naturalSizes.map { max(0, $0) }
    let flexIndices = result.indices.filter { isFlexible[$0] }
    let gap = max(0, spacing)
    let allSpacing = max(0, result.count - 1) * gap

    var nonFlexTotal = 0
    var flexTotal = 0
    for index in result.indices {
        if isFlexible[index] {
            flexTotal += result[index]
        } else {
            nonFlexTotal += result[index]
        }
    }

    if nonFlexTotal + flexTotal + allSpacing <= total {
        // Everything (content + every gap) fits; flexible children absorb the surplus.
        addLinearSpace(
            total - nonFlexTotal - flexTotal - allSpacing, to: flexIndices, of: &result, weights: nil)
    } else if nonFlexTotal + allSpacing <= total {
        // Fixed content + gaps fit; flexible children share the remainder.
        let weights = flexTotal > 0 ? flexIndices.map { result[$0] } : nil
        for index in flexIndices { result[index] = 0 }
        addLinearSpace(total - nonFlexTotal - allSpacing, to: flexIndices, of: &result, weights: weights)
    } else {
        // Even the fixed content + its gaps overflow: flexible → 0, then place
        // fixed children top-down at their natural size, charging `spacing` only
        // *between* placed children, until the space runs out. Children that
        // don't fit collapse to zero (clipped). Charging spacing per placed
        // child — rather than reserving every gap up front — is what stops the
        // whole stack going blank when the gaps alone would exceed `available`.
        for index in flexIndices { result[index] = 0 }
        var used = 0
        var placedAny = false
        for index in result.indices where !isFlexible[index] {
            let leadingGap = placedAny ? gap : 0
            let room = total - used - leadingGap
            if room <= 0 {
                result[index] = 0
                continue
            }
            let size = min(result[index], room)
            result[index] = size
            if size > 0 {
                used += leadingGap + size
                placedAny = true
            }
        }
    }
    return result
}

/// Adds `amount` cells across `indices`, either evenly or proportionally to
/// `weights`, handing out any rounding remainder one cell at a time.
private func addLinearSpace(_ amount: Int, to indices: [Int], of result: inout [Int], weights: [Int]?) {
    guard !indices.isEmpty, amount > 0 else { return }

    let weightTotal = weights?.reduce(0, +) ?? 0
    if let weights, weightTotal > 0 {
        var distributed = 0
        for (offset, index) in indices.enumerated() {
            let share = amount * weights[offset] / weightTotal
            result[index] += share
            distributed += share
        }
        var remainder = amount - distributed
        var cursor = 0
        while remainder > 0 {
            result[indices[cursor % indices.count]] += 1
            remainder -= 1
            cursor += 1
        }
    } else {
        let per = amount / indices.count
        let remainder = amount % indices.count
        for (offset, index) in indices.enumerated() {
            result[index] += per + (offset < remainder ? 1 : 0)
        }
    }
}
