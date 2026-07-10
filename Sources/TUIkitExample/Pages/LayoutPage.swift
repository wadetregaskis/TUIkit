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

/// Layout system demo page.
///
/// Shows various layout options including:
/// - VStack (vertical stacking)
/// - HStack (horizontal stacking)
/// - Spacer (flexible space)
/// - Padding and frame modifiers
/// - Lazy stacks windowing to a ScrollView's viewport (live rendered-row set)
struct LayoutPage: View {
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
            DemoAppHeader(L("page.layout.header"))
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
