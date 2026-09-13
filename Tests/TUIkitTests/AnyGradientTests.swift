//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyGradientTests.swift
//
//  `AnyGradient`, `Color.gradient` and `Color.mix(with:by:)` — the three
//  SwiftUI spellings that turn a colour into a ramp, or a pair of colours into
//  a colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("AnyGradient")
struct AnyGradientTests {

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        return environment
    }

    @Test("An AnyGradient paints as a top-to-bottom ramp")
    func paintsTopToBottom() {
        let paint = AnyGradient(Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)]))
            .paint(in: environment())
        guard case .gradient(let ramp) = paint else {
            Issue.record("not a gradient: \(paint)")
            return
        }
        #expect(ramp.geometry == .linear(from: .top, to: .bottom), "\(ramp.geometry)")
        #expect(ramp.gradient.stops.count == 2)
    }

    @Test("Color.gradient runs from a lighter version of the colour to the colour")
    func derivedFromAColour() {
        let base = Color.rgb(51, 102, 204)
        let stops = base.gradient.gradient(in: environment()).stops
        #expect(stops.count == 2, "\(stops)")
        #expect(stops.last?.color == base, "the ramp must end at the colour itself: \(stops)")

        guard let top = stops.first?.color.rgbComponents else {
            Issue.record("no top colour: \(stops)")
            return
        }
        let (baseHue, baseSaturation, baseLightness) = Color.rgbToHSL(
            red: 51, green: 102, blue: 204)
        let (hue, saturation, lightness) = Color.rgbToHSL(
            red: top.red, green: top.green, blue: top.blue)
        // Hue and saturation held, lightness up by 15 — see `Color.gradient`
        // for what SwiftUI's own renderer answered for this colour.
        #expect(abs(hue - baseHue) < 1, "hue moved: \(hue) vs \(baseHue)")
        #expect(abs(saturation - baseSaturation) < 1, "saturation moved: \(saturation)")
        #expect(abs(lightness - (baseLightness + 15)) < 1, "lightness: \(lightness)")
    }

    @Test("A colour at full lightness has nowhere to go, and stays")
    func whiteDerivesToItself() {
        let stops = Color.rgb(255, 255, 255).gradient.gradient(in: environment()).stops
        #expect(stops.first?.color == .rgb(255, 255, 255), "\(stops)")
        #expect(stops.last?.color == .rgb(255, 255, 255), "\(stops)")
    }

    /// A palette role is a reference, not a colour: there is nothing to lighten
    /// until something paints. The derivation therefore happens at paint time,
    /// and a semantic base must come out as real ink rather than as itself.
    @Test("A palette role derives against the palette that paints it")
    func semanticBaseResolvesAtPaintTime() {
        var green = environment()
        green.palette = SystemPalette.green
        let stops = Color.palette.accent.gradient.gradient(in: green).stops
        #expect(stops.count == 2, "\(stops)")
        #expect(
            stops.allSatisfy { $0.color.rgbComponents != nil },
            "a semantic colour survived into the ramp: \(stops)")
        #expect(stops.last?.color == green.palette.accent.resolve(with: green.palette), "\(stops)")
    }

    /// A faded colour's gradient is faded at BOTH ends. The lighter stop is rebuilt
    /// through `Color.hsl`, which builds at alpha 255, beside a bottom stop that is
    /// the colour itself — so without the carry `Color.blue.opacity(0.5).gradient`
    /// ran from solid to half-faded, and text with the height to show the ramp
    /// faded in down its rows. Asked of a concrete base and of a palette role,
    /// because the role reaches the stop through `resolve(with:)`, which composes.
    @Test("A faded colour's gradient carries the alpha to both stops")
    func fadedBaseCarriesAlphaToBothStops() {
        let concrete = Color.rgb(51, 102, 204).opacity(0.5).gradient.gradient(in: environment()).stops
        let concreteAlphas = concrete.map(\.color.alpha)
        #expect(concreteAlphas == [128, 128], "a faded concrete colour: \(concrete)")

        let role = Color.palette.accent.opacity(0.5).gradient.gradient(in: environment()).stops
        let roleAlphas = role.map(\.color.alpha)
        #expect(roleAlphas == [128, 128], "a faded palette role: \(role)")
    }

    /// `mix` is the same interpolation a gradient does — asked for one point
    /// rather than a whole ramp — once the two are told to use the same space.
    @Test("Color.mix in .device is a two-stop device gradient at the fraction")
    func mixMatchesTheGradient() {
        let red = Color.rgb(255, 0, 0)
        let blue = Color.rgb(0, 0, 255)
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            #expect(
                red.mix(with: blue, by: fraction, in: .device)
                    == Gradient(colors: [red, blue]).color(at: fraction),
                "at \(fraction)")
            #expect(
                red.mix(with: blue, by: fraction)
                    == Gradient(colors: [red, blue], colorSpace: .perceptual)
                    .color(at: fraction),
                "the default is perceptual, at \(fraction)")
        }
    }

    /// SwiftUI's own asymmetry, kept rather than tidied: a bare `Gradient`
    /// interpolates in `.device` and `mix` mixes in `.perceptual`, so the two
    /// disagree unless told otherwise. Pinned because it looks like a bug.
    @Test("mix and a bare gradient disagree by default, and that is SwiftUI's")
    func theDefaultsDiffer() {
        let red = Color.rgb(255, 0, 0)
        let blue = Color.rgb(0, 0, 255)
        #expect(red.mix(with: blue, by: 0.5, in: .device) == .rgb(128, 0, 128))
        #expect(red.mix(with: blue, by: 0.5) == .rgb(140, 83, 162))
        #expect(Gradient(colors: [red, blue]).color(at: 0.5) == .rgb(128, 0, 128))
    }

    @Test("Color.mix clamps outside 0…1")
    func mixClamps() {
        let red = Color.rgb(255, 0, 0)
        let blue = Color.rgb(0, 0, 255)
        #expect(red.mix(with: blue, by: -1) == red)
        #expect(red.mix(with: blue, by: 2) == blue)
    }

    /// The point of the whole thing: `.foregroundStyle(.blue.gradient)` has to
    /// compile against the generic `ShapeStyle` overload and paint a ramp.
    @Test("A derived gradient goes where a style goes")
    func usableAsAStyle() {
        var environment = environment()
        environment.focusManager = FocusManager()
        let tui = TUIContext()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4, environment: environment, tuiContext: tui)
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AA")
                Text(verbatim: "BB")
            }
            .foregroundStyle(Color.rgb(0, 0, 255).gradient)
            .gradientExtent(.subtree),
            context: context
        ).lines
        // Two rows of a two-stop ramp: the lighter end, then the colour.
        #expect(lines[0].contains("38;2;"), "no ink: \(lines)")
        #expect(lines[1].contains("38;2;0;0;255"), "the ramp must end at the colour: \(lines)")
        #expect(!lines[0].contains("38;2;0;0;255"), "both rows the same: \(lines)")
    }
}
