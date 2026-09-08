//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SiblingIdentityStabilityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// A view's identity must not depend on how many children the views BEFORE it
/// happened to produce.
///
/// A stack flattens its content into one child list, and a positional child
/// used to take its index from that flattened list. So a `ForEach` gaining a
/// row moved every later sibling onto a new identity — and identity is what
/// `@State` binds to, what focus files an id under, what `onAppear` fires
/// against and what the buffer memo is keyed on. Adding one row to a list
/// emptied the form underneath it.
///
/// Keyed rows were never the broken half: `"\(slot)#\(key)"` is namespaced by
/// the provider's STATIC tuple slot and follows its element across insertions.
/// It is the positional children that had to stop counting their neighbours.
@MainActor
@Suite("A sibling's identity does not move when a ForEach grows")
struct SiblingIdentityStabilityTests {

    /// Mutates its `@State` once, on appearing, so a reset reads as `count-0`
    /// on a frame that has already appeared.
    private struct Counter: View {
        @State private var count = 0
        var body: some View {
            Text("count-\(count)").onAppear { count = 7 }
        }
    }

    private func render(_ view: some View, into tui: TUIContext, _ environment: EnvironmentValues)
        -> String
    {
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20, environment: environment, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped).joined(separator: "|")
    }

    private func makeHost() -> (TUIContext, EnvironmentValues) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (tui, environment)
    }

    private struct ListThenControl: View {
        let rows: Int
        var body: some View {
            VStack {
                ForEach(0..<rows, id: \.self) { Text("row-\($0)") }
                Counter()
            }
        }
    }

    @Test("A control after a ForEach keeps its state when the ForEach grows")
    func controlAfterForEachKeepsState() {
        let (tui, environment) = makeHost()
        _ = render(ListThenControl(rows: 3), into: tui, environment)
        #expect(
            render(ListThenControl(rows: 3), into: tui, environment).contains("count-7"),
            "the control case: its state survives a frame at all")
        #expect(
            render(ListThenControl(rows: 4), into: tui, environment).contains("count-7"),
            "one more row emptied the control below the list")
    }

    /// The same thing one level down, which is where the obvious fix went
    /// wrong: re-indexing a provider's children to their position in the
    /// ENCLOSING flattened list just moves the counting inside the provider,
    /// so the `Counter` starts counting the rows beside it instead.
    private struct GroupedListThenControl: View {
        let rows: Int
        var body: some View {
            VStack {
                Group {
                    ForEach(0..<rows, id: \.self) { Text("g-\($0)") }
                    Counter()
                }
                Text("tail")
            }
        }
    }

    @Test("A control after a ForEach INSIDE a Group keeps its state too")
    func controlAfterForEachInsideGroupKeepsState() {
        let (tui, environment) = makeHost()
        _ = render(GroupedListThenControl(rows: 3), into: tui, environment)
        #expect(render(GroupedListThenControl(rows: 3), into: tui, environment).contains("count-7"))
        #expect(
            render(GroupedListThenControl(rows: 4), into: tui, environment).contains("count-7"),
            "the row count reached the control through the Group")
    }

    /// The constraint that rules out the one-line version of this fix.
    ///
    /// Giving a direct child its static slot is only safe while a provider's
    /// children cannot land on the same index. Flattened, they could: the
    /// `Group`'s second child and the sibling after it are both `Counter` at
    /// index 1, same parent — one `@State` box between them, and two controls
    /// filed under one focus id.
    @Test("A Group's children cannot collide with the sibling after it")
    func groupChildrenDoNotCollideWithTheNextSibling() {
        let (tui, environment) = makeHost()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20, environment: environment, tuiContext: tui)
        let children = resolveChildViews(
            from: ViewBuilder.buildBlock(Group { Counter(); Counter() }, Counter()),
            context: context)
        let paths = children.map { $0.identity(under: context).path }
        #expect(paths.count == 3)
        #expect(Set(paths).count == 3, "two of these three share an identity: \(paths)")
    }

    /// Keyed rows keep the identity they had, which is not merely an
    /// optimisation: it is what makes `@State`, focus and scroll position
    /// follow an element across an insertion. It is also the hot path — a step
    /// added here measured `menus` +6.2% — so this pins the shape as well as
    /// the stability.
    @Test("ForEach rows keep their keyed identity, and its depth")
    func foreachRowsKeepTheirKeyedIdentity() {
        let (tui, environment) = makeHost()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20, environment: environment, tuiContext: tui)
        func rowPaths(_ rows: Int) -> [String] {
            resolveChildViews(
                from: ViewBuilder.buildBlock(
                    ForEach(0..<rows, id: \.self) { Text("r\($0)") }, Counter()),
                context: context
            ).map { $0.identity(under: context).path }
        }
        let three = rowPaths(3)
        let four = rowPaths(4)
        #expect(three[0] == "/Text[0#0]", "a keyed row sits directly under the stack: \(three[0])")
        #expect(
            Array(four.prefix(3)) == Array(three.prefix(3)),
            "the rows moved when the collection grew")
        #expect(
            three.last == four.last,
            "the sibling after the loop moved: \(three.last ?? "") vs \(four.last ?? "")")
    }
}
