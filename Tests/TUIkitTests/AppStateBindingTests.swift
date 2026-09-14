//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppStateBindingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Why these tests exist
//
// A view's `@State` is bound to `StateStorage` when the view renders, and the
// box it binds to knows the view's identity and its context's render cache. A
// write then clears that identity's ancestors and descendants from the cache,
// which is what refreshes a memoized row that draws the value without having it
// in its memo key (a `ForEach` row keyed on its element).
//
// An `App` is not a `View`, so nothing bound its `@State`: the box kept the
// identity-less, sink-less one `State.init` made. A write reached no cache, and a
// memoized row below the scene went on drawing the value from before the write.

/// Draws the App's own `@State` from inside a memoized `ForEach` row. The row's
/// element is `0` whatever `count` is, so the row memo alone cannot see a change.
private struct CountingApp: App {
    @State private var count = 0

    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                ForEach(0..<1, id: \.self) { _ in
                    Text("count \(count)")
                }
            }
        }
    }

    /// A binding onto the App's state, written from outside a frame the way an
    /// event handler writes one.
    var countBinding: Binding<Int> { $count }
}

/// The same shape with the state one level down, in a root `View`: the
/// behaviour App-level `@State` is expected to match.
private struct CountingRoot: View {
    @State private var count = 0
    let exposeBinding: (Binding<Int>) -> Void

    var body: some View {
        exposeBinding($count)
        return VStack {
            ForEach(0..<1, id: \.self) { _ in
                Text("count \(count)")
            }
        }
    }
}

private final class BindingSlot {
    var binding: Binding<Int>?
}

private struct CountingRootApp: App {
    let slot: BindingSlot

    init() { self.slot = BindingSlot() }

    var body: some Scene {
        WindowGroup {
            CountingRoot(exposeBinding: { [slot] in slot.binding = $0 })
        }
    }
}

@MainActor
@Suite("App-level @State")
struct AppStateBindingTests {
    private func frameText<A: App>(_ loop: RenderLoop<A>) -> String {
        (loop.replayable?.contentLines ?? []).map(\.stripped).joined(separator: "\n")
    }

    @Test("A write to a root view's @State redraws a memoized row below it")
    func rootViewStateRedrawsMemoizedRow() throws {
        let app = CountingRootApp()
        let loop = RenderLoopHarness().loop(app)

        loop.render()
        #expect(frameText(loop).contains("count 0"))

        let binding = try #require(app.slot.binding)
        binding.wrappedValue = 1
        loop.render()
        #expect(frameText(loop).contains("count 1"))
    }

    @Test("A write to an App's @State redraws a memoized row below the scene")
    func appStateRedrawsMemoizedRow() {
        let app = CountingApp()
        let loop = RenderLoopHarness().loop(app)

        loop.render()
        #expect(frameText(loop).contains("count 0"))

        app.countBinding.wrappedValue = 1
        loop.render()
        #expect(
            frameText(loop).contains("count 1"),
            "the memoized row kept the App's state from before the write")
    }

    @Test("An App's @State keeps its value across frames")
    func appStatePersistsAcrossFrames() {
        let app = CountingApp()
        let loop = RenderLoopHarness().loop(app)

        loop.render()
        app.countBinding.wrappedValue = 7
        for _ in 0..<3 { loop.render() }
        #expect(app.countBinding.wrappedValue == 7)
        #expect(frameText(loop).contains("count 7"))
    }
}
