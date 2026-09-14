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
/// cells when the geometry is integers. A line is as tall as its tallest
/// subview, so a subview taller than one row does not overlap the next line.
struct Flow: Layout {
    var spacing = 1

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let limit = proposal.width ?? 40
        let rows = lines(of: subviews, in: limit)
        return ViewSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.y
        for line in lines(of: subviews, in: bounds.width) {
            var x = bounds.x
            for index in line.indices {
                subviews[index].place(at: (x: x, y: y), proposal: .unspecified)
                x += subviews[index].sizeThatFits(.unspecified).width + spacing
            }
            y += line.height
        }
    }

    /// Greedily packs subviews into lines no wider than `limit`. A line is as
    /// tall as its tallest subview; shorter subviews sit at its top.
    private func lines(
        of subviews: Subviews, in limit: Int
    ) -> [(indices: [Int], width: Int, height: Int)] {
        var rows: [(indices: [Int], width: Int, height: Int)] = []
        var current: [Int] = []
        var width = 0
        var height = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let advance = current.isEmpty ? size.width : spacing + size.width
            if !current.isEmpty, width + advance > limit {
                rows.append((current, width, height))
                current = [index]
                width = size.width
                height = size.height
            } else {
                current.append(index)
                width += advance
                height = max(height, size.height)
            }
        }
        if !current.isEmpty { rows.append((current, width, height)) }
        return rows
    }
}
