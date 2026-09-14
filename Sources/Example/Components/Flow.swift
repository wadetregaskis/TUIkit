//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Flow.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Wraps its subviews onto as many lines as they need, like text — the layout a
/// terminal has no built-in for, and the one that shows what ``Layout`` is for.
///
/// Both passes route through `lines(of:in:)` so the size reported and the
/// arrangement drawn cannot disagree. Note the widths accumulate per line
/// rather than being divided up front: dividing first is what silently loses
/// cells when the geometry is integers.
struct Flow: Layout {
    var spacing = 1

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let limit = proposal.width ?? 40
        let rows = lines(of: subviews, in: limit)
        return ViewSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.count)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for (row, line) in lines(of: subviews, in: bounds.width).enumerated() {
            var x = bounds.x
            for index in line.indices {
                subviews[index].place(at: (x: x, y: bounds.y + row), proposal: .unspecified)
                x += subviews[index].sizeThatFits(.unspecified).width + spacing
            }
        }
    }

    /// Greedily packs subviews into lines no wider than `limit`.
    private func lines(
        of subviews: Subviews, in limit: Int
    ) -> [(indices: [Int], width: Int)] {
        var rows: [(indices: [Int], width: Int)] = []
        var current: [Int] = []
        var width = 0
        for index in subviews.indices {
            let itemWidth = subviews[index].sizeThatFits(.unspecified).width
            let advance = current.isEmpty ? itemWidth : spacing + itemWidth
            if !current.isEmpty, width + advance > limit {
                rows.append((current, width))
                current = [index]
                width = itemWidth
            } else {
                current.append(index)
                width += advance
            }
        }
        if !current.isEmpty { rows.append((current, width)) }
        return rows
    }
}
