//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeptResultObservationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A result the cache keeps observes everything read beneath it — not only what
/// a body read.
///
/// A control reads its `Binding` while it draws, in its core, after the body
/// that made the binding has returned, so no body's observation scope saw the
/// read. Under a memo that was a stale control: an `.equatable()` view holding
/// the model compares equal after the property changes (it is the same model),
/// the memo served the buffer drawn with the old value, and the toggle showed
/// the old state until something else cleared the cache.
@MainActor
@Suite("A kept render observes what a control read beneath it")
struct KeptResultObservationTests {

    @Observable
    final class Model {
        var flag = false
    }

    /// An `.equatable()` wrapper that is honestly equal while its row holds the
    /// same model — the shape of a real one: a view compared by the identity of
    /// the reference it was given.
    private struct Holder<Content: View>: View, @preconcurrency Equatable {
        let content: Content
        let model: ObjectIdentifier
        var body: some View { content }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.model == rhs.model }
    }

    private struct ToggleRow: View {
        let model: Model
        var body: some View {
            @Bindable var model = model
            return Toggle("flag", isOn: $model.flag)
        }
    }

    /// Counts its renders: a kept sibling that read nothing must be served.
    private struct CountingText: View, Renderable {
        let counter: Counter
        var body: Never { fatalError("CountingText renders via Renderable") }
        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            counter.renders += 1
            return FrameBuffer(text: "sibling")
        }
    }

    private final class Counter: @unchecked Sendable {
        var renders = 0
    }

    private struct Page: App {
        let model: Model
        let counter: Counter
        init() { self.init(model: Model(), counter: Counter()) }
        init(model: Model, counter: Counter) {
            self.model = model
            self.counter = counter
        }
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    // Holds the focus: a focused control breathes, and a subtree
                    // that animates is never kept, so the toggle must not have it.
                    Button("first") {}
                    Holder(content: ToggleRow(model: model), model: ObjectIdentifier(model)).equatable()
                    Holder(content: CountingText(counter: counter), model: ObjectIdentifier(model)).equatable()
                }
            }
        }
    }

    @Test("A toggle bound to an @Observable under an equal .equatable() view redraws when the property changes")
    func toggleUnderAMemoRedraws() {
        let (model, counter) = (Model(), Counter())
        let app = HeadlessApp(Page(model: model, counter: counter), width: 30, height: 8)
        app.frame(atNanos: 1_000_000_000)
        app.frame(atNanos: 1_100_000_000)
        let off = app.screen.joined(separator: "\n").stripped
        #expect(off.contains("□ flag"), "sanity: the toggle starts off:\n\(off)")
        let siblingRenders = counter.renders

        model.flag = true
        app.frame(atNanos: 1_200_000_000)
        app.frame(atNanos: 1_300_000_000)
        let on = app.screen.joined(separator: "\n").stripped
        #expect(on.contains("■ flag"), "the kept toggle showed the old state:\n\(on)")
        #expect(counter.renders == siblingRenders, "a kept sibling that read nothing was drawn again")
    }
}
