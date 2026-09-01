//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityAnimationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Animating opacity")
struct OpacityAnimationTests {

    /// One place in the tree, faded again as the frame clock advances.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 12, height: 3)

        init(animation: Animation?) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        /// Renders `Text("ABC").opacity(x)` and returns the styled line.
        ///
        /// The whole line, escapes and all: what a fade changes is the colour
        /// the renderer named, and comparing the bytes is the only check that
        /// cannot be fooled by two different opacities landing on one colour.
        func line(_ opacity: Double, atMillis: Int) -> String {
            context.environment.frameNowNanos = Int64(atMillis) * 1_000_000
            let buffer = renderToScreen(Text("ABC").opacity(opacity), context: context)
            return buffer.lines.first ?? ""
        }
    }

    @Test("A change to opacity fades through intermediate colours")
    func opacityFades() {
        // `_OpacityView` is `Animatable`, so this is a fade with no `Animatable`
        // view of the caller's own anywhere in it — the built-in modifier is
        // what makes `withAnimation` do something out of the box.
        let screen = Screen(animation: .linear(duration: 1))
        let opaque = screen.line(1, atMillis: 0)

        // Halfway through a fade to invisible, the colour is neither endpoint.
        let start = screen.line(0, atMillis: 0)
        let middle = screen.line(0, atMillis: 500)
        let end = screen.line(0, atMillis: 1000)
        #expect(start == opaque, "the frame the change lands on still shows the old value")
        #expect(middle != start, "the fade never left its starting colour")
        #expect(middle != end, "the fade jumped straight to its destination")
        #expect(end != opaque, "the fade never arrived")
    }

    @Test("Without an animation, opacity snaps")
    func unanimatedOpacitySnaps() {
        let screen = Screen(animation: nil)
        let opaque = screen.line(1, atMillis: 0)
        let faded = screen.line(0, atMillis: 0)
        #expect(faded != opaque)
        #expect(screen.line(0, atMillis: 500) == faded, "it moved after arriving")
    }

    @Test("A fade ends exactly where an unanimated one would")
    func fadeArrivesAtTheSamePlace() {
        // The animation must not leave the picture a shade off its target: the
        // last frame has to be byte-identical to the one that never animated,
        // or every animated change would leave a residue.
        let animated = Screen(animation: .linear(duration: 1))
        _ = animated.line(1, atMillis: 0)
        _ = animated.line(0.4, atMillis: 0)

        let snapped = Screen(animation: nil)
        _ = snapped.line(1, atMillis: 0)

        #expect(animated.line(0.4, atMillis: 1000) == snapped.line(0.4, atMillis: 0))
    }
}

@MainActor
@Suite("A fade that never ends")
struct RepeatingOpacityTests {

    /// A view whose opacity is on a repeating animation, rendered at a chosen
    /// tick of the replay clock.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 12, height: 3)

        init(_ animation: Animation) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        func render(_ opacity: Double, atTick tick: Int) -> FrameBuffer {
            context.environment.animationTick = tick
            context.environment.frameNowNanos =
                Int64(Double(tick) * AnimationClock.cursor.tickInterval * 1_000_000_000)
            // Bracketed exactly as the run loop brackets a frame. Without this
            // the whole suite passed while the app froze: the store's records
            // were pruned at the end of every pass, so every pass saw a first
            // sight — and a first sight never animates.
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            // Resolved, because the RUNS are the compositor's work now: a
            // repeating fade cannot be coloured until what is behind it is
            // known, so the modifier stamps the whole cycle and the resolution
            // turns it into frames. `renderToBuffer` alone stops one step short
            // and hands back the layer, regions pending.
            return renderToScreen(Text("ABC").opacity(opacity), context: context)
        }

        /// How many animating values the store is tracking.
        var storedAnimationCount: Int {
            context.environment.stateStorage!.animations.count
        }

        /// One pass that renders a different tree entirely.
        func renderSomethingElse() {
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            _ = renderToBuffer(Text("gone"), context: context)
        }

        /// Whether the run loop would still be rendering for this.
        func needsRenders(atTick tick: Int) -> Bool {
            context.environment.stateStorage!.animations.hasLiveAnimations(
                at: Int64(Double(tick) * AnimationClock.cursor.tickInterval * 1_000_000_000))
        }
    }

    @Test("The whole cycle is handed to the run loop, pre-rendered")
    func repeatingFadeBecomesRuns() {
        // 0.4 s out and back is 0.8 s, which is sixteen ticks of the 50 ms
        // replay clock — the same sixteen a focus breath uses.
        let screen = Screen(.linear(duration: 0.4).repeatForever(autoreverses: true))
        _ = screen.render(1, atTick: 0)
        let buffer = screen.render(0.2, atTick: 0)

        #expect(buffer.animatedCells.count == 1, "one row of text, so one run")
        let run = buffer.animatedCells[0]
        #expect(run.isAnimating)
        #expect(run.frames.count == 16, "got \(run.frames.count) frames")
        // The CONTENT clock, not the cursor one. Both tick at the same rate —
        // the sixteen frames above are still sixteen — but only the cursor
        // clock restarts when the focus moves, and a fade the app is running
        // must not. This used to be `.cursor`, and a Tab anywhere on the page
        // sent every such fade back to its first frame.
        #expect(run.clock == .content)
    }

    @Test("And the loop then renders nothing for it")
    func repeatingFadeStopsTheRenders() {
        // The whole point. A fade that never ends, served by re-rendering,
        // costs a render pass for as long as the view is on screen.
        let screen = Screen(.linear(duration: 0.4).repeatForever(autoreverses: true))
        _ = screen.render(1, atTick: 0)
        _ = screen.render(0.2, atTick: 0)
        #expect(!screen.needsRenders(atTick: 0))
        #expect(!screen.needsRenders(atTick: 400), "a repeating fade woke the loop up again")
    }

    @Test("Replaying the tick just rendered changes nothing")
    func replayIsIdentityAtTheCurrentStep() {
        // The property every run must have: the loop splices `frame(at: step)`
        // over what is on screen without consulting the view, so at the step
        // the view just drew, that must be a no-op. A run whose frames are a
        // hair out of phase with the picture repaints the row every tick.
        let screen = Screen(.linear(duration: 0.4).repeatForever(autoreverses: true))
        _ = screen.render(1, atTick: 0)
        for tick in [0, 1, 5, 8, 15, 16, 33] {
            let buffer = screen.render(0.2, atTick: tick)
            for run in buffer.animatedCells {
                // Byte for byte: the frame the loop would splice in at this
                // tick IS the line the render drew. Comparing only the visible
                // characters would pass with the colours a full cycle out of
                // phase, which is the mistake worth catching here.
                #expect(run.frame(atIndex: tick) == buffer.lines[run.offsetY], "tick \(tick)")

                // And splicing it really does leave the cells where they were.
                let replayed = buffer.composited(
                    with: FrameBuffer(lines: [run.frame(atIndex: tick)]),
                    at: (x: run.offsetX, y: run.offsetY))
                #expect(
                    replayed.lines.map(\.stripped) == buffer.lines.map(\.stripped),
                    "tick \(tick) moved the cells")
            }
        }
    }

    @Test("A cycle too long to hold is rendered the ordinary way")
    func longCyclesFallBack() {
        // Past the cap the frames outweigh what they save, so the run loop goes
        // back to rendering — correctly, just not cheaply.
        let screen = Screen(.linear(duration: 60).repeatForever(autoreverses: true))
        _ = screen.render(1, atTick: 0)
        let buffer = screen.render(0.2, atTick: 0)
        #expect(buffer.animatedCells.isEmpty)
        #expect(screen.needsRenders(atTick: 0), "it stopped rendering AND left no runs")
    }

    @Test("The record survives the pass that created it")
    func recordsAreNotPrunedEachPass() {
        // A `Renderable` modifier renders at its PARENT's identity and marks
        // nothing active, so the store cannot use `@State`'s active-identity
        // set to decide what is still alive. It keys on what the tree asked
        // about instead. Get this wrong and every pass is a first sight: the
        // fade jumps to its target, the loop goes quiet, and the CPU graph
        // reads as a total success.
        let screen = Screen(.linear(duration: 0.4).repeatForever(autoreverses: true))
        _ = screen.render(1, atTick: 0)
        _ = screen.render(0.2, atTick: 0)
        // Several passes later it must STILL be animating, at a value it was
        // never given.
        let buffer = screen.render(0.2, atTick: 4)
        #expect(buffer.animatedCells.count == 1, "the animation was pruned mid-flight")
        // Not tick 12: an autoreversing cycle of sixteen is symmetric about its
        // midpoint, so 4 and 12 are the same picture by construction.
        #expect(buffer.lines != screen.render(0.2, atTick: 6).lines, "the fade stood still")
    }

    @Test("A view that leaves the tree takes its animation with it")
    func leavingPrunesTheRecord() {
        let screen = Screen(.linear(duration: 0.4).repeatForever(autoreverses: true))
        _ = screen.render(1, atTick: 0)
        _ = screen.render(0.2, atTick: 0)
        #expect(screen.storedAnimationCount == 1)

        // A pass that renders something else entirely: nothing asks about the
        // fade, so it is gone.
        screen.renderSomethingElse()
        #expect(screen.storedAnimationCount == 0)
    }

    @Test("A finite fade leaves no runs — it just ends")
    func finiteFadesAreNotPreRendered() {
        let screen = Screen(.linear(duration: 0.4))
        _ = screen.render(1, atTick: 0)
        let buffer = screen.render(0.2, atTick: 0)
        #expect(buffer.animatedCells.isEmpty)
        #expect(screen.needsRenders(atTick: 0))
        #expect(!screen.needsRenders(atTick: 100), "a finite fade never finished")
    }
}
