//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Collects the indices of the ``LazyVStack`` rows that actually rendered this
/// frame. Because a row only emits its preference when it renders — and a
/// `LazyVStack` inside a `ScrollView` now windows to the visible viewport — the
/// union is exactly the set of rows on screen, and it changes as you scroll.
private struct LazyRenderedRowsKey: PreferenceKey {
    static let defaultValue: Set<Int> = []
    static func reduce(value: inout Set<Int>, nextValue: () -> Set<Int>) {
        value.formUnion(nextValue())
    }
}

/// Collects the indices of rows that participated in LAYOUT (were measured),
/// reported by the framework's `.onRenderPass` instrumentation. A plain sink
/// class: the callbacks fire in the middle of the measure/render passes, where
/// view state must not be mutated — the page snapshots it from a `.task` loop
/// instead.
@MainActor
private final class LazyMeasureSink {
    private var measured: Set<Int> = []

    func record(_ index: Int) { measured.insert(index) }

    /// The rows measured since the last snapshot (and resets the window).
    func snapshot() -> Set<Int> {
        defer { measured.removeAll(keepingCapacity: true) }
        return measured
    }
}

/// Wraps its subviews onto as many lines as they need, like text — the layout a
/// terminal has no built-in for, and the one that shows what ``Layout`` is for.
///
/// Both passes route through `lines(of:in:)` so the size reported and the
/// arrangement drawn cannot disagree. Note the widths accumulate per line
/// rather than being divided up front: dividing first is what silently loses
/// cells when the geometry is integers.
private struct Flow: Layout {
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

/// One subview per line — the other half of the ``AnyLayout`` switch, so the
/// same chips can be re-arranged without their identities (and state) being
/// torn down.
private struct Column: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        ViewSize(
            width: subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0,
            height: subviews.count)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for (row, subview) in subviews.enumerated() {
            subview.place(at: (x: bounds.x, y: bounds.y + row), proposal: .unspecified)
        }
    }
}

/// Sample data for the custom-layout demo, deliberately of varied widths so the
/// wrap points move as the terminal resizes. Tokens, not chrome — they are the
/// demo's *content*, so they are not translated (as file names in the browser
/// demo are not).
private let flowChips = [
    "swift", "terminal", "layout", "cells", "unicode", "ansi", "focus",
    "scroll", "render", "cache", "guides", "measure", "place", "anchor",
    "wrap", "flow", "column", "cell grid", "proposal", "subview",
]

/// Layout system demo page.
///
/// Shows various layout options including:
/// - VStack (vertical stacking)
/// - HStack (horizontal stacking)
/// - Spacer (flexible space)
/// - Padding and frame modifiers
/// - Lazy stacks windowing to a ScrollView's viewport (live rendered-row set)
/// - Alignment guides, GeometryReader, and a custom `Layout`
struct LayoutPage: View {
    /// Whether the bullet hangs off the stack's alignment line.
    @State private var hangBullet = true

    /// Whether the chips flow onto wrapped lines or stack in one column.
    @State private var flowChipsLayout = true

    /// The rows the windowed `LazyVStack` rendered in the last frame.
    @State private var renderedRows: Set<Int> = []

    /// The rows measured (layout participation) in the last sampling window —
    /// genuinely instrumented via `.onRenderPass`, not inferred.
    @State private var measuredRows: Set<Int> = []

    /// Raw sink the instrumentation callbacks write into mid-pass.
    @State private var measureSink = LazyMeasureSink()

    private let lazyRowCount = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.layout.section.vstack")) {
                VStack(spacing: 0) {
                    Text("\(L("page.layout.item")) 1")
                    Text("\(L("page.layout.item")) 2")
                    Text("\(L("page.layout.item")) 3")
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.hstack")) {
                HStack(spacing: 2) {
                    Text(L("page.layout.left"))
                    Text(L("page.layout.center"))
                    Text(L("page.layout.right"))
                }
                .border()
            }

            DemoSection(L("page.layout.section.spacer")) {
                HStack {
                    Text(L("page.layout.start"))
                    Spacer()
                    Text(L("page.layout.end"))
                }
                .border()
            }

            DemoSection(L("page.layout.section.paddingFrame")) {
                HStack(spacing: 2) {
                    VStack {
                        Text(".padding()").dim()
                        Text(L("page.layout.padded"))
                            .frame(width: 25, alignment: .center)
                            .padding(EdgeInsets(all: 1))
                            .border()  // Uses appearance default
                    }
                    VStack {
                        Text(".frame()").dim()
                        Text(L("page.layout.framed"))
                            .frame(width: 15, alignment: .center)
                            .border()  // Uses appearance default
                    }
                }
            }

            DemoSection(L("page.layout.section.viewThatFits")) {
                // A single row when there is room; the same items stacked
                // vertically when the terminal is too narrow for the row.
                ViewThatFits {
                    HStack(spacing: 2) {
                        Text("[ \(L("page.layout.profile")) ]")
                        Text("[ \(L("page.layout.settings")) ]")
                        Text("[ \(L("page.layout.signOut")) ]")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("[ \(L("page.layout.profile")) ]")
                        Text("[ \(L("page.layout.settings")) ]")
                        Text("[ \(L("page.layout.signOut")) ]")
                    }
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.zstack")) {
                // Children stack back-to-front; alignment positions them within
                // the union of their sizes. Here a label is centred over a band.
                ZStack(alignment: .center) {
                    Text(String(repeating: "▒", count: 28)).foregroundStyle(.palette.accent)
                    Text(" \(L("page.layout.onTop")) ").bold().inverted()
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.alignmentGuide")) {
                // `.alignmentGuide` moves the line the stack aligns on. With the
                // bullet's guide at its own TRAILING edge, the bullet hangs to
                // the left of that line and everything else shifts right to meet
                // it — so the column ends up WIDER than its widest child, which
                // the border makes visible.
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.layout.guideExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(L("page.layout.guideToggle"), isOn: $hangBullet)

                    VStack(alignment: .leading, spacing: 0) {
                        if hangBullet {
                            Text("•")
                                .foregroundStyle(.palette.accent)
                                .alignmentGuide(.leading) { $0[.trailing] }
                        } else {
                            Text("•").foregroundStyle(.palette.accent)
                        }
                        Text(L("page.layout.guideItem"))
                        Text(L("page.layout.guideItem2"))
                    }
                    .border(color: .brightBlack)
                }
            }

            DemoSection(L("page.layout.section.geometryReader")) {
                // The one thing an app could not work around before: reading the
                // space it was actually given. Resize the terminal and watch both
                // the numbers and the chosen arrangement change.
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.layout.geometryExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 1) {
                                Text(L("page.layout.geometryOffered"))
                                    .foregroundStyle(.palette.foregroundSecondary)
                                Text("\(proxy.size.width)×\(proxy.size.height)")
                                    .foregroundStyle(.palette.accent)
                                    .bold()
                                Text(L("page.layout.geometryCells"))
                                    .foregroundStyle(.palette.foregroundTertiary)
                            }
                            if proxy.size.width >= 60 {
                                Text(L("page.layout.geometryWide"))
                                    .foregroundStyle(.palette.success)
                            } else {
                                Text(L("page.layout.geometryNarrow"))
                                    .foregroundStyle(.palette.warning)
                            }
                        }
                    }
                    .frame(height: 2)
                    .border(color: .brightBlack)
                }
            }

            DemoSection(L("page.layout.section.customLayout")) {
                // `Flow` is a real custom Layout — no stack arranges things this
                // way. `AnyLayout` erases the two so the switch keeps ONE
                // identity, and the chips are not rebuilt when it flips.
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.layout.flowExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(L("page.layout.flowToggle"), isOn: $flowChipsLayout)

                    let layout = flowChipsLayout ? AnyLayout(Flow()) : AnyLayout(Column())
                    layout {
                        ForEach(flowChips, id: \.self) { chip in
                            Text(" \(chip) ").inverted()
                        }
                    }
                    .border(color: .brightBlack)
                }
            }

            DemoSection(L("page.layout.section.divider")) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("page.layout.above"))
                    Divider()
                    Text(L("page.layout.between"))
                    Divider(character: "═")
                    Text(L("page.layout.below"))
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.lazy")) {
                // Same API shape as VStack/HStack, but rows are realised lazily.
                // Inside a ScrollView the LazyVStack windows to the visible
                // viewport — only those rows render (and fire onAppear). Each row
                // reports its index via a preference when it renders, so the
                // read-out below is exactly the on-screen set; scroll the list
                // (wheel, or Tab to focus it and use ↑/↓/PageUp/PageDown) and
                // watch the range-set slide.
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.layout.lazyExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 1) {
                        Text(L("page.layout.lazyRendered"))
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(rangeSetDescription(renderedRows))
                            .foregroundStyle(.palette.accent)
                            .bold()
                        Text("(\(renderedRows.count)/\(lazyRowCount))")
                            .foregroundStyle(.palette.foregroundTertiary)
                    }
                    // Layout participation ≠ rendering: the stack may measure
                    // rows (to size the scroll extent) that it never draws.
                    // Reported by the framework's own `.onRenderPass` hook.
                    HStack(spacing: 1) {
                        Text(L("page.layout.lazyMeasured"))
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(rangeSetDescription(measuredRows))
                            .foregroundStyle(.palette.success)
                            .bold()
                        Text("(\(measuredRows.count)/\(lazyRowCount))")
                            .foregroundStyle(.palette.foregroundTertiary)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<lazyRowCount, id: \.self) { index in
                                Text("\(L("page.layout.lazyRow")) \(index)")
                                    .onRenderPass { pass in
                                        if pass == .measure { measureSink.record(index) }
                                    }
                                    .preference(key: LazyRenderedRowsKey.self, value: [index])
                            }
                        }
                    }
                    .frame(height: 8)
                    .border(color: .palette.border)
                    .onPreferenceChange(LazyRenderedRowsKey.self) { renderedRows = $0 }
                    .task {
                        await runMeasureSampler()
                    }

                    LazyHStack(spacing: 2) {
                        Text("\(L("page.layout.col")) 1")
                        Text("\(L("page.layout.col")) 2")
                        Text("\(L("page.layout.col")) 3")
                    }
                    .border(color: .brightBlack)
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("menu.item.layout"))
        }
    }

    /// Snapshots the mid-pass measure sink on a safe async cadence — the
    /// `.onRenderPass` callbacks fire during layout/render, where view state
    /// must not be mutated, so the sink is drained from here instead.
    private func runMeasureSampler() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            let measured = measureSink.snapshot()
            if !measured.isEmpty, measured != measuredRows {
                measuredRows = measured
            }
        }
    }

    /// Collapses a set of indices into a compact range-set string, e.g.
    /// `{3,4,5,7}` → `"3–5, 7"`. `"—"` when empty.
    private func rangeSetDescription(_ set: Set<Int>) -> String {
        guard !set.isEmpty else { return "—" }
        let sorted = set.sorted()
        var runs: [String] = []
        var start = sorted[0]
        var previous = sorted[0]
        func flush() { runs.append(start == previous ? "\(start)" : "\(start)–\(previous)") }
        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
            } else {
                flush()
                start = value
                previous = value
            }
        }
        flush()
        return runs.joined(separator: ", ")
    }
}
