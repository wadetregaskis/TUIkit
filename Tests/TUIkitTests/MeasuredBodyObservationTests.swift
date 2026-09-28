//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeasuredBodyObservationTests.swift
//
//  A body evaluated to MEASURE a view is observed once its type is known to
//  read an `@Observable`, as a body evaluated to draw it always was. On the
//  tree before, a measured body read untracked, so a result kept from a
//  measure — a hugging `List`'s width, the picture of an `.equatable()` view
//  whose `ViewThatFits` chose by a measure — was served stale after a write to
//  what only the measure read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What the readers below read.
@Observable
private final class MeasuredModel {
    /// Read by the label that is drawn.
    var top = "top"
    /// Read by the label that is only measured: too wide to fit, at first.
    var wide = String(repeating: "w", count: 30)
    /// Read by one hugged row, far off the list's window.
    var far = "far"
    /// Read by a type that is never drawn.
    var hidden = String(repeating: "h", count: 30)
}

/// Reads `top` when drawn at the top of the page, `wide` as the candidate a
/// `ViewThatFits` measures.
private struct FitLabel: View {
    let model: MeasuredModel
    let wide: Bool
    var body: some View { Text(verbatim: wide ? model.wide : model.top) }
}

/// A `ViewThatFits` over the wide label and a fallback, kept by the buffer
/// memo: its value — the model it reads — never changes.
private struct Fitting: View, @MainActor Equatable {
    let model: MeasuredModel
    var body: some View {
        ViewThatFits(in: .horizontal) {
            FitLabel(model: model, wide: true)
            Text(verbatim: "narrow")
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

/// The label drawn at the top, which teaches the cache that `FitLabel` reads,
/// over the kept `ViewThatFits`.
private struct FittingPage: View {
    let model: MeasuredModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FitLabel(model: model, wide: false)
            Fitting(model: model).equatable()
        }
    }
}

/// A row of a hugging list: row 20, far off the window, reads `far`, and
/// every other row reads `top` — so the rows that are drawn teach the cache
/// that the type reads.
private struct HugRow: View {
    let model: MeasuredModel
    let index: Int
    var body: some View { Text(verbatim: index == 20 ? model.far : "\(model.top) \(index)") }
}

/// Thirty rows, hugged: the list's width is the widest row's, kept across
/// frames, and only the first few rows are drawn.
private struct HuggingPage: View {
    let model: MeasuredModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(0..<30, id: \.self) { HugRow(model: model, index: $0) }
            }
            .fixedSize(horizontal: true)
            Text(verbatim: "|")
        }
    }
}

/// A type that reads, and is only ever measured: never drawn, so never known
/// to read.
private struct HiddenLabel: View {
    let model: MeasuredModel
    var body: some View { Text(verbatim: model.hidden) }
}

/// Nothing drawn reads: the only reader is the candidate `ViewThatFits`
/// measures and does not choose.
private struct HiddenPage: View {
    let model: MeasuredModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "static")
            ViewThatFits(in: .horizontal) {
                HiddenLabel(model: model)
                Text(verbatim: "narrow")
            }
        }
    }
}

@MainActor
@Suite("A measured body of a reading type is observed")
struct MeasuredBodyObservationTests {
    /// The `ViewThatFits` measures the wide label, finds it too wide, and
    /// draws the fallback; the `.equatable()` around it keeps that picture.
    /// A write that makes the label fit reached nothing: the only read of
    /// `wide` was the measure's.
    @Test("A write to what only a measure read re-lays the view out")
    func measuredOnlyReadInvalidates() {
        let model = MeasuredModel()
        let tui = TUIContext()
        for _ in 0..<3 { _ = observedFrame(FittingPage(model: model), tui: tui, width: 20) }
        #expect(observedFrame(FittingPage(model: model), tui: tui, width: 20).contains("narrow"))
        model.wide = "fits"
        let warm = observedFrame(FittingPage(model: model), tui: tui, width: 20)
        let cold = observedFrame(FittingPage(model: model), tui: TUIContext(), width: 20)
        #expect(cold.contains("fits"))
        #expect(warm == cold, "warm \(warm)\ncold \(cold)")
    }

    /// The hug measures every row and keeps the widest; row 20 is never
    /// drawn. A write that widens it must widen the list.
    @Test("A hugged row off the window still widens the list when what it reads is written")
    func huggedRowOffTheWindow() {
        let model = MeasuredModel()
        let tui = TUIContext()
        for _ in 0..<3 { _ = observedFrame(HuggingPage(model: model), tui: tui) }
        model.far = "a far wider row than the rest"
        let warm = observedFrame(HuggingPage(model: model), tui: tui)
        let cold = observedFrame(HuggingPage(model: model), tui: TUIContext())
        #expect(warm == cold, "warm \(warm)\ncold \(cold)")
    }

    /// Counted as measured: the scope is the measure's, at the row's identity.
    @Test("A measured body of a known reading type arms a measure scope")
    func measuredScopeCounted() {
        let model = MeasuredModel()
        let tui = TUIContext()
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        for _ in 0..<3 { _ = observedFrame(FittingPage(model: model), tui: tui, width: 20) }
        #expect(census.snapshot.armed(.bodyMeasure) > 0, "\(census.snapshot)")
    }

    /// What stays as it was: a type never drawn is never learned, so its
    /// measures read untracked — the residue Option C's C3 closes.
    @Test("A type that is only ever measured is not observed while measured")
    func unknownTypeStaysUnobserved() {
        let model = MeasuredModel()
        let tui = TUIContext()
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        for _ in 0..<3 { _ = observedFrame(HiddenPage(model: model), tui: tui, width: 20) }
        #expect(census.snapshot.armed(.bodyMeasure) == 0, "\(census.snapshot)")
        #expect(tui.renderCache.readingTypes.isEmpty, "nothing drawn read, so no type is known")
    }

    /// A kept result computed before its readers' type was known holds sizes
    /// measured untracked, so the first time a type is seen to read, the
    /// cache is cleared once, at the next pass — and not again.
    @Test("Learning that a type reads clears the cache once")
    func learningClearsOnce() {
        let model = MeasuredModel()
        let tui = TUIContext()
        let before = tui.renderCache.clearGeneration
        _ = observedFrame(FittingPage(model: model), tui: tui, width: 20)
        #expect(tui.renderCache.clearGeneration == before, "learned during the frame, cleared at the next")
        for _ in 0..<3 { _ = observedFrame(FittingPage(model: model), tui: tui, width: 20) }
        #expect(tui.renderCache.clearGeneration == before + 1, "once for the one reading type")
        _ = observedFrame(HuggingPage(model: model), tui: tui)
        _ = observedFrame(HuggingPage(model: model), tui: tui)
        #expect(tui.renderCache.clearGeneration == before + 2, "and once more for the next")
    }
}
