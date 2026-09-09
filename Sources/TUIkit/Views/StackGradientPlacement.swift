//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackGradientPlacement.swift
//
//  Where a stack's children sit inside a `.gradientExtent(.subtree)` ramp.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension _VStackCore {
    /// A child's left edge inside an extent `width` cells wide, under this
    /// stack's horizontal alignment.
    ///
    /// The one place the ramp's horizontal answer is written down: the eager
    /// pass, the viewport walk and the uniform seek all align the same way, and
    /// a ramp that disagreed with any of them would move a colour sideways when
    /// the render path changed under it.
    static func gradientX(childWidth: Int, extent: Int, alignment: HorizontalAlignment) -> Int {
        let slack = max(0, extent - childWidth)
        switch alignment {
        case .leading: return 0
        case .trailing: return slack
        default: return slack / 2
        }
    }

    /// Where each child sits, for a gradient that spans the whole stack.
    ///
    /// Vertical from the distribution PASS 1 produced — exact. Horizontal from
    /// the MEASURED widths, because the rendered ones do not exist yet; exact
    /// wherever measure and render agree, and a disagreement moves a colour
    /// rather than a cell.
    static func gradientOffsets(
        heights: [Int], spacing: Int, sizes: [ViewSize], alignment: HorizontalAlignment,
        extentWidth: Int?
    ) -> [(x: Int, y: Int)] {
        let width = extentWidth ?? sizes.map(\.width).max() ?? 0
        var offsets: [(x: Int, y: Int)] = []
        offsets.reserveCapacity(heights.count)
        var y = 0
        for index in heights.indices {
            let childWidth = index < sizes.count ? sizes[index].width : 0
            offsets.append(
                (x: gradientX(childWidth: childWidth, extent: width, alignment: alignment), y: y))
            // A row allocated no lines is appended through `appendVertically`'s
            // contributes-nothing branch and earns no gap, so it must not
            // advance the ramp by one either — otherwise every row after an
            // `EmptyView` samples the ramp one step below where it draws.
            y += heights[index] + (heights[index] > 0 ? spacing : 0)
        }
        return offsets
    }

    /// The rectangle a `.window` stack's ramp spans, and where each child sits
    /// in it — for the append-while-it-fits path, which renders as it walks and
    /// so cannot learn its own extent on the way.
    ///
    /// **Walked only when a ramp is actually in force**, and only as far as the
    /// fold: a lazy stack's whole point is never touching the rows past it, and
    /// this measure walk stops exactly where the render walk does. With no
    /// `.gradientExtent(.subtree)` above, the frame is `nil` and nothing here
    /// runs at all.
    ///
    /// A `Spacer` between the rows is measured at nothing and then given the
    /// share the render loop will give it, from the same arithmetic — so a
    /// spring inside a lazy stack pushes the ramp exactly as far as it pushes
    /// the rows.
    ///
    /// - Returns: The settled frame (`nil` when no ramp spans this stack) and
    ///   one offset per child, short of `children` where the fold cut the walk.
    func windowGradientPlacement(
        _ children: [ChildView], context: RenderContext
    ) -> (frame: GradientFrame?, offsets: [(x: Int, y: Int)]) {
        guard context.gradientFrame != nil else { return (nil, []) }

        // Spacers take what the fixed rows leave, so their share is only known
        // once every fixed row has been measured — the same order the render
        // loop uses, off the same numbers.
        let proposal = ProposedSize(width: context.availableWidth, height: nil)
        let sizes = children.map { child in
            child.isSpacer
                ? ViewSize.fixed(0, 0)
                : child.measure(proposal: proposal, context: context)
        }
        let spacerCount = children.count { $0.isSpacer }
        var spacerHeight = 0
        var spacerRemainder = 0
        if spacerCount > 0 {
            let fixedHeight = zip(children, sizes)
                .reduce(0) { $0 + ($1.0.isSpacer ? 0 : $1.1.height) }
            let totalSpacing = max(0, children.count - 1) * spacing
            let forSpacers = max(0, context.availableHeight - fixedHeight - totalSpacing)
            spacerHeight = forSpacers / spacerCount
            spacerRemainder = forSpacers % spacerCount
        }

        var heights: [Int] = []
        var placed: [ViewSize] = []
        var running = 0
        var spacerIndex = 0
        for (index, child) in children.enumerated() {
            let spacingBefore = index > 0 ? spacing : 0
            let height: Int
            if child.isSpacer {
                height = max(
                    child.spacerMinLength ?? 0,
                    spacerHeight + (spacerIndex < spacerRemainder ? 1 : 0))
                spacerIndex += 1
            } else {
                height = sizes[index].height
            }
            guard running + spacingBefore + height <= context.availableHeight else { break }
            running += spacingBefore + height
            heights.append(height)
            placed.append(sizes[index])
        }

        // A flexible child (or a Spacer, which makes the column fill) stretches
        // the stack to the width it was offered; otherwise the ramp spans only
        // as far as the widest row, which is what the stack itself will be.
        let fillsWidth = spacerCount > 0 || placed.contains { $0.isWidthFlexible }
        let width = fillsWidth ? context.availableWidth : (placed.map(\.width).max() ?? 0)
        return (
            context.gradientContentFrame(width: width, height: running),
            Self.gradientOffsets(
                heights: heights, spacing: spacing, sizes: placed, alignment: alignment,
                extentWidth: fillsWidth ? context.availableWidth : nil)
        )
    }
}

extension _HStackCore {
    /// A child's top edge inside an extent `height` lines tall, under this
    /// row's vertical alignment. The horizontal twin of
    /// ``_VStackCore/gradientX(childWidth:extent:alignment:)``.
    static func gradientY(childHeight: Int, extent: Int, alignment: VerticalAlignment) -> Int {
        let slack = max(0, extent - childHeight)
        switch alignment {
        case .top: return 0
        case .bottom: return slack
        default: return slack / 2
        }
    }

    /// The rectangle a `.window` row's ramp spans, and where each child sits in
    /// it — the horizontal twin of
    /// ``_VStackCore/windowGradientPlacement(_:context:)``, and walked under
    /// the same rule: only when a ramp is in force, and only as far as the fold.
    ///
    /// - Returns: The settled frame (`nil` when no ramp spans this row) and one
    ///   offset per child, short of `children` where the fold cut the walk.
    func windowGradientPlacement(
        _ children: [ChildView], context: RenderContext
    ) -> (frame: GradientFrame?, offsets: [(x: Int, y: Int)]) {
        guard context.gradientFrame != nil else { return (nil, []) }

        let sizes = children.map { child in
            child.isSpacer
                ? ViewSize.fixed(0, 0)
                : child.measure(proposal: .unspecified, context: context)
        }
        let spacerCount = children.count { $0.isSpacer }
        var spacerWidth = 0
        var spacerRemainder = 0
        if spacerCount > 0 {
            let fixedWidth = zip(children, sizes)
                .reduce(0) { $0 + ($1.0.isSpacer ? 0 : $1.1.width) }
            let totalSpacing = max(0, children.count - 1) * spacing
            let forSpacers = max(0, context.availableWidth - fixedWidth - totalSpacing)
            spacerWidth = forSpacers / spacerCount
            spacerRemainder = forSpacers % spacerCount
        }

        var placed: [(child: ChildView, size: ViewSize, x: Int)] = []
        var running = 0
        var spacerIndex = 0
        for (index, child) in children.enumerated() {
            let spacingBefore = index > 0 ? spacing : 0
            let width: Int
            if child.isSpacer {
                width = max(
                    child.spacerMinLength ?? 0,
                    spacerWidth + (spacerIndex < spacerRemainder ? 1 : 0))
                spacerIndex += 1
            } else {
                width = sizes[index].width
            }
            guard running + spacingBefore + width <= context.availableWidth else { break }
            running += spacingBefore
            placed.append((child, sizes[index], running))
            running += width
        }

        // The row is as tall as its tallest placed child, or fills what it was
        // given when one of them is flexible — the same answer PASS 2 reaches.
        let fillsHeight = placed.contains { $0.size.isHeightFlexible }
        let height =
            fillsHeight ? context.availableHeight : (placed.map(\.size.height).max() ?? 0)
        return (
            context.gradientContentFrame(width: running, height: height),
            placed.map {
                (
                    x: $0.x,
                    y: Self.gradientY(
                        childHeight: $0.size.height, extent: height, alignment: alignment)
                )
            }
        )
    }
}
