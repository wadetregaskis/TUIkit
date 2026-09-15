//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorAnimationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Animating a colour")
struct ColorAnimationTests {

    /// One place in the tree, drawn again as the frame clock advances.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 24, height: 5)

        init(_ animation: Animation?) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        func draw<V: View>(_ view: V, atMillis millis: Int) -> [String] {
            buffer(view, atMillis: millis).lines
        }

        func buffer<V: View>(_ view: V, atMillis millis: Int) -> FrameBuffer {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(view, context: context)
        }
    }

    /// A subtree styled through the `View` modifier — `Text`'s own overload
    /// bakes the colour in, which is a different thing (see below).
    private func styled(_ colour: Color) -> some View {
        VStack { Text("ab") }.foregroundStyle(colour)
    }

    @Test("A foreground colour fades through colours it was never given")
    func foregroundFades() {
        let screen = Screen(.linear(duration: 1))
        let black = screen.draw(styled(.rgb(0, 0, 0)), atMillis: 0)
        // The frame the change lands on still shows the old colour.
        #expect(screen.draw(styled(.rgb(200, 0, 0)), atMillis: 0) == black)

        let half = screen.draw(styled(.rgb(200, 0, 0)), atMillis: 500)
        #expect(half.first?.contains("100;0;0") == true, "got \(half)")

        let end = screen.draw(styled(.rgb(200, 0, 0)), atMillis: 1000)
        #expect(end.first?.contains("200;0;0") == true, "got \(end)")
    }

    @Test("A colour baked into a Text does not fade, and says so")
    func textOwnStyleIsBaked() {
        // `Text.foregroundStyle(_:) -> Text` is a different overload from the
        // `View` one: it returns a `Text` carrying the colour, so the colour is
        // part of the view value rather than something a modifier paints, and
        // there is no modifier left to ask the animator. Wrapping the `Text`
        // is the answer, and this pins the boundary so it is a documented
        // contract rather than a surprise.
        //
        // Deliberate: `Text` is the most-rendered view in the framework and a
        // store lookup per Text would be paid by every app on every frame.
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").foregroundStyle(Color.rgb(0, 0, 0)), atMillis: 0)
        let changed = screen.draw(Text("ab").foregroundStyle(Color.rgb(200, 0, 0)), atMillis: 0)
        #expect(changed.first?.contains("200;0;0") == true, "got \(changed)")
    }

    @Test("A background colour fades too")
    func backgroundFades() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").background(.rgb(0, 0, 0)), atMillis: 0)
        _ = screen.draw(Text("ab").background(.rgb(0, 100, 0)), atMillis: 0)
        let half = screen.draw(Text("ab").background(.rgb(0, 100, 0)), atMillis: 500)
        #expect(half.first?.contains("0;50;0") == true, "got \(half)")
    }

    @Test("A border colour fades")
    func borderFades() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(Text("ab").border(.rgb(0, 0, 0)), atMillis: 0)
        _ = screen.draw(Text("ab").border(.rgb(0, 0, 80)), atMillis: 0)
        let half = screen.draw(Text("ab").border(.rgb(0, 0, 80)), atMillis: 500)
        #expect(half.first?.contains("0;0;40") == true, "got \(half.first ?? "")")
    }

    @Test("A border already carrying a cycle is left alone")
    func cyclingBorderIsNotInterpolated() {
        // An `AnimatedColor` with several frames is a DECORATION on the run
        // loop's replay path. Interpolating one cycle into another would be
        // neither an animation nor a decoration, and would cost a render pass
        // per tick to produce it.
        let screen = Screen(.linear(duration: 1))
        let cycle = AnimatedColor(
            frames: [.rgb(0, 0, 0), .rgb(0, 0, 255)], step: 0, clock: .cursor)
        _ = screen.draw(Text("ab").border(.rgb(255, 255, 255)), atMillis: 0)
        let drawn = screen.draw(Text("ab").border(cycle), atMillis: 0)
        // Drawn at the cycle's own current frame, not partway from white.
        #expect(drawn.first?.contains("0;0;0") == true, "got \(drawn.first ?? "")")
    }

    @Test("Without an animation a colour change is immediate")
    func unanimatedColorSnaps() {
        let screen = Screen(nil)
        _ = screen.draw(styled(.rgb(0, 0, 0)), atMillis: 0)
        let changed = screen.draw(styled(.rgb(200, 0, 0)), atMillis: 0)
        #expect(changed.first?.contains("200;0;0") == true, "got \(changed)")
    }

    @Test("A semantic colour animates between what it resolves to")
    func semanticColorsAnimate() {
        // `.palette.accent` is not a red, a green and a blue until it meets a
        // palette — which is why this goes through the render context rather
        // than through `Animatable`.
        let screen = Screen(.linear(duration: 1))
        let accent = screen.context.environment.palette.accent.resolve(
            with: screen.context.environment.palette)
        _ = screen.draw(styled(.rgb(0, 0, 0)), atMillis: 0)
        _ = screen.draw(styled(.palette.accent), atMillis: 0)
        let half = screen.draw(styled(.palette.accent), atMillis: 500)
        let end = screen.draw(styled(.palette.accent), atMillis: 1000)
        #expect(half != end, "the fade never moved")
        guard let components = accent.rgbComponents else {
            Issue.record("the palette's accent is not a concrete colour")
            return
        }
        #expect(
            end.first?.contains("\(components.red);\(components.green);\(components.blue)") == true,
            "got \(end)")
    }

    @Test("Two backgrounds around one view fade independently")
    func nestedBackgroundsDoNotShareOneRecord() {
        // Only `Renderable` modifiers stand between the two `.background`s, and
        // those push no child identity — so both fills are painted at ONE
        // `ViewIdentity`, and the animation store can only tell them apart by
        // the enclosing `ModifiedView`'s generic type.
        func nested(_ inner: Color) -> some View {
            Text("ab").background(inner).padding(1).background(Color.rgb(0, 0, 200))
        }
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(nested(.rgb(0, 0, 0)), atMillis: 0)
        _ = screen.draw(nested(.rgb(0, 200, 0)), atMillis: 0)
        let half = screen.draw(nested(.rgb(0, 200, 0)), atMillis: 500)

        // `padding(1)` puts the inner fill on the middle row, inside the outer's
        // own fill — so the row carries both SGRs and each can be checked.
        #expect(half.dropFirst().first?.contains("0;100;0") == true, "got \(half)")
        // The outer never changed, so it must not have moved either.
        #expect(half.first?.contains("0;0;200") == true, "got \(half)")
    }

    /// **Alpha is a channel of the animation, not a property carried around it.**
    ///
    /// `ColorAnimation.Data` was red, green and blue, and the reassembly was
    /// `Color.rgb(...)` — whose alpha defaults to opaque. So any colour animating
    /// anywhere came out FULLY OPAQUE for the whole of the animation, and the
    /// alpha reappeared only when the animation finished and `resolving` returned
    /// `target` unchanged. Nothing painted a translucent colour before this
    /// branch, so nothing noticed.
    ///
    /// Fading a translucent highlight in is a change of alpha and nothing else, so
    /// interpolating the other three while snapping this one would animate the
    /// wrong half of the colour.
    @Test("A colour's alpha animates with the rest of it")
    func alphaFades() {
        func veil(_ alpha: UInt8) -> Color {
            var colour = Color.red
            colour.alpha = alpha
            return colour
        }
        func fieldAlpha(_ buffer: FrameBuffer) -> Double? {
            buffer.opacityRegions.first?.fieldOpacity
        }

        let screen = Screen(.linear(duration: 1))
        _ = screen.buffer(veil(0), atMillis: 0)
        // The frame the change lands on still shows the old value.
        #expect(fieldAlpha(screen.buffer(veil(255), atMillis: 0)) == 0)

        let midway = fieldAlpha(screen.buffer(veil(255), atMillis: 500))
        #expect(
            (midway ?? 0) > 0.1 && (midway ?? 1) < 0.9,
            "partway between transparent and opaque, got \(String(describing: midway))")

        let done = fieldAlpha(screen.buffer(veil(255), atMillis: 1_200))
        #expect(done == nil, "and opaque at the end claims no region at all: \(String(describing: done))")
    }
}
