//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListTableBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks specifically targeting `List` and `Table` —
/// the regression watch for #29 (composing them on top of
/// ``ScrollView``). The numbers these emit before and after
/// that refactor are the right gating signal.
///
/// What we want to catch:
///
///   - List/Table render cost growing super-linearly with row
///     count (the windowing should keep it O(viewport_height),
///     not O(item_count)).
///   - Scroll handling adding measurable per-frame overhead
///     when the user isn't scrolling.
///   - Selection lookups regressing — `isSelected(at:)` is
///     called per visible row per render.
///   - Row content with hit-test regions / focus IDs adding
///     measurable cost (the `focusID` field added in this
///     session shouldn't move these numbers).
///
/// All benchmark bodies wrap their work in
/// `MainActor.assumeIsolated` — see the comment in
/// ``LayoutBenchmarks`` for the rationale.
enum ListTableBenchmarks {

    static func register() {
        registerListBenchmarks()
        registerTableBenchmarks()
        registerScrolledListBenchmarks()
    }

    // MARK: - List

    /// A small List (50 items) is the everyday case. Should be
    /// dominated by the visible-row rendering, not the whole-
    /// list bookkeeping.
    private static func registerListBenchmarks() {
        Benchmark("list/50 rows, single-select") { benchmark in
            MainActor.assumeIsolated {
                let items = (0..<50).map { "Row \($0)" }
                let view = List("Items", selection: Binding<String?>.constant("Row 0")) {
                    ForEach(items, id: \.self) { Text($0) }
                }
                let context = tallContext()
                for _ in benchmark.scaledIterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("list/500 rows, single-select") { benchmark in
            MainActor.assumeIsolated {
                let items = (0..<500).map { "Row \($0)" }
                let view = List("Items", selection: Binding<String?>.constant("Row 0")) {
                    ForEach(items, id: \.self) { Text($0) }
                }
                let context = tallContext()
                for _ in benchmark.scaledIterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        /// 1900 rows — emoji-list-sized. This is the case
        /// where lazy rendering matters most; regressions
        /// here would surface as visible frame-rate drops in
        /// the example app.
        Benchmark("list/1900 rows, single-select (emoji-list-sized)") { benchmark in
            MainActor.assumeIsolated {
                let items = (0..<1900).map { "Row \($0)" }
                let view = List("Items", selection: Binding<String?>.constant("Row 0")) {
                    ForEach(items, id: \.self) { Text($0) }
                }
                let context = tallContext()
                for _ in benchmark.scaledIterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("list/50 rows, selectionless") { benchmark in
            MainActor.assumeIsolated {
                let items = (0..<50).map { "Row \($0)" }
                let view = List("Items") {
                    ForEach(items, id: \.self) { Text($0) }
                }
                let context = tallContext()
                for _ in benchmark.scaledIterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }

    // MARK: - Table

    private struct Person: Identifiable, Sendable {
        let id: Int
        let name: String
        let age: Int
        let city: String
    }

    private static let people: [Person] = (0..<200).map {
        Person(id: $0, name: "Person \($0)", age: 20 + ($0 % 60), city: "City \($0 % 10)")
    }

    private static func registerTableBenchmarks() {
        Benchmark("table/200 rows × 3 columns") { benchmark in
            MainActor.assumeIsolated {
                let view = Table(
                    people,
                    selection: Binding<Int?>.constant(nil)
                ) {
                    TableColumn<Person>("Name", value: \.name)
                    TableColumn<Person>("Age") { "\($0.age)" }
                    TableColumn<Person>("City", value: \.city)
                }
                let context = tallContext()
                for _ in benchmark.scaledIterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }

    // MARK: - Scrolled state

    /// Lists are most expensive when they have to render scroll
    /// indicators and re-window. This benchmark drives the
    /// 1000-row case so the number reflects the windowed-
    /// render cost, not first-frame setup.
    private static func registerScrolledListBenchmarks() {
        Benchmark("list/1000 rows, mid-scroll") { benchmark in
            MainActor.assumeIsolated {
                let items = (0..<1000).map { "Row \($0)" }
                let view = List("Items", selection: Binding<String?>.constant("Row 500")) {
                    ForEach(items, id: \.self) { Text($0) }
                }
                let context = tallContext()
                // First render establishes the handler;
                // subsequent renders inherit its scrollOffset.
                // To benchmark the mid-scroll case meaningfully
                // would require mutating handler state between
                // renders, which isn't accessible from the
                // public API. Leaving this as 'rendered
                // repeatedly from the top' for now — it still
                // catches per-render regressions, just doesn't
                // isolate the middle-of-list path.
                for _ in benchmark.scaledIterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }
}
