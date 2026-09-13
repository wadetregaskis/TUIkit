//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedProviderIdentityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// A child spliced out of a provider that is ITSELF spliced — a `Group` or an
/// `if` that is one element among several in a builder — keeps the address the
/// inner level gave it.
///
/// A stack flattens nested providers one level at a time, and each level used
/// to re-address everything it was handed from its own slot alone. That threw
/// away whatever the level below had told its children apart by: an inner tuple
/// slot, an inner provider's step, a branch. One level of nesting cannot show
/// it, and `SiblingIdentityStabilityTests` and `ForEachIdentityTests` only ever
/// nest one level. Two levels collapsed distinct children onto one identity —
/// one `@State` box, one focus id, and one row-memo entry, which then served
/// one loop's buffer for another loop's row in the same pass.
@MainActor
@Suite("A nested provider's children keep the identities the inner level gave them")
struct NestedProviderIdentityTests {

    /// Draws the value its `@State` was created with, so two views sharing a
    /// box both draw the FIRST one's.
    private struct Tagged: View {
        @State private var text: String

        init(_ initial: String) {
            _text = State(initialValue: initial)
        }

        var body: some View {
            Text("T=\(text)")
        }
    }

    /// Two loops over one id range, in a `Group` that is itself spliced because
    /// a `Text` sits beside it. Same row type, same elements: a shared identity
    /// is a row-memo HIT for every row of the second loop.
    private struct TwoLoopsInAGroup: View {
        var first = 2

        @ViewBuilder var content: some View {
            Text("Legend")
            Group {
                ForEach(0..<first, id: \.self) { Text("fg \($0)") }
                ForEach(0..<2, id: \.self) { Text("bg \($0)") }
            }
        }

        var body: some View {
            VStack(alignment: .leading) { content }
        }
    }

    /// The positional twin: two `if`s in a spliced `Group`. Each gives its view
    /// index 0 under its OWN step, so the steps are all that separate them.
    private struct TwoConditionalsInAGroup: View {
        let shown: Bool

        @ViewBuilder var content: some View {
            Text("h")
            Group {
                if shown { Tagged("A") }
                if shown { Tagged("B") }
            }
        }

        var body: some View {
            VStack(alignment: .leading) { content }
        }
    }

    /// One loop per arm of an `if`/`else`, same row type and ids: only the
    /// branch step separates the arms, and a flat slot-prefixed key has nowhere
    /// to put it.
    private struct KeyedBranches: View {
        let compact: Bool

        @ViewBuilder var content: some View {
            Text("h")
            if compact {
                ForEach(["a", "b"], id: \.self) { Text($0) }
            } else {
                ForEach(["a", "b"], id: \.self) { Text("• " + $0) }
            }
        }

        var body: some View {
            VStack(alignment: .leading) { content }
        }
    }

    private func makeHost() -> (TUIContext, EnvironmentValues) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (tui, environment)
    }

    /// One render pass on a fresh host; the lines, stripped and trimmed.
    private func render(_ view: some View) -> [String] {
        let (tui, environment) = makeHost()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The identity path a stack gives each of `content`'s children.
    private func childPaths(_ content: some View) -> [String] {
        let (tui, environment) = makeHost()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tui)
        return resolveChildViews(from: content, context: context).map {
            $0.identity(under: context).path
        }
    }

    @Test("Two ForEach loops in a spliced Group draw their own rows")
    func twoLoopsInASplicedGroupDrawTheirOwnRows() {
        let rows = render(TwoLoopsInAGroup())
        #expect(
            rows == ["Legend", "fg 0", "fg 1", "bg 0", "bg 1"],
            "the second loop drew the first loop's rows: \(rows)")
    }

    /// The mechanism under the picture above, and the property the fix must not
    /// give up: a row's identity still follows its key, so the second loop's
    /// rows stay put when the first loop grows.
    @Test("Their rows carry one identity each, stable when the loop before them grows")
    func twoLoopsInASplicedGroupHaveDistinctStableIdentities() {
        let two = childPaths(TwoLoopsInAGroup(first: 2).content)
        let three = childPaths(TwoLoopsInAGroup(first: 3).content)
        #expect(two.count == 5)
        #expect(Set(two).count == 5, "rows share an identity: \(two)")
        #expect(
            Array(two.suffix(2)) == Array(three.suffix(2)),
            "the second loop's rows moved when the first grew: \(two) vs \(three)")
    }

    @Test("Two conditionals in a spliced Group keep their own @State")
    func twoConditionalsInASplicedGroupKeepTheirOwnState() {
        let paths = childPaths(TwoConditionalsInAGroup(shown: true).content)
        #expect(Set(paths).count == 3, "two children share an identity: \(paths)")
        let rows = render(TwoConditionalsInAGroup(shown: true))
        #expect(rows == ["h", "T=A", "T=B"], "the second view drew the first's @State: \(rows)")
    }

    @Test("An if/else of same-typed loops beside a sibling keeps its arms apart")
    func keyedBranchesStayApart() {
        let compact = childPaths(KeyedBranches(compact: true).content)
        let expanded = childPaths(KeyedBranches(compact: false).content)
        let compactRows = Set(compact.dropFirst())
        let expandedRows = Set(expanded.dropFirst())
        #expect(compact.count == 3)
        #expect(expanded.count == 3)
        #expect(
            compactRows.isDisjoint(with: expandedRows),
            "both arms' rows land on \(compactRows.sorted())")
    }
}
