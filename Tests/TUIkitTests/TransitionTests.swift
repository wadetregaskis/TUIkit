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

        // The arrival is animated too, so let it finish: a view removed
        // mid-arrival departs from where its arrival had got, not from full
        // presence.
        _ = draw(true, atMillis: 0)
        _ = draw(true, atMillis: 1100)
        #expect(draw(false, atMillis: 1100).first == "XXXX")
        #expect(draw(false, atMillis: 1600).first == "  XX")
        #expect(draw(false, atMillis: 2400).isEmpty)
    }

    /// A transition swapped while the view is ON SCREEN belongs to the next
    /// departure, not to the one that was current when it arrived.
    ///
    /// The parting picture is left behind on every frame the view renders — but
    /// only frames that carried an animation were recording one, and every
    /// frame after the arrival is an ordinary state change with no animation in
    /// force. So the store kept the removal from the arrival: the Example's
    /// panel went on fading out long after the picker had been moved to Slide,
    /// and only adopted it on the trip after next.
    @Test("A transition changed while the view is up takes effect when it leaves")
    func removalFollowsTheCurrentTransition() {
        var context = makeRenderContext(width: 8, height: 4)
        context.environment.canAnimate = true

        func draw(_ showing: Bool, _ transition: AnyTransition, animated: Bool, atMillis millis: Int)
            -> [String]
        {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            // Only the show and the hide are animated. The frames in between —
            // where the transition is chosen — are plain state changes, which
            // is what the app actually does.
            context.environment.transaction = Transaction(
                animation: animated ? .linear(duration: 1) : nil)
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            let content: Text? = showing ? Text("XXXX") : nil
            return renderToBuffer(
                content.map { $0.transition(transition) }, context: context
            ).lines.map(\.stripped)
        }

        // Arrives under a fade…
        _ = draw(true, .opacity, animated: true, atMillis: 0)
        _ = draw(true, .opacity, animated: false, atMillis: 1200)
        // …then the choice changes, with nothing animating.
        _ = draw(true, .move(edge: .trailing), animated: false, atMillis: 1300)
        // …and leaving must slide, not fade.
        _ = draw(false, .move(edge: .trailing), animated: true, atMillis: 1400)
        #expect(draw(false, .move(edge: .trailing), animated: true, atMillis: 1900).first == "  XX")
    }

    // MARK: - Leaving

    @Test("A removal inside a stack plays out, holding its row open")
    func removalInsideAStackPlaysOut() {
        // `if` inside a stack is how a view comes and goes in almost every app,
        // and it used to be the one shape a removal could not play in: a stack
        // asks its children to flatten themselves and a `nil` optional flattened
        // to NO children, so the instant the condition went false there was
        // nothing standing where the view stood. Now the `nil` keeps a slot for
        // exactly as long as something is still leaving from it.
        let screen = Screen(.linear(duration: 1))
        // Let it arrive first — appearing under an animation is itself animated,
        // so the view is only whole once the insertion has run its second.
        _ = screen.draw(true, .move(edge: .trailing), atMillis: 0)
        #expect(screen.draw(true, .move(edge: .trailing), atMillis: 1000) == ["XXXX", "----"])
        // The frame it goes: still whole, still in its own row, and the row
        // below has not moved up.
        #expect(screen.draw(false, .move(edge: .trailing), atMillis: 1000) == ["XXXX", "----"])
        #expect(screen.draw(false, .move(edge: .trailing), atMillis: 1500) == ["  XX", "----"])
        // Played out: the slot goes, and the stack finally closes up.
        #expect(screen.draw(false, .move(edge: .trailing), atMillis: 2200) == ["----"])
    }

    @Test("A stack a view is not leaving keeps exactly the children it had")
    func absentOptionalCostsNoSlot() {
        // The other half of the contract: the slot exists only while a removal
        // is actually running. A `nil` that nothing left from contributes
        // nothing, so it cannot push its siblings apart by a stack's spacing —
        // which would be a layout change for every `if` in every app.
        let screen = Screen(nil)
        #expect(screen.draw(false, .opacity, atMillis: 0) == ["----"])
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

        // Arrive fully first, so the departure leaves from full presence.
        _ = draw(true, atMillis: 0)
        _ = draw(true, atMillis: 1100)
        _ = draw(false, atMillis: 1100)
        #expect(draw(false, atMillis: 1500).first == "  XX")
        // Present again. Not "resumed from where it was leaving" — it arrives,
        // which is the same thing that happens to any view that appears.
        #expect(draw(true, atMillis: 1600).first == "    ")
        #expect(draw(true, atMillis: 2100).first == "  XX")
        #expect(draw(true, atMillis: 2600).first == "XXXX")
    }

    /// How a view leaves is decided by the change that REMOVES it — not by
    /// whether any frame it happened to render under was animated.
    @Test("A statically-appeared view still plays an animated removal")
    func staticAppearanceAnimatedRemovalPlays() {
        var context = makeRenderContext(width: 8, height: 4)
        context.environment.canAnimate = true

        func draw(_ showing: Bool, animated: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            context.environment.transaction = Transaction(
                animation: animated ? .linear(duration: 1) : nil)
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            let content: Text? = showing ? Text("XXXX") : nil
            return renderToBuffer(
                content.map { $0.transition(.move(edge: .trailing)) }, context: context
            ).lines.map(\.stripped)
        }

        // Appears with nothing animating, sits on a static screen…
        _ = draw(true, animated: false, atMillis: 0)
        _ = draw(true, animated: false, atMillis: 1000)
        // …and is removed inside withAnimation: the removal must play. It
        // used to snap — no frame the view rendered under was animated, so no
        // departure was ever recorded, and the removal frame's transaction
        // was never consulted.
        #expect(draw(false, animated: true, atMillis: 2000).first == "XXXX")
        #expect(draw(false, animated: true, atMillis: 2500).first == "  XX")
        #expect(draw(false, animated: true, atMillis: 3200).isEmpty)
    }

    @Test("An unanimated removal snaps even when earlier frames were animated")
    func unanimatedRemovalSnapsDespiteAnimatedHistory() {
        var context = makeRenderContext(width: 8, height: 4)
        context.environment.canAnimate = true

        func draw(_ showing: Bool, animated: Bool, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            context.environment.transaction = Transaction(
                animation: animated ? .linear(duration: 1) : nil)
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            let content: Text? = showing ? Text("XXXX") : nil
            return renderToBuffer(
                content.map { $0.transition(.move(edge: .trailing)) }, context: context
            ).lines.map(\.stripped)
        }

        // Every frame the view renders under is animated (an app mid-flight)…
        _ = draw(true, animated: true, atMillis: 0)
        _ = draw(true, animated: true, atMillis: 1500)
        // …and then a plain, unanimated state change removes it. That is a
        // snap. It used to play whatever animation the record was carrying.
        #expect(draw(false, animated: false, atMillis: 2000).isEmpty)
    }

    @Test("A view removed mid-arrival departs from where its arrival had got")
    func midArrivalRemovalDepartsFromPartialPresence() {
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
        // Halfway through sliding on…
        #expect(draw(true, atMillis: 500).first == "  XX")
        // …it is removed. The first departing frame must show the view where
        // it WAS — half arrived — not popped to full presence.
        #expect(draw(false, atMillis: 500).first == "  XX")
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
