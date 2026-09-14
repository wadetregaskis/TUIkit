//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemeIndicatorAnimationSpeedTests.swift
//
//  A `Theme`'s `indicatorAnimationSpeeds`: the entries a `.theme(_:)` installs,
//  checked through a spinner's run and a focused text field's caret run.
//  Durations are compared in whole nanoseconds, the unit a run's steps are counted
//  in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// An `Equatable` view that never changes, wrapping a spinner, so its buffer can be
/// served from the memo.
private struct MemoizedThemeSpinner: View, Equatable {
    var body: some View {
        Spinner(style: .dots)
    }
}

@MainActor
@Suite("Indicator animation speeds in a theme")
struct ThemeIndicatorAnimationSpeedTests {
    private typealias Entry = IndicatorAnimationSpeeds.Entry

    private func theme(_ entries: [IndicatorAnimationSpeeds.Entry]) -> Theme {
        Theme(palette: SystemPalette(.green), indicatorAnimationSpeeds: entries)
    }

    /// The frame duration of every run `view` leaves, in nanoseconds.
    private func runNanos(_ view: some View) -> [Int64] {
        let context = RenderContext(availableWidth: 40, availableHeight: 4, tuiContext: TUIContext())
            .isolatingRenderCache()
        return renderToBuffer(view, context: context).animatedCells.map {
            AnimationClock.nanoseconds($0.frameDuration)
        }
    }

    /// The frame duration of the caret run a focused, blinking text field inside
    /// `wrap` leaves, in nanoseconds.
    private func caretNanos(_ wrap: (AnyView) -> some View) -> [Int64] {
        let field = AnyView(TextField("Name", text: Binding.constant("Ada")).textCursor(.block, animation: .blink))
        return renderToBuffer(wrap(field), context: makeRenderContext(width: 30, height: 6)).animatedCells.map {
            AnimationClock.nanoseconds($0.frameDuration)
        }
    }

    /// `[.spinners: 0.5, .all: 2]`: the entry naming more kinds is applied first,
    /// so the one naming fewer wins where they overlap, whichever order they are
    /// written in. The same rule a theme's scoped styles have.
    @Test("A theme's broader entry applies first, so its narrower one wins in either order")
    func broadestFirst() {
        let orders: [[Entry]] = [
            [Entry(0.5, for: .spinners), Entry(2)],
            [Entry(2), Entry(0.5, for: .spinners)],
        ]
        for entries in orders {
            #expect(runNanos(Spinner(style: .dots).theme(theme(entries))) == [220_000_000], "\(entries)")
            #expect(caretNanos { $0.theme(theme(entries)) } == [175_000_000], "\(entries)")
        }
    }

    @Test("Two entries naming as many kinds apply in the order they are written")
    func tiesKeepArrayOrder() {
        #expect(
            runNanos(Spinner(style: .dots).theme(theme([Entry(0.5, for: .spinners), Entry(2, for: .spinners)])))
                == [55_000_000])
        #expect(
            runNanos(Spinner(style: .dots).theme(theme([Entry(2, for: .spinners), Entry(0.5, for: .spinners)])))
                == [220_000_000])
    }

    @Test("A modifier nearer the content beats the theme, and a theme nearer than a modifier beats it")
    func nearerWins() {
        let slow = theme([Entry(0.5, for: .spinners)])
        #expect(
            runNanos(Spinner(style: .dots).indicatorAnimationSpeed(2, for: .spinners).theme(slow)) == [55_000_000])
        #expect(
            runNanos(Spinner(style: .dots).theme(slow).indicatorAnimationSpeed(2, for: .spinners)) == [220_000_000])
    }

    @Test("A theme's entry for one kind leaves the kinds it does not name as inherited")
    func unnamedKindsAreInherited() {
        let view = Spinner(style: .dots).theme(theme([Entry(0.5, for: .textCursor)]))
            .indicatorAnimationSpeed(2, for: .spinners)
        #expect(runNanos(view) == [55_000_000])
        #expect(runNanos(Spinner(style: .dots).theme(theme([]))) == [110_000_000])
    }

    @Test("A change to a theme's speeds alone reaches a spinner inside an .equatable() view")
    func speedsOnlyChangeReachesAMemoizedSubtree() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let cache = RenderCache()
        environment.renderCache = cache
        environment.preferenceStorage = tuiContext.preferences
        let context = RenderContext(
            availableWidth: 20, availableHeight: 2, environment: environment,
            identity: ViewIdentity(path: "Root"))
        func frame(_ entries: [Entry]) -> [Int64] {
            cache.beginRenderPass()
            let buffer = renderToBuffer(MemoizedThemeSpinner().equatable().theme(theme(entries)), context: context)
            cache.removeInactive()
            return buffer.animatedCells.map { AnimationClock.nanoseconds($0.frameDuration) }
        }

        #expect(frame([Entry(1, for: .spinners)]) == [110_000_000])
        let before = cache.stats
        #expect(frame([Entry(1, for: .spinners)]) == [110_000_000])
        #expect(
            cache.stats.delta(since: before).hits >= 1,
            "the spinner was not served from the memo, so this is not the case under test")
        #expect(frame([Entry(2, for: .spinners)]) == [55_000_000])
    }
}
