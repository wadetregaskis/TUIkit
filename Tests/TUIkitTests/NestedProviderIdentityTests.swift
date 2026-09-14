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
///
/// A branch is lost the same way one provider further in. In `Group { if … else
/// … }` the `Group` has no branch label of its own: the arms are told apart only
/// by the step the conditional took inside `resolveChildViews`, and a keyed row
/// has to carry that step out through the splice. That holds whichever way the
/// loop's rows were built, eagerly or through the child memo from sixteen rows.
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

    /// One loop per arm over the same ids and row type, so only the branch step
    /// tells the arms apart. Every fixture below uses it, so they all test the
    /// same conditional.
    @ViewBuilder
    private static func keyedArms(compact: Bool, count: Int) -> some View {
        if compact {
            ForEach(0..<count, id: \.self) { Tagged("\($0)-compact") }
        } else {
            ForEach(0..<count, id: \.self) { Tagged("\($0)-expanded") }
        }
    }

    /// A keyed `if`/`else` one provider further in: the conditional is the whole
    /// content of a `Group` that is spliced because a `Text` sits beside it.
    /// `Group` has no branch label, so only the step the conditional took inside
    /// `resolveChildViews` tells the arms apart, and the splice used to flatten
    /// it away.
    private struct KeyedBranchesInAGroup: View {
        let compact: Bool
        var count = 2

        @ViewBuilder var content: some View {
            Text("h")
            Group { NestedProviderIdentityTests.keyedArms(compact: compact, count: count) }
        }

        var body: some View {
            VStack(alignment: .leading) { content }
        }
    }

    /// The same under an `if` without `else`, an `Optional`, which has no branch
    /// label either.
    private struct KeyedBranchesInAnIf: View {
        let compact: Bool
        var count = 2
        var shown = true

        @ViewBuilder var content: some View {
            Text("h")
            if shown { NestedProviderIdentityTests.keyedArms(compact: compact, count: count) }
        }

        var body: some View {
            VStack(alignment: .leading) { content }
        }
    }

    /// One loop in a spliced `Group` with no branch anywhere: the hot shape, whose
    /// rows keep the flat slot-prefixed key.
    private struct LoopInAGroup: View {
        let count: Int

        @ViewBuilder var content: some View {
            Text("h")
            Group { ForEach(0..<count, id: \.self) { Text("row \($0)") } }
        }

        var body: some View {
            VStack(alignment: .leading) { content }
        }
    }

    /// The `List` twin: `_ListCore.extractFromChildren` reaches the same tuple
    /// splice through `resolveChildViews`.
    private struct KeyedBranchesInAListGroup: View {
        let compact: Bool
        var count = 2

        var body: some View {
            List {
                Text("h")
                Group { NestedProviderIdentityTests.keyedArms(compact: compact, count: count) }
            }
        }
    }

    /// The `Section` twin, through `Section.extractListRows`.
    private struct KeyedBranchesInASectionGroup: View {
        let compact: Bool
        var count = 2

        var body: some View {
            List {
                Section {
                    Text("h")
                    Group { NestedProviderIdentityTests.keyedArms(compact: compact, count: count) }
                } header: {
                    Text("S")
                }
            }
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

    /// Both arms resolve to a heading plus `count` rows, and no row path is shared.
    private func expectArmsApart(
        _ compact: [String], _ expanded: [String], count: Int, _ shape: String
    ) {
        #expect(compact.count == count + 1, "\(shape): \(compact)")
        #expect(expanded.count == count + 1, "\(shape): \(expanded)")
        let shared = Set(compact.dropFirst()).intersection(expanded.dropFirst())
        #expect(shared.isEmpty, "\(shape): both arms' rows land on \(shared.sorted())")
    }

    /// The expanded arm, drawn after the compact one through one state store,
    /// reads its own initial `@State` rather than the compact arm's.
    private func expectFlipKeepsArmState(_ flip: (before: String, after: String), _ shape: String) {
        #expect(flip.before.contains("T=0-compact"), "\(shape) before the flip: \(flip.before)")
        #expect(
            flip.after.contains("T=0-expanded"),
            "\(shape): the new arm read the old arm's @State: \(flip.after)")
        #expect(!flip.after.contains("-compact"), "\(shape) after the flip: \(flip.after)")
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

    // Counts 2 and 20 sit either side of the child memo's sixteen-row threshold:
    // below it the loop's rows reach the branch unresolved, from it they arrive
    // already resolved by the memo. Both must come out of the splice the same way.

    @Test("A keyed if/else in a spliced Group keeps its arms apart", arguments: [2, 20])
    func keyedBranchesInAGroupStayApart(count: Int) {
        expectArmsApart(
            childPaths(KeyedBranchesInAGroup(compact: true, count: count).content),
            childPaths(KeyedBranchesInAGroup(compact: false, count: count).content),
            count: count, "Group")
    }

    @Test("A keyed if/else in a spliced if keeps its arms apart", arguments: [2, 20])
    func keyedBranchesInAnIfStayApart(count: Int) {
        expectArmsApart(
            childPaths(KeyedBranchesInAnIf(compact: true, count: count).content),
            childPaths(KeyedBranchesInAnIf(compact: false, count: count).content),
            count: count, "if")
    }

    @Test(
        "Flipping a keyed if/else in a spliced Group or if gives each arm its own @State",
        arguments: [2, 20])
    func keyedBranchFlipInAStackKeepsEachArmsState(count: Int) {
        expectFlipKeepsArmState(
            renderedBeforeAndAfterFlip(width: 40, height: 30) {
                KeyedBranchesInAGroup(compact: $0, count: count)
            },
            "Group")
        expectFlipKeepsArmState(
            renderedBeforeAndAfterFlip(width: 40, height: 30) {
                KeyedBranchesInAnIf(compact: $0, count: count)
            },
            "if")
    }

    /// Rows here render at child identities under the list, not at the list's
    /// own, so `Tagged`'s `@State` at index 0 cannot meet `_ListCore`'s slots.
    @Test(
        "A keyed if/else in a Group inside a List or a Section gives each arm its own @State",
        arguments: [2, 20])
    func keyedBranchFlipInAListKeepsEachArmsState(count: Int) {
        expectFlipKeepsArmState(
            renderedBeforeAndAfterFlip(width: 40, height: 30) {
                KeyedBranchesInAListGroup(compact: $0, count: count)
            },
            "List")
        expectFlipKeepsArmState(
            renderedBeforeAndAfterFlip(width: 40, height: 30) {
                KeyedBranchesInASectionGroup(compact: $0, count: count)
            },
            "Section")
    }

    /// The guard on how the fix may decide. From the threshold the child memo
    /// hands a loop's rows back already resolved, so a splice that kept any row
    /// with an identity would move a plain `Group { ForEach }` row off its flat
    /// key the moment its loop reached sixteen rows. The threshold is asked of
    /// `ForEach` rather than written down, so the counts keep straddling it.
    @Test("Rows keep their identities as a spliced loop crosses the child memo's threshold")
    func identitiesStableAcrossTheMemoThreshold() throws {
        let (tui, environment) = makeHost()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tui)
        #expect(context.renderCache != nil, "no render cache, so the child memo never runs")
        let threshold = try #require(
            (1...64).first { count in
                ForEach(0..<count, id: \.self) { Text("\($0)") }.childViewsAreWorthMemoising
            })

        func expectStable(_ shape: String, _ paths: (Int) -> [String]) {
            let below = paths(threshold - 1)
            let at = paths(threshold)
            let above = paths(threshold + 1)
            #expect(below.count == threshold, "\(shape): \(below)")
            #expect(
                Array(at.prefix(threshold)) == below,
                "\(shape): crossing into the memo moved rows: \(below) vs \(at)")
            #expect(
                Array(above.prefix(threshold + 1)) == at,
                "\(shape): one row past the threshold moved rows: \(at) vs \(above)")
        }

        expectStable("Group { ForEach }") { childPaths(LoopInAGroup(count: $0).content) }
        expectStable("Group { if … else … }") {
            childPaths(KeyedBranchesInAGroup(compact: true, count: $0).content)
        }
        expectStable("if { if … else … }") {
            childPaths(KeyedBranchesInAnIf(compact: true, count: $0).content)
        }
    }
}
