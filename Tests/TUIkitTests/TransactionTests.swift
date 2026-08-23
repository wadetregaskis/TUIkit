//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransactionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Reports the transaction its subtree renders under, so a test can see what
/// reached it rather than what was set.
private struct TransactionProbe: View, Renderable {
    let report: (Transaction) -> Void

    @Environment(\.transaction) private var transaction

    var body: Never { fatalError("renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        report(context.environment.transaction)
        return FrameBuffer(lines: ["x"])
    }
}

@MainActor
@Suite("Transactions")
struct TransactionTests {

    // MARK: - The ambient scope

    @Test("withAnimation puts an animation in force for its closure only")
    func ambientIsScoped() {
        #expect(Transaction.ambient == nil)
        withAnimation(.linear(duration: 1)) {
            #expect(Transaction.ambient?.animation == .linear(duration: 1))
        }
        #expect(Transaction.ambient == nil)
    }

    @Test("Nesting shadows, and restores")
    func ambientNests() {
        withAnimation(.easeIn) {
            withAnimation(.easeOut) {
                #expect(Transaction.ambient?.animation == .easeOut)
            }
            #expect(Transaction.ambient?.animation == .easeIn)
        }
    }

    @Test("withAnimation(nil) is an explicit refusal, not an absence")
    func nilAnimationIsExplicit() {
        withAnimation(.easeIn) {
            withAnimation(nil) {
                // The transaction is present — so the change is NOT picked up
                // by the outer one — and names no animation, so it snaps.
                #expect(Transaction.ambient != nil)
                #expect(Transaction.ambient?.animation == nil)
            }
        }
    }

    @Test("withAnimation returns what its body returns, and rethrows")
    func passesThroughValuesAndErrors() {
        #expect(withAnimation { 7 } == 7)
        #expect(throws: CancellationError.self) {
            try withAnimation { throw CancellationError() }
        }
    }

    // MARK: - Reaching the render

    // MARK: - A binding's own transaction

    @Test("A binding writes under the transaction it was given")
    func bindingCarriesItsTransaction() {
        final class Box { var value = 0 }
        let box = Box()
        var seen: Transaction?
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        var stated = Transaction(animation: .easeIn)
        stated.disablesAnimations = true

        binding.transaction(stated).wrappedValue = 1
        // The write happened; the transaction was in force WHILE it happened.
        #expect(box.value == 1)

        let watched = Binding(
            get: { box.value },
            set: { _ in seen = Transaction.ambient })
        watched.transaction(stated).wrappedValue = 2
        #expect(seen == stated)
    }

    @Test("A binding with no transaction of its own does not override the caller's")
    func plainBindingDefersToTheAmbientTransaction() {
        var seen: Transaction?
        let binding = Binding(get: { 0 }, set: { _ in seen = Transaction.ambient })

        withAnimation(.linear(duration: 1)) { binding.wrappedValue = 1 }
        #expect(
            seen?.animation == .linear(duration: 1),
            """
            a plain binding is transparent — storing an empty Transaction here \
            would silently un-animate every write made inside withAnimation
            """)

        // …and reads as an empty one, which is what SwiftUI reports.
        #expect(binding.transaction == Transaction())
    }

    @Test("animation(_:) is the transaction form under a name")
    func bindingAnimationIsATransaction() {
        var seen: Transaction?
        let binding = Binding(get: { 0 }, set: { _ in seen = Transaction.ambient })

        binding.animation(.easeOut).wrappedValue = 1
        #expect(seen?.animation == .easeOut)

        // `nil` is a REFUSAL, not an absence: it has to survive an enclosing
        // withAnimation, which only a stated transaction does.
        withAnimation(.linear(duration: 1)) { binding.animation(nil).wrappedValue = 2 }
        #expect(seen != nil && seen?.animation == nil)
    }

    @Test("A change made under an animation stamps the render that follows")
    func changeStampsTheNextRender() {
        // A private instance, not `AppState.shared`: suites run in parallel and
        // the pending transaction is process-wide state.
        let state = AppState()
        withAnimation(.linear(duration: 2)) { state.setNeedsRender() }
        #expect(state.consumePendingTransaction()?.animation == .linear(duration: 2))
        // Consumed, so it applies to exactly one pass. A frame that renders for
        // some other reason must not restart an animation that already began.
        #expect(state.consumePendingTransaction() == nil)
    }

    @Test("An unrelated change does not drop a pending animation")
    func plainChangeDoesNotClear() {
        // `withAnimation { a = 1 }` and then a plain `b = 2` before the frame:
        // one pass renders both, and it must still be the animated one.
        let state = AppState()
        withAnimation(.easeOut) { state.setNeedsRender() }
        state.setNeedsRender()
        #expect(state.consumePendingTransaction()?.animation == .easeOut)
    }

    @Test("The last animated change of a frame is the one that runs")
    func lastAnimatedChangeWins() {
        let state = AppState()
        withAnimation(.easeIn) { state.setNeedsRender() }
        withAnimation(.linear(duration: 9)) { state.setNeedsRender() }
        #expect(state.consumePendingTransaction()?.animation == .linear(duration: 9))
    }

    @Test("A change made outside any transaction stamps nothing")
    func plainChangeStampsNothing() {
        let state = AppState()
        state.setNeedsRender()
        #expect(state.consumePendingTransaction() == nil)
    }

    @Test("An @Observable change carries its transaction too")
    func cacheClearingChangeAlsoStamps() {
        // `setNeedsRenderWithCacheClear` is the `@Observable` route. It is a
        // change like any other and animates like one.
        let state = AppState()
        withAnimation(.easeIn) { state.setNeedsRenderWithCacheClear() }
        #expect(state.consumePendingTransaction()?.animation == .easeIn)
    }

    // MARK: - Narrowing it for a subtree

    @Test("A subtree can be opted out of an ambient animation")
    func disablesAnimationsInASubtree() {
        var seen: Transaction?
        var context = makeRenderContext(width: 10, height: 3)
        context.environment.transaction = Transaction(animation: .easeInOut)

        _ = renderToBuffer(
            TransactionProbe { seen = $0 }.transaction { $0.disablesAnimations = true },
            context: context)

        // The animation is still NAMED — the subtree may want to know what it
        // opted out of — but it no longer applies.
        #expect(seen?.animation == .easeInOut)
        #expect(seen?.disablesAnimations == true)
        #expect(seen?.effectiveAnimation == nil)
    }

    @Test("Without a modifier the frame's transaction reaches the subtree whole")
    func transactionFlowsDown() {
        var seen: Transaction?
        var context = makeRenderContext(width: 10, height: 3)
        context.environment.transaction = Transaction(animation: .linear(duration: 3))

        _ = renderToBuffer(
            VStack { TransactionProbe { seen = $0 } }.padding(), context: context)

        #expect(seen?.effectiveAnimation == .linear(duration: 3))
    }

    @Test("With no transaction at all, nothing animates")
    func defaultIsNoAnimation() {
        var seen: Transaction?
        _ = renderToBuffer(
            TransactionProbe { seen = $0 }, context: makeRenderContext(width: 10, height: 3))
        #expect(seen?.animation == nil)
        #expect(seen?.effectiveAnimation == nil)
    }
}
