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
            let buffer = renderToBuffer(Text("ABC").opacity(opacity), context: context)
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
