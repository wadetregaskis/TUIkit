//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EnvironmentPropertyTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Environment Key

private struct TestColorKey: EnvironmentKey {
    static let defaultValue: String = "blue"
}

private struct TestSizeKey: EnvironmentKey {
    static let defaultValue: Int = 42
}

extension EnvironmentValues {
    fileprivate var testColor: String {
        get { self[TestColorKey.self] }
        set { self[TestColorKey.self] = newValue }
    }

    fileprivate var testSize: Int {
        get { self[TestSizeKey.self] }
        set { self[TestSizeKey.self] = newValue }
    }
}

// MARK: - Tests

@MainActor
@Suite("@Environment Property Wrapper Tests")
struct EnvironmentPropertyTests {

    /// The active environment is a `@TaskLocal`, so each test body starts with
    /// it unset no matter what any concurrently-running suite is doing —
    /// asserting that, rather than assigning `nil` to arrange it, is both the
    /// stronger check and the only one available now that publishing goes
    /// through `withHydration`.
    @Test("Reads default value outside render context")
    func readsDefaultOutsideRenderContext() {
        #expect(StateRegistration.activeEnvironment == nil)

        let wrapper = Environment(\.testColor)
        #expect(wrapper.wrappedValue == "blue")
    }

    @Test("Reads default int value outside render context")
    func readsDefaultIntOutsideRenderContext() {
        #expect(StateRegistration.activeEnvironment == nil)

        let wrapper = Environment(\.testSize)
        #expect(wrapper.wrappedValue == 42)
    }

    @Test("Reads value from active environment")
    func readsFromActiveEnvironment() {
        var env = EnvironmentValues()
        env.testColor = "red"

        let wrapper = Environment(\.testColor)
        StateRegistration.withHydration(environment: env) {
            #expect(wrapper.wrappedValue == "red")
        }
        #expect(wrapper.wrappedValue == "blue", "the scope must not outlive the call")
    }

    @Test("Multiple @Environment properties read independently")
    func multiplePropertiesReadIndependently() {
        var env = EnvironmentValues()
        env.testColor = "green"
        env.testSize = 100

        let colorWrapper = Environment(\.testColor)
        let sizeWrapper = Environment(\.testSize)
        StateRegistration.withHydration(environment: env) {
            #expect(colorWrapper.wrappedValue == "green")
            #expect(sizeWrapper.wrappedValue == 100)
        }
    }

    @Test("Reads dynamically from current active environment")
    func readsDynamically() {
        var env1 = EnvironmentValues()
        env1.testColor = "red"

        var env2 = EnvironmentValues()
        env2.testColor = "yellow"

        let wrapper = Environment(\.testColor)

        StateRegistration.withHydration(environment: env1) {
            #expect(wrapper.wrappedValue == "red")
        }
        StateRegistration.withHydration(environment: env2) {
            #expect(wrapper.wrappedValue == "yellow")
        }
        #expect(wrapper.wrappedValue == "blue")  // default
    }

    @Test("Environment propagates through render pipeline")
    func propagatesThroughRenderPipeline() {
        // Create a view that uses @Environment internally
        let view = Text("Hello")
            .environment(\.testColor, "purple")

        let context = RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            tuiContext: TUIContext()
        ).isolatingRenderCache()

        // This should render without issues - the environment modifier
        // propagates the value through the render tree
        let buffer = renderToBuffer(view, context: context)
        #expect(!buffer.isEmpty)
    }

    @Test("Nested environment overrides resolve correctly")
    func nestedOverrides() {
        var outerEnv = EnvironmentValues()
        outerEnv.testColor = "outer"

        var innerEnv = EnvironmentValues()
        innerEnv.testColor = "inner"

        let wrapper = Environment(\.testColor)

        // Genuine nesting, not a simulation of it: the inner scope shadows the
        // outer and the outer comes back on its own when the inner returns —
        // which is exactly what a composite view's `body` does to its parent's.
        StateRegistration.withHydration(environment: outerEnv) {
            #expect(wrapper.wrappedValue == "outer")

            StateRegistration.withHydration(environment: innerEnv) {
                #expect(wrapper.wrappedValue == "inner")
            }

            #expect(wrapper.wrappedValue == "outer", "the inner scope must not leak")
        }
        #expect(wrapper.wrappedValue == "blue")
    }

    @Test("@Environment resolves inside a closure created during body (event-handler parity)")
    func resolvesInDeferredClosure() {
        // Box the probe stashes a closure into during `body`, mimicking an
        // .onKeyPress / Button action that runs AFTER render — when the active
        // environment has been cleared.
        final class Sink { var read: (() -> String)? }
        let sink = Sink()

        struct ProbeView: View {
            @Environment(\.testColor) var color
            let sink: Sink
            var body: some View {
                sink.read = { color }  // captures self; reads @Environment when invoked
                return Text(color)
            }
        }

        #expect(StateRegistration.activeEnvironment == nil)
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        _ = renderToBuffer(ProbeView(sink: sink).environment(\.testColor, "teal"), context: context)

        // Render finished → the active environment is nil again, exactly as
        // when an event handler runs. The captured closure must still read the
        // value resolved at render (via the wrapper's box), not the default.
        #expect(StateRegistration.activeEnvironment == nil)
        #expect(sink.read?() == "teal")
    }

    /// The reason the active environment is a task local rather than a plain
    /// global, stated as a test.
    ///
    /// Two suites in this target publish an environment, swift-testing runs
    /// suites in parallel, and the old implementation saved and restored one
    /// process-wide `var` — so a concurrent publisher could capture another's
    /// value as its "previous" and restore it over the top. Latent rather than
    /// active (the window is a few instructions wide, and fifteen consecutive
    /// full-suite runs never hit it), but it is the class already fixed twice
    /// here by deleting shared mutable defaults.
    ///
    /// Two tasks, interleaved deliberately by yielding inside each scope. On
    /// the old global this fails: whichever task publishes second wins, and the
    /// first sees the other's value. On a task local each scope is private to
    /// its own task, so neither can observe the other at all.
    @Test("Concurrent publishers cannot see each other's environment")
    func concurrentPublishersAreIsolated() async {
        func publish(_ color: String) async -> [String] {
            var env = EnvironmentValues()
            env.testColor = color
            let wrapper = Environment(\.testColor)
            return await StateRegistration.withHydration(environment: env) {
                // Suspend inside the scope so the other task interleaves here.
                Task { [wrapper] in
                    var seen = [wrapper.wrappedValue]
                    await Task.yield()
                    seen.append(wrapper.wrappedValue)
                    return seen
                }
            }.value
        }

        async let first = publish("first")
        async let second = publish("second")
        let (firstSeen, secondSeen) = await (first, second)

        // Each task's inner Task inherits its own parent's scope and nothing
        // else — including across the suspension point in the middle.
        #expect(firstSeen == ["first", "first"], "saw \(firstSeen)")
        #expect(secondSeen == ["second", "second"], "saw \(secondSeen)")
    }
}
