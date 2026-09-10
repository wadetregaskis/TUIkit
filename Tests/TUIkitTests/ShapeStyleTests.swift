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

    // MARK: - The other twelve static members
    //
    // `.foregroundStyle(.conicGradient(colors: […]))` is the spelling an app
    // writes; the explicit initializer is the spelling the geometry tests use.
    // Between them sits a one-line forward per member, and a forward to the
    // WRONG initializer of the same type still compiles: `.conicGradient`
    // reaching `init(gradient:center:startAngle:endAngle:)` instead of the
    // full-turn `init(gradient:center:angle:)` gives a degenerate zero-width
    // sweep — a flat colour where a colour wheel was asked for. Each of these
    // pins the member against the initializer it claims to spell, including
    // the defaults that are not obvious (`endRadiusFraction: 0.5`, and a conic
    // gradient's `endAngle` of a whole turn past its start).

    private static let ramp: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
    private static var stops: [Gradient.Stop] { Gradient(colors: ramp).stops }

    @Test("The three angular members spell the sweep initializers")
    func angularMembers() {
        let sweep = Angle(radians: 1)
        let end = Angle(radians: 2)
        let gradient = Gradient(colors: Self.ramp)

        let byInit = AngularGradient(
            gradient: gradient, center: .center, startAngle: sweep, endAngle: end)
        let fromGradient: AngularGradient = .angularGradient(
            gradient, startAngle: sweep, endAngle: end)
        let fromColors: AngularGradient = .angularGradient(
            colors: Self.ramp, startAngle: sweep, endAngle: end)
        let fromStops: AngularGradient = .angularGradient(
            stops: Self.stops, startAngle: sweep, endAngle: end)

        #expect(fromGradient == byInit, "the member's default centre is .center")
        #expect(fromColors == byInit)
        #expect(fromStops == byInit)
    }

    @Test("The three conic members spell the FULL-TURN initializer, not the sweep one")
    func conicMembers() {
        let angle = Angle(radians: 0.25)
        let gradient = Gradient(colors: Self.ramp)

        let byInit = AngularGradient(gradient: gradient, center: .center, angle: angle)
        let fromGradient: AngularGradient = .conicGradient(gradient, angle: angle)
        let fromColors: AngularGradient = .conicGradient(colors: Self.ramp, angle: angle)
        let fromStops: AngularGradient = .conicGradient(stops: Self.stops, angle: angle)

        #expect(fromGradient == byInit)
        #expect(fromColors == byInit)
        #expect(fromStops == byInit)
        // The distinguishing fact: a whole turn, not the `.zero` end angle the
        // sweep initializer would have left. Without this the three assertions
        // above pass just as well against the degenerate forward.
        #expect(fromColors.startAngle == angle)
        #expect(fromColors.endAngle.radians == angle.radians + 2 * .pi)
    }

    @Test("The three elliptical members spell the initializer, defaults included")
    func ellipticalMembers() {
        let gradient = Gradient(colors: Self.ramp)
        let byInit = EllipticalGradient(gradient: gradient)
        let fromGradient: EllipticalGradient = .ellipticalGradient(gradient)
        let fromColors: EllipticalGradient = .ellipticalGradient(colors: Self.ramp)
        let fromStops: EllipticalGradient = .ellipticalGradient(stops: Self.stops)

        #expect(fromGradient == byInit)
        #expect(fromColors == byInit)
        #expect(fromStops == byInit)
        #expect(fromColors.startRadiusFraction == 0)
        #expect(fromColors.endRadiusFraction == 0.5, "the middle of each edge")
        #expect(fromColors.center == .center)
    }

    @Test("The three radial members spell the initializer")
    func radialMembers() {
        let gradient = Gradient(colors: Self.ramp)
        let byInit = RadialGradient(
            gradient: gradient, center: .center, startRadius: 1, endRadius: 5)
        let fromGradient: RadialGradient = .radialGradient(
            gradient, startRadius: 1, endRadius: 5)
        let fromColors: RadialGradient = .radialGradient(
            colors: Self.ramp, startRadius: 1, endRadius: 5)
        let fromStops: RadialGradient = .radialGradient(
            stops: Self.stops, startRadius: 1, endRadius: 5)

        #expect(fromGradient == byInit)
        #expect(fromColors == byInit)
        #expect(fromStops == byInit)
    }

    /// The `colors:` / `stops:` convenience initializers the members forward
    /// through: each must build the same stop list the `gradient:` one is given.
    @Test("The colors: and stops: initializers agree with the gradient: one")
    func convenienceInitializers() {
        let gradient = Gradient(colors: Self.ramp)

        #expect(
            AngularGradient(colors: Self.ramp, center: .center)
                == AngularGradient(gradient: gradient, center: .center))
        #expect(
            AngularGradient(stops: Self.stops, center: .center, angle: .zero)
                == AngularGradient(gradient: gradient, center: .center, angle: .zero))
        #expect(EllipticalGradient(colors: Self.ramp) == EllipticalGradient(gradient: gradient))
        #expect(EllipticalGradient(stops: Self.stops) == EllipticalGradient(gradient: gradient))
        #expect(
            RadialGradient(colors: Self.ramp, center: .center, startRadius: 0, endRadius: 3)
                == RadialGradient(
                    gradient: gradient, center: .center, startRadius: 0, endRadius: 3))
        #expect(
            RadialGradient(stops: Self.stops, center: .center, startRadius: 0, endRadius: 3)
                == RadialGradient(
                    gradient: gradient, center: .center, startRadius: 0, endRadius: 3))
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

    /// **A faded style carries alpha; it does not mix toward anything.**
    ///
    /// This used to mix toward `palette.background` and answer with a concrete
    /// colour, and the test asserted that. It was the right answer while alpha did
    /// not exist — the alternative then was mixing toward black, which is why
    /// "dim" read as a smudge on a light palette — and it is the wrong one now.
    /// The page's background is only what is behind a cell when nothing else is,
    /// so a faded label over a coloured panel came out mixed toward the page.
    ///
    /// The alpha travels instead, and the compositor resolves it against whatever
    /// is actually behind the cell.
    @Test("A style at opacity carries the alpha rather than mixing")
    func opacityCarriesTheAlpha() {
        var light = environment()
        light.palette = PaperPalette()
        let red = Color.rgb(255, 0, 0)
        let faded = AnyShapeStyle(red).opacity(0.5).paint(in: light)
        #expect(faded == .color(red.opacity(0.5)), "got \(faded)")
        #expect(faded.representative.alpha == 128, "and it is carried, not consumed")
        #expect(
            faded.representative.value == red.value,
            "the colour itself is untouched — nothing was blended into it")
    }

    /// **The two spellings of `.opacity(_:)` now mean the same thing.**
    ///
    /// `Color` has its own `opacity(_:)` returning a `Color`, and a member on the
    /// concrete type beats a protocol extension — so `.red.opacity(0.5)` takes the
    /// `Color` one and `AnyShapeStyle(.red).opacity(0.5)` takes the `ShapeStyle`
    /// one. SwiftUI shadows them the same way.
    ///
    /// They used to be two different operations wearing one name: one storing
    /// alpha and deferring to the composite, the other consuming it against
    /// `palette.background`. Which you got depended on whether the value's static
    /// type happened to be `Color` — the kind of difference that is invisible at
    /// the call site and visible on screen. They agree now, and that agreement is
    /// what this pins.
    @Test("Color's opacity and ShapeStyle's agree")
    func theTwoOpacitySpellingsAgree() {
        // `.rgb` as an implicit member is the assertion that it IS a Color:
        // a `ShapeStyle` wrapper would not compare to one.
        let faded = Color.rgb(255, 0, 0).opacity(0.5)
        #expect(faded.value == Color.ColorValue.rgb(red: 255, green: 0, blue: 0))
        #expect(faded.alpha == 128, "the colour carries it rather than mixing it")
        var dark = environment()
        dark.palette = SystemPalette.green
        #expect(
            AnyShapeStyle(Color.rgb(255, 0, 0)).opacity(0.5).paint(in: dark)
                == .color(faded),
            "the same answer through either spelling")
    }

    /// Every stop, not merely the two ends: a three-stop ramp faded halfway is
    /// still a three-stop ramp, and the middle one moves with the others.
    @Test("A gradient at opacity moves every stop")
    func opacityReachesEveryStop() {
        let values = environment()
        let stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255)]
        let faded = Gradient(colors: stops).opacity(0.25).paint(in: values)
        guard case .gradient(let ramp) = faded else {
            Issue.record("a faded gradient stopped being one: \(faded)")
            return
        }
        #expect(ramp.gradient.stops.count == 3)
        for (stop, original) in zip(ramp.gradient.stops, stops) {
            #expect(stop.color == original.opacity(0.25))
            #expect(stop.color.value == original.value, "the hue is untouched")
        }
    }

    /// **A semantic colour's own components survive a fade now.**
    ///
    /// `Color.paint(in:)` resolves a semantic colour against the palette — that is
    /// its job and it happens per frame, so a theme change is still followed. What
    /// changed is what the fade then does with the answer.
    ///
    /// It used to MIX the palette's accent toward the palette's background and
    /// hand back the blend, so the accent was gone: nothing downstream could tell
    /// a 40% accent from the particular greenish grey it had become. Now the
    /// accent's own components come through untouched with the alpha alongside
    /// them, and the compositor decides what 40% of it looks like over whatever is
    /// actually behind the cell.
    ///
    /// (The fade had to resolve, before: `Color.opacity(_:over:)` cannot mix a
    /// colour it has no components for, so `.palette.accent.opacity(0.4)` would
    /// otherwise have been a silent no-op.)
    @Test("Opacity leaves a semantic colour's components unmixed")
    func opacityKeepsSemanticColours() {
        let values = environment()
        let faded = AnyShapeStyle(Color.palette.accent).opacity(0.4).paint(in: values)
        let accent = values.palette.accent
        #expect(faded.representative.value == accent.value, "the accent itself: \(faded)")
        #expect(faded.representative.alpha == 102, "carrying 40%")
        #expect(
            faded != .color(accent.opacity(0.4, over: values.palette.background)),
            "and specifically NOT mixed toward the background")
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
