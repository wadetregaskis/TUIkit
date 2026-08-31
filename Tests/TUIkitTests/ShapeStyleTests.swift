//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStyleTests.swift
//
//  The vocabulary: that a style reduces to a paint, that erasure survives it,
//  and that the two things a memo depends on — one concrete Equatable answer —
//  actually hold.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A palette that is not dark, because the whole point of blending toward the
/// surface rather than toward black is invisible on a black one.
private struct PaperPalette: Palette {
    let id = "paper"
    let name = "Paper"
    let background = Color.rgb(250, 248, 244)
    let foreground = Color.rgb(20, 20, 24)
    let accent = Color.rgb(0, 90, 200)
    let success = Color.rgb(0, 120, 60)
    let warning = Color.rgb(180, 120, 0)
    let error = Color.rgb(180, 30, 30)
    let info = Color.rgb(0, 90, 200)
    let border = Color.rgb(180, 178, 172)
    let statusBarBackground = Color.rgb(230, 228, 224)
    let appHeaderBackground = Color.rgb(230, 228, 224)
}

@MainActor
@Suite("ShapeStyle")
struct ShapeStyleTests {

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        return environment
    }

    // MARK: - The primitives

    @Test("A colour paints itself")
    func colourIsItsOwnPaint() {
        #expect(Color.rgb(1, 2, 3).paint(in: environment()) == .color(.rgb(1, 2, 3)))
    }

    /// Measured against SwiftUI: `Rectangle().fill(Gradient(colors: [.red, .blue]))`
    /// is red at the top corners and blue at the bottom ones.
    @Test("A bare gradient is a vertical linear gradient")
    func bareGradientIsVertical() {
        let gradient = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        #expect(gradient.paint(in: environment()) == .gradient(GradientPaint(gradient, .linear(from: .top, to: .bottom))))
    }

    @Test("A LinearGradient keeps the direction it was given")
    func linearKeepsItsAxis() {
        let gradient = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        let style = LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
        #expect(style.paint(in: environment()) == .gradient(GradientPaint(gradient, .linear(from: .leading, to: .trailing))))
        // And the three initialisers agree.
        #expect(
            LinearGradient(
                colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)],
                startPoint: .leading, endPoint: .trailing) == style)
        #expect(
            LinearGradient(
                stops: gradient.stops, startPoint: .leading, endPoint: .trailing) == style)
    }

    @Test("The static-member spelling reaches the same style")
    func staticMemberSpelling() {
        let colours: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        let byInit = LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom)
        let byMember: LinearGradient = .linearGradient(
            colors: colours, startPoint: .top, endPoint: .bottom)
        #expect(byMember == byInit)
    }

    // MARK: - Resolution

    /// The SwiftUI way to write a custom style: implement `resolve(in:)` and
    /// inherit everything else. The default `_paint` resolves one step and asks
    /// again, so it must terminate at a primitive.
    private struct Attention: ShapeStyle {
        func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
            environment.isEnabled ? Color.rgb(255, 0, 0) : Color.rgb(100, 100, 100)
        }
    }

    @Test("A custom style resolves through to a paint")
    func customStyleResolves() {
        var enabled = environment()
        enabled.isEnabled = true
        #expect(Attention().paint(in: enabled) == .color(.rgb(255, 0, 0)))

        var disabled = environment()
        disabled.isEnabled = false
        #expect(Attention().paint(in: disabled) == .color(.rgb(100, 100, 100)))
    }

    /// A conformance that supplies neither `resolve(in:)` nor `paint(in:)` is
    /// a programmer error. SwiftUI traps on it; a terminal app should not die,
    /// so it paints in the ink the text would have had anyway.
    private struct Empty: ShapeStyle {}

    @Test("An empty conformance paints the environment's ink rather than trapping")
    func emptyConformanceDegrades() {
        let values = environment()
        #expect(Empty().paint(in: values) == .color(values.palette.foreground))
    }

    // MARK: - Erasure

    @Test("AnyShapeStyle carries whatever it erased")
    func erasureKeepsThePaint() {
        let values = environment()
        let gradient = Gradient(colors: [.rgb(1, 1, 1), .rgb(2, 2, 2)])
        #expect(AnyShapeStyle(Color.rgb(9, 8, 7)).paint(in: values) == .color(.rgb(9, 8, 7)))
        #expect(
            AnyShapeStyle(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                .paint(in: values) == .gradient(GradientPaint(gradient, .linear(from: .leading, to: .trailing))))
        // Erasure is what makes the runtime choice spellable at all.
        let chosen = true ? AnyShapeStyle(Color.rgb(1, 0, 0)) : AnyShapeStyle(gradient)
        #expect(chosen.paint(in: values) == .color(.rgb(1, 0, 0)))
    }

    @Test("Erasure resolves against the environment it is asked in, not the one it was made in")
    func erasureResolvesLate() {
        let erased = AnyShapeStyle(Attention())
        var enabled = environment()
        enabled.isEnabled = true
        var disabled = environment()
        disabled.isEnabled = false
        #expect(erased.paint(in: enabled) == .color(.rgb(255, 0, 0)))
        #expect(erased.paint(in: disabled) == .color(.rgb(100, 100, 100)))
    }

    // MARK: - Modifying a style

    /// The mix is toward the SURFACE, not toward black. Mixing toward black is
    /// what `Color.opacity(_:)` does and it is why "dim" reads as a smudge on a
    /// light palette — the bug class this framework already learned once.
    @Test("A style at opacity blends toward the palette's background")
    func opacityBlendsTowardTheSurface() {
        var light = environment()
        light.palette = PaperPalette()
        let surface = light.palette.background
        let red = Color.rgb(255, 0, 0)
        #expect(
            AnyShapeStyle(red).opacity(0.5).paint(in: light)
                == .color(red.opacity(0.5, over: surface)))
        #expect(
            red.opacity(0.5, over: surface) != red.opacity(0.5),
            "on a light palette, toward-the-surface and toward-black must differ")
    }

    /// `Color` has its own `opacity(_:)` returning a `Color`, and a member on
    /// the concrete type beats a protocol extension — so `.red.opacity(0.5)`
    /// is the older, surface-blind shorthand rather than this. SwiftUI's
    /// `Color.opacity(_:)` shadows its `ShapeStyle` one the same way, so the
    /// spelling means what SwiftUI source means; on the dark palettes this
    /// framework ships the two answers coincide exactly, because mixing toward
    /// black IS mixing toward a black surface.
    @Test("Color's own opacity still wins for a Color, as it does in SwiftUI")
    func colourKeepsItsOwnOpacity() {
        // `.rgb` as an implicit member is the assertion that it IS a Color:
        // a `ShapeStyle` wrapper would not compare to one.
        let faded = Color.rgb(255, 0, 0).opacity(0.5)
        #expect(faded == .rgb(127, 0, 0))
        var dark = environment()
        dark.palette = SystemPalette.green
        #expect(
            AnyShapeStyle(Color.rgb(255, 0, 0)).opacity(0.5).paint(in: dark)
                == .color(Color.rgb(255, 0, 0).opacity(0.5, over: dark.palette.background)))
    }

    /// Every stop, not merely the two ends: a three-stop ramp faded halfway is
    /// still a three-stop ramp, and the middle one moves with the others.
    @Test("A gradient at opacity moves every stop")
    func opacityReachesEveryStop() {
        let values = environment()
        let surface = values.palette.background
        let stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)]
        let faded = Gradient(colors: stops).opacity(0.25).paint(in: values)
        guard case .gradient(let ramp) = faded else {
            Issue.record("a faded gradient stopped being one: \(faded)")
            return
        }
        #expect(ramp.gradient.stops.count == 3)
        for (stop, original) in zip(ramp.gradient.stops, stops) {
            #expect(stop.color == original.opacity(0.25, over: surface))
        }
    }

    /// A semantic colour is resolved before it is mixed, or `.opacity(_:)` on
    /// the palette's own ink would be a silent no-op — `Color.opacity(_:over:)`
    /// returns an unresolved colour untouched.
    @Test("Opacity resolves a semantic colour rather than passing it through")
    func opacityResolvesSemanticColours() {
        let values = environment()
        let faded = AnyShapeStyle(Color.palette.accent).opacity(0.4).paint(in: values)
        #expect(faded != .color(.palette.accent), "the semantic colour was passed through")
        #expect(
            faded
                == .color(
                    values.palette.accent.opacity(0.4, over: values.palette.background)))
    }

    /// `.in(_:)` reads the size and nothing else — the origin is unused because
    /// each leaf re-anchors, which is measured SwiftUI behaviour and is why it
    /// cannot span a set of views.
    @Test("`.in(_:)` carries the size into the paint, and only the size")
    func fixedExtentIsCarriedInThePaint() {
        let gradient = Gradient(colors: [.rgb(1, 0, 0), .rgb(0, 0, 1)])
        let style = LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
        let paint = style.in(CellRect(x: 7, y: 9, width: 40, height: 3)).paint(in: environment())
        guard case .gradient(let ramp) = paint else {
            Issue.record("`.in(_:)` stopped being a gradient: \(paint)")
            return
        }
        #expect(ramp.extent == CellSize(width: 40, height: 3))
        #expect(ramp.geometry == .linear(from: .leading, to: .trailing), "the geometry survived")
        // A colour has no extent, so it is left exactly as it was.
        #expect(
            Color.rgb(3, 4, 5).in(CellRect(x: 0, y: 0, width: 9, height: 9))
                .paint(in: environment()) == .color(.rgb(3, 4, 5)))
    }

    // MARK: - What the memo needs

    /// The render memo asks whether an applied environment value
    /// `is any Equatable`, and an existential answers no — which disables
    /// memoization for the whole subtree beneath it. `Paint` is what travels,
    /// and it must stay concrete and comparable.
    @Test("A paint is Equatable, so a styled subtree can still be memoized")
    func paintIsComparable() {
        let paint: Paint = .color(.rgb(1, 2, 3))
        #expect((paint as Any) is any Equatable)
        #expect(paint == .color(.rgb(1, 2, 3)))
        #expect(paint != .color(.rgb(1, 2, 4)))
        let gradient = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 255, 255)])
        #expect(
            Paint.gradient(GradientPaint(gradient, .linear(from: .top, to: .bottom)))
                != .gradient(GradientPaint(gradient, .linear(from: .leading, to: .trailing))))
    }

    @Test("A paint collapses to one colour where a gradient cannot go")
    func collapsing() {
        #expect(Paint.color(.rgb(4, 5, 6)).representative == .rgb(4, 5, 6))
        #expect(Paint.color(.rgb(4, 5, 6)).solid == .rgb(4, 5, 6))
        let gradient = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 255, 255)])
        let ramp = Paint.gradient(GradientPaint(gradient, .linear(from: .top, to: .bottom)))
        #expect(ramp.solid == nil, "a ramp is not a solid colour")
        #expect(ramp.representative == gradient.color(at: 0.5))
    }
}
