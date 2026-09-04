//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomLayout.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Custom Layout

/// A `Layout` conformance arranging N subviews, reached through `AnyLayout`.
///
/// This is the shape that made the Example's "Layout System" page ~8× slower
/// than the rest of that page put together: gating the page's three sections
/// one at a time, the custom-`Layout` section alone accounted for 305 ms of a
/// 335 ms open, while the alignment-guide and `GeometryReader` sections cost
/// 14 ms and 38 ms.
///
/// What it stresses is the `Layout` protocol's own call pattern. A conformance
/// has to work out its arrangement twice — once in `sizeThatFits` to report a
/// size, once in `placeSubviews` to act on it — because there is nowhere to
/// keep the answer between them, so a textbook implementation asks each subview
/// for its size about three times per pass. That is the protocol's shape, not a
/// mistake in the conformance, which is why the cost belongs to the framework
/// to absorb.
enum CustomLayoutScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "customlayout",
        title: "Custom Layout",
        blurb: "N subviews arranged by a Layout conformance behind AnyLayout.",
        stresses: "Layout protocol call pattern · repeated subview measurement · AnyLayout erasure",
        make: { config in AnyView(CustomLayoutView(config: config)) }
    )
}

/// Wraps its subviews onto as many lines as they need — the same shape as the
/// Example's `Flow`, deliberately written the obvious way so the scenario
/// measures the protocol rather than a clever conformance.
private struct Flow: Layout {
    var spacing = 1

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let rows = lines(of: subviews, in: proposal.width ?? 40)
        return ViewSize(width: rows.map(\.width).max() ?? 0, height: rows.count)
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

    private func lines(of subviews: Subviews, in limit: Int) -> [(indices: [Int], width: Int)] {
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

private struct CustomLayoutView: View {
    let config: StressConfig

    var body: some View {
        let count = config.sized(20)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.customlayout.heading", count)).bold()
            Divider()
            AnyLayout(Flow()) {
                ForEach(0..<count, id: \.self) { index in
                    Text(" \(Synth.slug(mix(config.seed, index))) ").inverted()
                }
            }
            .border(.brightBlack)
        }
    }
}
