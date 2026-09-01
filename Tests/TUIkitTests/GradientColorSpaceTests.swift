//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientColorSpaceTests.swift
//
//  `Gradient.ColorSpace` — which space the stops are interpolated in, and the
//  two artefacts that made it worth having.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Gradient colour space")
struct GradientColorSpaceTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)
    private let yellow = Color.rgb(255, 255, 0)

    /// OKLab lightness, for asserting about how a ramp READS rather than what
    /// bytes it happens to contain.
    private func lightness(_ colour: Color) -> Double {
        guard let rgb = colour.rgbComponents else { return 0 }
        return Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue).l
    }

    private func chroma(_ colour: Color) -> Double {
        guard let rgb = colour.rgbComponents else { return 0 }
        let lab = Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
        return (lab.a * lab.a + lab.b * lab.b).squareRoot()
    }

    // MARK: - The transform

    /// The inverse has to be the inverse. Every colour of the 6×6×6 cube's
    /// spacing, out through OKLab and back.
    @Test("OKLab round-trips to the byte")
    func roundTrips() {
        var worst = 0
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let lab = Color.oklab(
                        red: UInt8(red), green: UInt8(green), blue: UInt8(blue))
                    let back = Color.fromOKLab(l: lab.l, a: lab.a, b: lab.b)
                    worst = max(
                        worst,
                        max(
                            abs(Int(back.red) - red),
                            max(abs(Int(back.green) - green), abs(Int(back.blue) - blue))))
                }
            }
        }
        #expect(worst == 0, "round-trip error of \(worst)")
    }

    // MARK: - What it fixes

    /// Red to blue in encoded sRGB is DARKER in the middle than at either end —
    /// the muddy middle. Perceptually it descends once and stops.
    @Test("A device ramp dips darker than both its ends; a perceptual one does not")
    func theMuddyMiddle() {
        let device = Gradient(colors: [red, blue])
        let perceptual = Gradient(colors: [red, blue], colorSpace: .perceptual)
        let ends = min(lightness(red), lightness(blue))

        let deviceDip = (1...3).map { lightness(device.color(at: Double($0) / 4)) }.min() ?? 0
        #expect(deviceDip < ends, "the device ramp did not dip: \(deviceDip) vs \(ends)")

        let perceptualDip =
            (1...3).map { lightness(perceptual.color(at: Double($0) / 4)) }.min() ?? 0
        #expect(
            perceptualDip >= ends - 0.001,
            "the perceptual ramp dipped below its ends: \(perceptualDip) vs \(ends)")
    }

    /// The textbook case: blue to yellow through encoded sRGB passes through
    /// EXACTLY zero chroma — a grey — because the two colours are opposite on
    /// both axes at once.
    @Test("A device blue-to-yellow ramp goes grey in the middle; a perceptual one keeps its hue")
    func theGreyMidpoint() {
        let device = Gradient(colors: [blue, yellow])
        // r == g == b, so the colour has no chroma by definition; the measured
        // value is 2.2e-08 rather than a hard zero, which is the transform's
        // own arithmetic and not a property of the colour.
        #expect(device.color(at: 0.5) == .rgb(128, 128, 128), "\(device.color(at: 0.5))")
        #expect(chroma(device.color(at: 0.5)) < 1e-6)

        let perceptual = Gradient(colors: [blue, yellow], colorSpace: .perceptual)
        #expect(
            chroma(perceptual.color(at: 0.5)) > 0.05,
            "the perceptual midpoint went grey too: \(perceptual.color(at: 0.5))")
    }

    // MARK: - The API

    /// `.device` must be byte-for-byte what the framework did before there was
    /// a choice — every ramp that does not ask for a space is this one.
    @Test("The default is device, and device is the old interpolation exactly")
    func deviceIsTheDefaultAndUnchanged() {
        let ramp = Gradient(colors: [red, blue])
        #expect(ramp.colorSpace == .device)
        for step in 0...8 {
            let phase = Double(step) / 8
            #expect(
                ramp.color(at: phase) == Color.lerp(red, blue, phase: phase),
                "at \(phase)")
        }
    }

    /// SwiftUI's spelling returns an `AnyGradient`, because in SwiftUI that is
    /// the only thing that can carry a space. Ours carries it on the `Gradient`
    /// too, so a `LinearGradient` can be perceptual — which SwiftUI's cannot.
    @Test("colorSpace(_:) erases to AnyGradient, and the ramp keeps the space")
    func theSwiftUISpelling() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green

        let erased: AnyGradient = Gradient(colors: [red, blue]).colorSpace(.perceptual)
        #expect(erased.gradient(in: environment).colorSpace == .perceptual)
        #expect(erased.gradient(in: environment).color(at: 0.5) == .rgb(140, 83, 162))

        // …and again on an AnyGradient, which is SwiftUI's other spelling.
        #expect(erased.colorSpace(.device).gradient(in: environment).colorSpace == .device)
    }

    /// The whole reason the space is stored on `Gradient`: a directional
    /// gradient is what a terminal actually paints, and SwiftUI gives it no way
    /// to carry one.
    @Test("A LinearGradient honours the space its Gradient carries")
    func directionalGradientsHonourIt() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green

        let ramp = LinearGradient(
            gradient: Gradient(colors: [red, blue], colorSpace: .perceptual),
            startPoint: .top, endPoint: .bottom)
        guard case .gradient(let painted) = ramp.paint(in: environment) else {
            Issue.record("not a gradient")
            return
        }
        #expect(painted.gradient.colorSpace == .perceptual)
        #expect(painted.gradient.color(at: 0.5) == .rgb(140, 83, 162))
    }

    /// A colour derived from another (`Color.gradient`) can be told a space
    /// too, even though it has no stops until something paints it.
    @Test("A derived gradient takes a colour space")
    func derivedGradientsTakeASpace() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        let derived = Color.rgb(0, 0, 255).gradient.colorSpace(.perceptual)
        #expect(derived.gradient(in: environment).colorSpace == .perceptual)
    }

    // MARK: - Everything that rebuilds a ramp

    /// Anything that replaces a ramp's STOPS must keep the rest of the ramp.
    /// Two places did not, and both were found by a reviewer rather than by
    /// reasoning: an animating perceptual gradient blended in `.device` for the
    /// length of the animation and snapped back at the end, and `.opacity(_:)`
    /// on one dropped the space outright.
    @Test("A ramp keeps its space through the animator")
    func animationKeepsTheSpace() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        let tui = TUIContext()
        environment.applyRuntimeServices(from: tui)
        environment.canAnimate = true
        environment.transaction = Transaction(animation: .linear(duration: 1))
        let context = RenderContext(
            availableWidth: 10, availableHeight: 3, environment: environment, tuiContext: tui)

        let ramp = Paint.gradient(
            GradientPaint(
                Gradient(colors: [red, blue], colorSpace: .perceptual),
                .linear(from: .top, to: .bottom)))
        guard case .gradient(let moved) = PaintAnimation.resolving(
            ramp, owner: Self.self, context: context)
        else {
            Issue.record("not a gradient")
            return
        }
        #expect(moved.gradient.colorSpace == .perceptual)
    }

    @Test("A ramp keeps its space through .opacity(_:)")
    func opacityKeepsTheSpace() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        // Through a generic function, because the gradients are BOTH a
        // `ShapeStyle` and a `View` and both protocols have `.opacity(_:)` —
        // written directly on the concrete type the call is ambiguous. In here
        // `style` is only a `ShapeStyle`, so there is one `opacity` to find.
        func faded<S: ShapeStyle>(_ style: S) -> Paint {
            style.opacity(0.5).paint(in: environment)
        }
        let ramped = faded(
            LinearGradient(
                gradient: Gradient(colors: [red, blue], colorSpace: .perceptual),
                startPoint: .top, endPoint: .bottom))
        guard case .gradient(let ramp) = ramped else {
            Issue.record("not a gradient")
            return
        }
        #expect(ramp.gradient.colorSpace == .perceptual)
    }

    /// Every edit the gradient panel makes rebuilt the ramp, and so reset its
    /// space. All of them go through ``Gradient/withStops(_:)`` now; this walks
    /// the ones a user can reach.
    @Test("Editing a ramp in the panel keeps its colour space")
    func panelEditsKeepTheSpace() {
        let perceptual = Gradient(
            stops: [
                Gradient.Stop(color: red, location: 0),
                Gradient.Stop(color: blue, location: 1),
            ],
            colorSpace: .perceptual)

        #expect(
            GradientEditorPanel.duplicatingStop(perceptual, at: 0).0.colorSpace == .perceptual,
            "duplicate")
        #expect(
            GradientEditorPanel.removingStop(perceptual, at: 1).0.colorSpace == .perceptual,
            "remove")
        #expect(
            GradientEditorPanel.movingStop(perceptual, at: 0, by: 1).0.colorSpace == .perceptual,
            "move")
        #expect(
            GradientEditorPanel.collapsedToSolid(perceptual, at: 0).colorSpace == .perceptual,
            "collapse to solid")
        // …and back out of solid, which is its own branch.
        let solid = GradientEditorPanel.collapsedToSolid(perceptual, at: 0)
        #expect(
            GradientEditorPanel.duplicatingStop(solid, at: 0).0.colorSpace == .perceptual,
            "expand from solid")
    }

    /// A chip is a library entry — colours and positions, from a format with
    /// nowhere to put a space — so applying one must not quietly re-blend the
    /// app's ramp.
    @Test("Applying a preset or recent keeps the edited ramp's colour space")
    func chipsKeepTheSpace() {
        let edited = Gradient(colors: [red, blue], colorSpace: .perceptual)
        let chip = Gradient(colors: [.rgb(1, 2, 3), .rgb(4, 5, 6)])
        let applied = GradientEditorPanel.applying(chip, to: edited)
        #expect(applied.stops.map(\.color) == chip.stops.map(\.color), "the colours change")
        #expect(applied.colorSpace == .perceptual, "the space does not")
    }

    /// `AnyGradient` is public and `Hashable`, so "no space asked for" and
    /// "the space it resolves to" have to be the same value.
    @Test("A derived gradient told its own default equals the untold one")
    func derivedDefaultIsNotADistinctValue() {
        let plain = Color.rgb(40, 90, 200).gradient
        let told = plain.colorSpace(.device)
        #expect(plain == told)
        #expect(plain.hashValue == told.hashValue)
        #expect(plain != plain.colorSpace(.perceptual), "and a real change still shows")

        let environment = EnvironmentValues()
        #expect(plain.gradient(in: environment).colorSpace == .device)
        #expect(plain.colorSpace(.perceptual).gradient(in: environment).colorSpace == .perceptual)
    }

    /// The space is part of what a gradient IS, so two ramps that differ only
    /// in it are different values — which is what keeps the render memo honest.
    @Test("Two ramps differing only in space are not equal")
    func theSpaceIsPartOfIdentity() {
        let device = Gradient(colors: [red, blue])
        let perceptual = Gradient(colors: [red, blue], colorSpace: .perceptual)
        #expect(device != perceptual)
        #expect(device.hashValue != perceptual.hashValue)
        #expect(Paint.gradient(GradientPaint(device, .linear(from: .top, to: .bottom)))
            != Paint.gradient(GradientPaint(perceptual, .linear(from: .top, to: .bottom))))
    }
}
