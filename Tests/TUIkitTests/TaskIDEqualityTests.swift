//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TaskIDEqualityTests.swift
//
//  SwiftUI: "To detect a change, the modifier tests whether a new value for the
//  `id` parameter equals the previous value." TUIkit declared the Equatable
//  constraint and then compared `String(describing:)` instead, which is a
//  different relation in BOTH directions — unequal class instances describe
//  identically, and equal structs can describe differently.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("task(id:) equality")
struct TaskIDEqualityTests {
    /// Apple's own worked example shape: an Equatable reference type whose
    /// `==` compares a field. Two instances describe identically.
    private final class Server: Equatable {
        let name: String
        init(_ name: String) { self.name = name }
        static func == (lhs: Server, rhs: Server) -> Bool { lhs.name == rhs.name }
    }

    /// The mirror: equal by `==`, different by description.
    private struct Row: Equatable, CustomStringConvertible {
        let id: Int
        let lastSeen: Int
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        var description: String { "Row(\(id), \(lastSeen))" }
    }

    /// Renders a `.task(id:)` view twice with the two ids, and reports how
    /// many times the task body ran.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    /// One live-loop-shaped render pass: the begin/end bracket the run loop
    /// puts around a frame, which is what makes the token bookkeeping real.
    private func render<V: View>(_ view: V, in tuiContext: TUIContext) {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4,
            environment: environment, tuiContext: tuiContext)
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.lifecycle.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
    }

    private func starts<ID: Equatable>(_ first: ID, then second: ID) async -> Int {
        let counter = Counter()
        let tuiContext = TUIContext()

        // The task is spawned, not run inline, so each render needs a
        // suspension point before its body has actually executed.
        render(Text("x").task(id: first) { counter.value += 1 }, in: tuiContext)
        for _ in 0..<4 { await Task.yield() }
        render(Text("x").task(id: second) { counter.value += 1 }, in: tuiContext)
        for _ in 0..<4 { await Task.yield() }
        return counter.value
    }

    @Test("An unequal id restarts the task; an equal one does not")
    func restartFollowsEquality() async {
        #expect(await starts(1, then: 1) == 1, "an unchanged id starts once")
        #expect(await starts(1, then: 2) == 2, "a changed id restarts")
    }

    @Test("Two unequal instances that describe identically still restart")
    func classInstancesCompareByEquality() async {
        // `String(describing:)` gives both of these the same text, so the
        // old token comparison saw no change at all.
        #expect(await starts(Server("alpha"), then: Server("beta")) == 2)
        #expect(await starts(Server("alpha"), then: Server("alpha")) == 1, "and equal ones do not")
    }

    @Test("Two equal values that describe differently do NOT restart")
    func equalValuesDoNotRestart() async {
        // The other direction: `==` ignores lastSeen, so this is a non-event
        // and an in-flight task must not be cancelled for it.
        #expect(await starts(Row(id: 1, lastSeen: 10), then: Row(id: 1, lastSeen: 99)) == 1)
        #expect(await starts(Row(id: 1, lastSeen: 10), then: Row(id: 2, lastSeen: 10)) == 2)
    }

    @Test("Two chained task(id:) start once each, not once per frame")
    func chainedTasksKeepTheirOwnGeneration() async {
        let search = Counter()
        let load = Counter()
        let tuiContext = TUIContext()

        // Nothing between them pushes a child identity — `TaskModifier` is
        // `Renderable` and renders its content under the unchanged context — so
        // both modifiers key on ONE identity and one generation counter.
        func view() -> some View {
            Text("x")
                .task(id: 1) { search.value += 1 }
                .task(id: 2) { load.value += 1 }
        }

        for _ in 0..<3 {
            render(view(), in: tuiContext)
            for _ in 0..<4 { await Task.yield() }
        }

        #expect(search.value == 1, "the inner task restarted")
        #expect(load.value == 1, "the outer task restarted")
    }
}
