//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A view that comes and goes, in a slot that survives it.
private struct Host: View {
    let showing: Bool
    let transition: AnyTransition

    var body: some View {
        VStack(spacing: 0) {
            if showing {
                Text("XXXX").transition(transition)
            }
            Text("----")
        }
    }
}

@MainActor
@Suite("Transitions")
struct TransitionTests {

    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 8, height: 6)

        init(_ animation: Animation?) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        func draw(_ showing: Bool, _ transition: AnyTransition, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(
                Host(showing: showing, transition: transition), context: context
            ).lines.map(\.stripped)
        }
    }

    // MARK: - Arriving

    @Test("A view moving in starts off its own edge and slides on")
    func insertionSlides() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(false, .move(edge: .leading), atMillis: 0)
        // On the frame it appears it is entirely off to the leading side.
        #expect(screen.draw(true, .move(edge: .leading), atMillis: 0)[0].trimmingCharacters(
            in: .whitespaces).isEmpty)
        #expect(screen.draw(true, .move(edge: .leading), atMillis: 500)[0] == "XX  ")
        #expect(screen.draw(true, .move(edge: .leading), atMillis: 1000)[0] == "XXXX")
    }

    @Test("A view revealed by scale uncovers a cell at a time")
    func insertionScales() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(false, .scale(anchor: .leading), atMillis: 0)
        _ = screen.draw(true, .scale(anchor: .leading), atMillis: 0)
        #expect(screen.draw(true, .scale(anchor: .leading), atMillis: 500)[0] == "XX  ")
        #expect(screen.draw(true, .scale(anchor: .leading), atMillis: 1000)[0] == "XXXX")
    }

    @Test("Without an animation an appearance is instant")
    func unanimatedInsertionIsInstant() {
        let screen = Screen(nil)
        _ = screen.draw(false, .move(edge: .leading), atMillis: 0)
        #expect(screen.draw(true, .move(edge: .leading), atMillis: 0)[0] == "XXXX")
    }

    @Test("A transition with its own animation runs whatever caused the change")
    func explicitAnimationWins() {
        // `.transition(_:.animation(_:))` is how a view insists on how it
        // comes and goes, whoever changed the condition.
        let screen = Screen(nil)
        let transition = AnyTransition.move(edge: .leading).animation(.linear(duration: 1))
        _ = screen.draw(false, transition, atMillis: 0)
        #expect(screen.draw(true, transition, atMillis: 0)[0].trimmingCharacters(
            in: .whitespaces).isEmpty)
        #expect(screen.draw(true, transition, atMillis: 500)[0] == "XX  ")
    }

    // MARK: - Where a removal can be hosted

    @Test("A removal plays out where the slot survives the view")
    func removalNeedsASurvivingSlot() {
        // Rendered as the optional ITSELF rather than as a child of a stack.
        // A stack asks its children to flatten themselves, and a `nil` optional
        // flattens to no children at all — so there is no slot left to play a
        // removal in. Where the optional is the thing being rendered, there is.
        var context = makeRenderContext(width: 8, height: 4)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))

        func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            let content: Text? = showing ? Text("XXXX") : nil
            return renderToBuffer(
                content.map { $0.transition(.move(edge: .trailing)) }, context: context
            ).lines.map(\.stripped)
        }

        _ = draw(true, atMillis: 0)
        #expect(draw(false, atMillis: 0).first == "XXXX")
        #expect(draw(false, atMillis: 500).first == "  XX")
        #expect(draw(false, atMillis: 1200).isEmpty)
    }

    // MARK: - Leaving

    @Test("A removal inside a stack is instant, because no slot is left")
    func removalInsideAStackIsInstant() {
        // The limitation, pinned so it is a stated contract rather than a
        // surprise. A stack asks its children to flatten themselves; a `nil`
        // optional flattens to NO children, so the moment the condition goes
        // false there is nothing in the tree standing where the view stood, and
        // nothing that could play its removal out. The insertion half works
        // here — the view is present for that — and the removal is a jump.
        //
        // Fixing it means an optional keeping a slot of its own rather than
        // flattening, which changes identities and stack spacing for every
        // existing `if` in every app. Not worth it for this.
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(true, .move(edge: .trailing), atMillis: 0)
        #expect(screen.draw(false, .move(edge: .trailing), atMillis: 0)[0] == "----")
        #expect(screen.draw(false, .move(edge: .trailing), atMillis: 200).count == 1)
    }

    @Test("Coming back cancels the departure and runs the insertion again")
    func returningCancelsTheDeparture() {
        var context = makeRenderContext(width: 8, height: 4)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))

        func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            let content: Text? = showing ? Text("XXXX") : nil
            return renderToBuffer(
                content.map { $0.transition(.move(edge: .trailing)) }, context: context
            ).lines.map(\.stripped)
        }

        _ = draw(true, atMillis: 0)
        _ = draw(false, atMillis: 0)
        #expect(draw(false, atMillis: 400).first == "  XX")
        // Present again. Not "resumed from where it was leaving" — it arrives,
        // which is the same thing that happens to any view that appears.
        #expect(draw(true, atMillis: 500).first == "    ")
        #expect(draw(true, atMillis: 1000).first == "  XX")
        #expect(draw(true, atMillis: 1500).first == "XXXX")
    }

    @Test("An unanimated removal is instant")
    func unanimatedRemovalIsInstant() {
        let screen = Screen(nil)
        _ = screen.draw(true, .opacity, atMillis: 0)
        #expect(screen.draw(false, .opacity, atMillis: 0).count == 1)
    }

    // MARK: - Composition

    @Test("Slide is asymmetric on purpose")
    func slideIsAsymmetric() {
        #expect(AnyTransition.slide.insertion == AnyTransition.move(edge: .leading).insertion)
        #expect(AnyTransition.slide.removal == AnyTransition.move(edge: .trailing).removal)
    }

    @Test("Combining applies both")
    func combinedAppliesBoth() {
        let screen = Screen(.linear(duration: 1))
        let both = AnyTransition.move(edge: .leading).combined(with: .opacity)
        _ = screen.draw(false, both, atMillis: 0)
        _ = screen.draw(true, both, atMillis: 0)
        // Half-way: moved AND faded, so the visible cells are in place but the
        // line is not the plain one the move alone would give.
        let half = screen.draw(true, both, atMillis: 500)
        #expect(half[0] == "XX  ")
        let moveOnly = Screen(.linear(duration: 1))
        _ = moveOnly.draw(false, .move(edge: .leading), atMillis: 0)
        _ = moveOnly.draw(true, .move(edge: .leading), atMillis: 0)
        #expect(half[0] == moveOnly.draw(true, .move(edge: .leading), atMillis: 500)[0])
    }

    @Test("Asymmetric takes each half from where it was asked")
    func asymmetricComposes() {
        let transition = AnyTransition.asymmetric(insertion: .opacity, removal: .scale)
        #expect(transition.insertion == AnyTransition.opacity.insertion)
        #expect(transition.removal == AnyTransition.scale.removal)
    }
}
