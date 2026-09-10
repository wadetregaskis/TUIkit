//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateAlphaTests.swift
//
//  §31.4's decline: an indeterminate bar's whole row is one `AnimatedCellRun`,
//  a sweep MOVES, and a run carries frames but no alpha — so no static region
//  describes every frame. §36.7 lifts it, not by teaching the run about alpha
//  but by declining the run.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("An indeterminate bar's alpha")
struct IndeterminateAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 24, height: Int = 3) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private var half: Double { 128.0 / 255 }

    /// **The run is what could not carry the alpha, so the run is what goes.**
    ///
    /// A pre-rendered cycle is an optimisation — these bars used to ask the run loop
    /// to re-render them thirty times a second, and `AnimatedCellRun` took that off
    /// the render path. A translucent bar gives it back: one frame per render, each
    /// with its own exact claim. `Spinner` already does this for a cycle whose frames
    /// are not all one width, and for the same reason.
    @Test("A translucent indeterminate bar claims its frame and emits no run")
    func translucentBarClaimsInsteadOfRunning() {
        let drawn = buffer(ProgressView().tint(Color.red.opacity(0.5)))
        #expect(drawn.animatedCells.isEmpty, "the run cannot carry it: \(drawn.animatedCells.count)")
        #expect(!drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
        #expect(
            drawn.opacityRegions.allSatisfy { $0.fieldOpacity == 1 && $0.inkOpacity < 1 },
            "ink claims only, and an opaque cell owes none: \(drawn.opacityRegions)")
        // A RANGE of alphas, not one: `.sweep`'s trail ramps from the control's empty
        // colour — opaque, the tint does not reach it — to the faded accent, and
        // `Color.lerp` carries alpha as a fourth channel. So the tint's own alpha is
        // the floor and nothing is below it.
        let alphas = drawn.opacityRegions.map(\.inkOpacity)
        #expect(alphas.allSatisfy { $0 >= half }, "\(alphas)")
        #expect(alphas.min() ?? 1 < half + 0.02, "the faded end is reached: \(alphas)")
    }

    /// The common case must be untouched: an opaque bar keeps its pre-rendered cycle,
    /// which is the whole saving. A regression here would be invisible — the bar still
    /// animates, by re-rendering the screen thirty times a second.
    @Test("An opaque indeterminate bar keeps its run and claims nothing")
    func opaqueBarKeepsItsRun() {
        let drawn = buffer(ProgressView())
        #expect(drawn.animatedCells.count == 1, "\(drawn.animatedCells.count)")
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    /// The bar's colours come from three palette slots and, for a styled bar, from the
    /// style's own gradient. Any one of them being translucent is enough, and the test
    /// is asked of the INPUTS rather than of a built frame — a frame paints only the
    /// colours it reached, and the next frame may reach another.
    @Test("Every colour the bar could paint is consulted")
    func everyColourCounts() {
        let opaque = SystemPalette.default
        #expect(
            IndeterminateRenderer.isOpaqueThroughout(
                style: .sweep, filledColor: .red, emptyColor: .blue, accentColor: .green,
                palette: opaque))
        for (name, colours) in [
            ("filled", (Color.red.opacity(0.5), Color.blue, Color.green)),
            ("empty", (Color.red, Color.blue.opacity(0.5), Color.green)),
            ("accent", (Color.red, Color.blue, Color.green.opacity(0.5))),
        ] {
            #expect(
                !IndeterminateRenderer.isOpaqueThroughout(
                    style: .sweep, filledColor: colours.0, emptyColor: colours.1,
                    accentColor: colours.2, palette: opaque),
                "a translucent \(name) was missed")
        }
        // And the style's own gradient, which never meets the palette's colours.
        #expect(
            !IndeterminateRenderer.isOpaqueThroughout(
                style: .gradient(Gradient(colors: [.red, Color.blue.opacity(0.5)])),
                filledColor: .red, emptyColor: .blue, accentColor: .green, palette: opaque))
    }

    /// A styled bar's gradient reaches `laid` as the colour of each cell, so its alpha
    /// arrives per RUN of equal alpha rather than as one rectangle — the shape a moving
    /// ramp actually has on the row it was drawn for.
    @Test("A translucent gradient motion claims runs across the row")
    func gradientMotionClaimsRuns() {
        let drawn = buffer(
            ProgressView()
                .indeterminateStyle(
                    .gradient(
                        Gradient(colors: [
                            Color.rgb(200, 40, 40).opacity(0.25),
                            Color.rgb(40, 40, 200).opacity(1.0),
                        ]))))
        #expect(drawn.animatedCells.isEmpty, "\(drawn.animatedCells.count)")
        let claims = drawn.opacityRegions
        #expect(claims.count > 1, "an alpha per run, not one: \(claims)")
        #expect(claims.allSatisfy { $0.height == 1 }, "\(claims)")
        // Adjacent and in order, covering a contiguous stretch of the bar.
        let sorted = claims.sorted { $0.offsetX < $1.offsetX }
        #expect(
            zip(sorted, sorted.dropFirst()).allSatisfy {
                $0.offsetX + $0.width <= $1.offsetX
            }, "claims must not overlap: \(sorted)")
    }
}
