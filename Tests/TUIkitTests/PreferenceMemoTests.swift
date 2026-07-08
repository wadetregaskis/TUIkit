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

    @Test("onPreferenceChange inside a memoized row keeps firing")
    func onChangeSurvivesRowMemo() {
        let tuiContext = TUIContext()
        nonisolated(unsafe) var fired = 0
        let view = VStack {
            ForEach(["alpha"], id: \.self) { name in
                Text(name)
                    .preference(key: TitleKey.self, value: name)
                    .onPreferenceChange(TitleKey.self) { _ in fired += 1 }
            }
        }

        _ = renderFrame(view, tuiContext: tuiContext)
        let after1 = fired
        _ = renderFrame(view, tuiContext: tuiContext)
        #expect(after1 > 0)
        #expect(fired > after1, "the observer must keep firing on cache-hit frames")
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
