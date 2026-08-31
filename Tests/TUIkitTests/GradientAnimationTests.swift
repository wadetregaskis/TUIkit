//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientAnimationTests.swift
//
//  A ramp fades the way a colour does — every stop, every location and the
//  geometry's own numbers, each on its own store entry.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Animating a gradient")
struct GradientAnimationTests {

    /// One place in the tree, drawn again as the frame clock advances.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 24, height: 5)

        init(_ animation: Animation?) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: animation)
        }

        func draw<V: View>(_ view: V, atMillis millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(view, context: context).lines
        }
    }

    /// Four rows under a vertical ramp — one colour per row, so a row's ink is
    /// a clean sample of the ramp at that point.
    private func styled(_ colours: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "aa")
            Text(verbatim: "bb")
        }
        .foregroundStyle(
            LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom))
        .gradientExtent(.subtree)
    }

    // MARK: - Stops

    @Test("Every stop of a ramp fades")
    func stopsFade() {
        let screen = Screen(.linear(duration: 1))
        let before = screen.draw(styled([.rgb(0, 0, 0), .rgb(0, 0, 200)]), atMillis: 0)
        // The frame the change lands on still shows the old ramp.
        #expect(screen.draw(styled([.rgb(200, 0, 0), .rgb(0, 200, 0)]), atMillis: 0) == before)

        let half = screen.draw(styled([.rgb(200, 0, 0), .rgb(0, 200, 0)]), atMillis: 500)
        #expect(half[0].contains("100;0;0") == true, "the first stop did not fade: \(half)")
        #expect(half[1].contains("0;100;100") == true, "the last stop did not fade: \(half)")

        let end = screen.draw(styled([.rgb(200, 0, 0), .rgb(0, 200, 0)]), atMillis: 1000)
        #expect(end[0].contains("200;0;0") == true, "got \(end)")
        #expect(end[1].contains("0;200;0") == true, "got \(end)")
    }

    /// The question that kept this unbuilt — "how does a two-stop ramp become a
    /// five-stop one?" — turns out not to need an answer: each stop is its own
    /// entry, so the stops that were already there fade and the ones that were
    /// not appear where they belong. The store's rule for a value it has never
    /// seen is that an appearance is not a change.
    @Test("A ramp that grows a stop fades the stops it already had")
    func growingARampFadesWhatItHad() {
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(styled([.rgb(0, 0, 0), .rgb(0, 0, 200)]), atMillis: 0)
        let grown: [Color] = [.rgb(200, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 100)]
        _ = screen.draw(styled(grown), atMillis: 0)

        let half = screen.draw(styled(grown), atMillis: 500)
        // Stop 0 was there and moves half way: 0 → 200 is 100.
        #expect(half[0].contains("100;0;0") == true, "stop 0 did not fade: \(half)")
        // Stop 1 is new, so it is already itself — and it is the ramp's middle,
        // which at four rows of two is not sampled directly; the LAST row is
        // stop 2, which was stop 1's entry and so fades from (0,0,200) to
        // (0,0,100).
        let end = screen.draw(styled(grown), atMillis: 1000)
        #expect(end[0].contains("200;0;0") == true, "got \(end)")
        #expect(end[1].contains("0;0;100") == true, "got \(end)")
    }

    @Test("Without an animation a ramp changes at once")
    func noAnimationIsImmediate() {
        let screen = Screen(nil)
        _ = screen.draw(styled([.rgb(0, 0, 0), .rgb(0, 0, 200)]), atMillis: 0)
        let changed = screen.draw(styled([.rgb(200, 0, 0), .rgb(0, 200, 0)]), atMillis: 0)
        #expect(changed[0].contains("200;0;0") == true, "got \(changed)")
    }

    /// A stop's LOCATION is a number like any other, so a stop that slides
    /// slides — the ramp's midpoint moves rather than jumping.
    @Test("A stop that moves along the ramp slides")
    func stopLocationSlides() {
        func ramp(_ middle: Double) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "aa")
                Text(verbatim: "bb")
                Text(verbatim: "cc")
            }
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .rgb(0, 0, 0), location: 0),
                        Gradient.Stop(color: .rgb(255, 255, 255), location: middle),
                        Gradient.Stop(color: .rgb(0, 0, 0), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom))
            .gradientExtent(.subtree)
        }
        let screen = Screen(.linear(duration: 1))
        let before = screen.draw(ramp(0.5), atMillis: 0)
        _ = screen.draw(ramp(0.9), atMillis: 0)
        let half = screen.draw(ramp(0.9), atMillis: 500)
        let end = screen.draw(ramp(0.9), atMillis: 1000)
        #expect(half != before, "the stop did not move: \(half)")
        #expect(half != end, "the stop jumped straight there: \(half) vs \(end)")
    }

    // MARK: - Geometry

    /// The geometry's numbers move too, so a ramp can sweep across a view.
    @Test("A moving start point sweeps rather than jumping")
    func geometrySlides() {
        func ramp(_ start: UnitPoint) -> some View {
            Text(verbatim: "abcdefgh")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)],
                        startPoint: start, endPoint: .trailing))
        }
        let screen = Screen(.linear(duration: 1))
        let before = screen.draw(ramp(.leading), atMillis: 0)
        _ = screen.draw(ramp(UnitPoint(x: 0.5, y: 0.5)), atMillis: 0)
        let half = screen.draw(ramp(UnitPoint(x: 0.5, y: 0.5)), atMillis: 500)
        let end = screen.draw(ramp(UnitPoint(x: 0.5, y: 0.5)), atMillis: 1000)
        #expect(half != before, "the start point did not move: \(half)")
        #expect(half != end, "the start point jumped straight there")
    }

    /// A change of KIND has nothing to interpolate — the four numbers a linear
    /// geometry carries are two points, and a radial one's are a centre and two
    /// radii. Each kind has its own slot range, so the store treats the new one
    /// as something it has never seen and shows it.
    @Test("A linear ramp becoming a radial one snaps")
    func changingGeometryKindSnaps() {
        let colours: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(
            Text(verbatim: "abcdefgh")
                .foregroundStyle(
                    LinearGradient(colors: colours, startPoint: .leading, endPoint: .trailing)),
            atMillis: 0)
        let radial = Text(verbatim: "abcdefgh")
            .foregroundStyle(
                RadialGradient(colors: colours, center: .center, startRadius: 0, endRadius: 4))
        let landed = screen.draw(radial, atMillis: 0)
        let settled = screen.draw(radial, atMillis: 1000)
        #expect(landed == settled, "the geometry interpolated: \(landed) vs \(settled)")
    }

    // MARK: - Backgrounds

    @Test("A background ramp fades too")
    func backgroundRampFades() {
        func filled(_ colours: [Color]) -> some View {
            Text(verbatim: "ab")
                .background(
                    LinearGradient(colors: colours, startPoint: .leading, endPoint: .trailing))
        }
        let screen = Screen(.linear(duration: 1))
        _ = screen.draw(filled([.rgb(0, 0, 0), .rgb(0, 0, 200)]), atMillis: 0)
        _ = screen.draw(filled([.rgb(200, 0, 0), .rgb(0, 200, 0)]), atMillis: 0)
        let half = screen.draw(filled([.rgb(200, 0, 0), .rgb(0, 200, 0)]), atMillis: 500)
        #expect(half[0].contains("48;2;100;0;0") == true, "the first stop did not fade: \(half)")
    }
}
