//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PreferenceMemoTests.swift
//
//  Regression tests for preferences interacting with the render memos and
//  the measure pass. The preference stack is rebuilt from scratch every
//  render pass, so a `.preference` inside a value-memoized row used to
//  publish on the first frame only: every cache-hit frame after that
//  silently dropped the value from the frame's collection (and an
//  `onPreferenceChange` in a cached row stopped firing). Preference writes
//  were also unguarded during measure passes, double-applying accumulating
//  `reduce` keys within one frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct TitleKey: PreferenceKey {
    static let defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}

private struct CountKey: PreferenceKey {
    static let defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()  // accumulating: double-writes corrupt it
    }
}

@MainActor
@Suite("Preferences through the render memos")
struct PreferenceMemoTests {
    /// One live-loop-shaped frame; returns the frame's collected preferences.
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, width: Int = 40, height: Int = 10
    ) -> PreferenceValues {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return tuiContext.preferences.current
    }

    @Test("A preference inside a memoized row publishes on every frame")
    func preferenceSurvivesRowMemo() {
        let tuiContext = TUIContext()
        let view = VStack {
            ForEach(["alpha"], id: \.self) { name in
                Text(name).preference(key: TitleKey.self, value: "from-\(name)")
            }
        }

        for frame in 1...3 {
            let prefs = renderFrame(view, tuiContext: tuiContext)
            #expect(prefs[TitleKey.self] == "from-alpha", "frame \(frame) dropped the preference")
        }
    }

    @Test("onPreferenceChange inside a memoized row follows value changes")
    func onChangeSurvivesRowMemo() {
        let tuiContext = TUIContext()
        nonisolated(unsafe) var fired = 0
        func makeView(_ title: String) -> some View {
            VStack {
                ForEach(["alpha"], id: \.self) { name in
                    Text(name)
                        .preference(key: TitleKey.self, value: title)
                        .onPreferenceChange(TitleKey.self) { _ in fired += 1 }
                }
            }
        }

        _ = renderFrame(makeView("one"), tuiContext: tuiContext)
        #expect(fired == 1, "the initial value fires once")
        _ = renderFrame(makeView("one"), tuiContext: tuiContext)
        #expect(fired == 1, "an unchanged value must not re-fire")
        // The row memo must not silence a change either — the observer's
        // side-effect declaration declines the cache, so the changed value
        // reaches it even though the ForEach element is unchanged.
        _ = renderFrame(makeView("two"), tuiContext: tuiContext)
        #expect(fired == 2, "the changed value fires exactly once more")
    }

    /// SwiftUI's contract: the action sees the subtree's REDUCED value, once,
    /// and only when it changed. It used to fire per publisher with RAW
    /// un-reduced values and then again with the reduction — every frame,
    /// changed or not, which spun the render loop when (canonically) the
    /// action wrote `@State`.
    @Test("The observer sees only the reduced value, once, on change")
    func observerSeesReducedValueOnce() {
        let tuiContext = TUIContext()
        nonisolated(unsafe) var seen: [Int] = []
        let view = VStack {
            Text("a").preference(key: CountKey.self, value: 1)
            Text("b").preference(key: CountKey.self, value: 1)
            Text("c").preference(key: CountKey.self, value: 1)
        }
        .onPreferenceChange(CountKey.self) { seen.append($0) }

        _ = renderFrame(view, tuiContext: tuiContext)
        #expect(seen == [3], "raw per-publisher values leaked: \(seen)")
        _ = renderFrame(view, tuiContext: tuiContext)
        #expect(seen == [3], "an unchanged value re-fired: \(seen)")
    }

    @Test("An accumulating key collects each writer exactly once per frame")
    func accumulatingKeyNotDoubleCounted() {
        let tuiContext = TUIContext()
        let view = VStack {
            Text("a").preference(key: CountKey.self, value: 1)
            Text("b").preference(key: CountKey.self, value: 1)
        }

        for frame in 1...2 {
            let prefs = renderFrame(view, tuiContext: tuiContext)
            #expect(prefs[CountKey.self] == 2, "frame \(frame): each writer once, got \(prefs[CountKey.self])")
        }
    }

    @Test("A measure-pass render publishes nothing")
    func measurePassIsSideEffectFree() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        var context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)
        context.isMeasuring = true

        tuiContext.preferences.beginRenderPass()
        _ = renderToBuffer(Text("x").preference(key: CountKey.self, value: 7), context: context)
        #expect(tuiContext.preferences.current[CountKey.self] == 0)
    }
}
