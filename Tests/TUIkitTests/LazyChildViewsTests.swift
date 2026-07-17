//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyChildViewsTests.swift
//
//  Stage 4 of "Locating things without drawing them" (§10): a huge ForEach
//  must not build every row view and id string before any layout question is
//  asked. The lazy collection answers count from the data (O(1)), keys
//  per-touch without invoking the row builder, and builds a row view only
//  when its ordinal is subscripted. The row builder itself is shared with
//  the eager path, so identities cannot drift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Counts row-builder invocations. @unchecked: driven on the main actor.
private final class BuildCounter: @unchecked Sendable {
    var calls = 0
}

@MainActor
@Suite("lazy ForEach child views")
struct LazyChildViewsTests {
    private static let huge = 5_000_000

    private func makeForEach(counting counter: BuildCounter) -> ForEach<Range<Int>, Int, Text> {
        ForEach(0..<Self.huge) { i in
            counter.calls += 1
            return Text("row \(i)")
        }
    }

    @Test("Count and keys come from the data; the row builder never runs")
    func countAndKeysAreFree() {
        let counter = BuildCounter()
        let forEach = makeForEach(counting: counter)
        let context = makeBareRenderContext(width: 30, height: 10)

        let children = forEach.childViewCollection(context: context)
        #expect(children.count == Self.huge, "count answers from the data, O(1)")
        #expect(children.isUniformlyKeyed)
        #expect(children.key(at: 0) == "0")
        #expect(children.key(at: 4_999_999) == "4999999")
        #expect(counter.calls == 0, "no row view was built for count or keys")
    }

    @Test("Subscripting builds exactly the touched rows")
    func subscriptBuildsOnDemand() {
        let counter = BuildCounter()
        let forEach = makeForEach(counting: counter)
        let context = makeBareRenderContext(width: 30, height: 10)

        let children = forEach.childViewCollection(context: context)
        let row = children[42]
        #expect(counter.calls == 1, "one subscript, one build")
        #expect(row.identityChildKey == "42")

        _ = children[4_000_000]
        #expect(counter.calls == 2)
    }

    @Test("Lazy and eager construction agree on identity, key, and memo wrapping")
    func lazyMatchesEager() {
        let items = ["alpha", "beta", "gamma"]
        let forEach = ForEach(items, id: \.self) { Text($0) }
        let context = makeBareRenderContext(width: 30, height: 10)

        let eager = forEach.childViews(context: context)
        let collection = forEach.childViewCollection(context: context)
        #expect(collection.count == eager.count)
        for ordinal in 0..<eager.count {
            let lazyChild = collection[ordinal]
            #expect(lazyChild.identityChildKey == eager[ordinal].identityChildKey)
            #expect(
                lazyChild.identity(under: context) == eager[ordinal].identity(under: context),
                "ordinal \(ordinal) must carry the identical identity either way")
            // Equatable elements memo-wrap on both paths (identity-transparent).
            #expect(lazyChild.wrappedView is _MemoizedRow<AnyEquatableBox, Text>)
            #expect(eager[ordinal].wrappedView is _MemoizedRow<AnyEquatableBox, Text>)
        }
    }

    @Test("The stack's placementCount and keyed routing never build rows")
    func stackQueriesAreLazy() {
        let counter = BuildCounter()
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: makeForEach(counting: counter))
        let context = makeBareRenderContext(width: 30, height: 10)

        #expect(stack.placementCount(context: context) == Self.huge)
        #expect(counter.calls == 0, "count must not build 5M rows")

        // Route a deep target: the key comes off the chain, the ordinal off
        // the data — still no row views.
        let target = context.identity
            .child(erasedType: Text.self, key: "3141592")
            .child(type: Int.self, index: 0)
        #expect(stack.ordinal(of: target, context: context) == 3_141_592)
        #expect(counter.calls == 0, "keyed routing must not build rows")

        // A positional step can't match keyed children — answered for free.
        let positional = context.identity.child(type: Text.self, index: 7)
        #expect(stack.ordinal(of: positional, context: context) == nil)
        #expect(counter.calls == 0)
    }

    @Test("Eager-content stacks keep working through the collection resolver")
    func eagerFallbackUnchanged() {
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .clip,
            content: TupleView(Text("a"), Text("b"), Text("c")))
        let context = makeBareRenderContext(width: 30, height: 10)

        #expect(stack.placementCount(context: context) == 3)
        let second = stack.placement(at: 1, proposal: .unspecified, context: context)!
        #expect(stack.ordinal(of: second.identity, context: context) == 1)
    }
}
