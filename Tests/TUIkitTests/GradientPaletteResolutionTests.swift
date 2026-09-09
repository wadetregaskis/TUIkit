//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientPaletteResolutionTests.swift
//
//  A gradient stop may name a palette role. Every path that turns one into ink
//  has to look the role up first — a role has no channels, and the ANSI layer
//  traps rather than guess.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Gradient stops that name a palette role")
struct GradientPaletteResolutionTests {

    /// `SystemPalette.green`'s accent, which is what every ramp below starts at
    /// once the role has been looked up.
    private var accent: Color { SystemPalette.green.accent }
    private let blue = Color.rgb(0, 0, 255)

    private var ramp: Gradient { Gradient(colors: [.accentColor, blue]) }

    private func context(width: Int = 12) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: 4, environment: environment, tuiContext: tui)
    }

    /// Every truecolor foreground of a line, in cell order.
    private func inks(_ line: String) -> [String] {
        var found: [String] = []
        var rest = Substring(line)
        while let start = rest.range(of: "\u{1B}[38;2;") {
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: "m") else { break }
            found.append(String(rest[rest.startIndex..<end]))
            rest = rest[rest.index(after: end)...]
        }
        return found
    }

    private func backgrounds(_ line: String) -> [String] {
        var found: [String] = []
        var rest = Substring(line)
        while let start = rest.range(of: "\u{1B}[48;2;") {
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: "m") else { break }
            found.append(String(rest[rest.startIndex..<end]))
            rest = rest[rest.index(after: end)...]
        }
        return found
    }

    private var accentCodes: String {
        guard let rgb = accent.rgbComponents else { return "?" }
        return "\(rgb.red);\(rgb.green);\(rgb.blue)"
    }

    // MARK: - The styles

    /// The one that used to be a hard crash: `Color.foregroundCodes()` traps on
    /// an unresolved role, and nothing on the foreground path resolved one.
    @Test("A role in a foreground ramp paints, starting at the palette's colour")
    func foregroundRamp() {
        let line = renderToBuffer(
            Text("abcdefghijkl")
                .foregroundStyle(
                    LinearGradient(gradient: ramp, startPoint: .leading, endPoint: .trailing)),
            context: context()
        ).lines.first ?? ""
        let painted = inks(line)
        #expect(painted.first == accentCodes, "\(painted)")
        #expect(painted.last == "0;0;255", "\(painted)")
    }

    /// The background path always resolved — it is the asymmetry that made the
    /// foreground hole visible, so it is worth a test that says so.
    @Test("A role in a background ramp paints")
    func backgroundRamp() {
        let line = renderToBuffer(
            Text("abcdefghijkl")
                .background(
                    LinearGradient(gradient: ramp, startPoint: .leading, endPoint: .trailing)),
            context: context()
        ).lines.first ?? ""
        let painted = backgrounds(line)
        #expect(painted.first == accentCodes, "\(painted)")
        #expect(painted.last == "0;0;255", "\(painted)")
    }

    /// A control style never goes through `ShapeStyle.paint(in:)` — it is read
    /// out of the environment by the control that draws it — so the resolve
    /// happens at the renderer's door instead.
    @Test("A role in a track's ramp paints")
    func trackRamp() {
        let line = renderToBuffer(
            ProgressView(value: 1).progressViewStyle(.shadeRamp(gradient: ramp)).frame(width: 12),
            context: context()
        ).lines.first ?? ""
        let painted = inks(line)
        #expect(painted.first == accentCodes, "\(painted)")
        #expect(painted.last == "0;0;255", "\(painted)")
    }

    /// This one did not crash — it silently substituted the built-in rainbow,
    /// because the motion filtered its stops down to the ones that had channels
    /// and fell back when fewer than two survived.
    @Test("A role in an indeterminate motion's ramp paints, and is not the built-in rainbow")
    func indeterminateRamp() {
        let line = renderToBuffer(
            ProgressView().indeterminateStyle(.gradient(ramp)).frame(width: 12),
            context: context()
        ).lines.first ?? ""
        let painted = inks(line)
        #expect(painted.first == accentCodes, "\(painted)")
        #expect(!painted.contains("180;30;80"), "fell back to the rainbow: \(painted)")
    }

    /// Every geometry, since each has its own `paint(in:)`.
    @Test("Every gradient geometry resolves its stops")
    func everyGeometry() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green

        func stops(of style: some ShapeStyle) -> [Color] {
            guard case .gradient(let painted) = style.paint(in: environment) else { return [] }
            return painted.gradient.stops.map(\.color)
        }

        let expected = [accent, blue]
        #expect(stops(of: ramp) == expected, "bare Gradient")
        #expect(
            stops(of: LinearGradient(gradient: ramp, startPoint: .top, endPoint: .bottom))
                == expected, "linear")
        #expect(
            stops(of: RadialGradient(gradient: ramp, center: .center, startRadius: 0, endRadius: 4)) == expected,
            "radial")
        #expect(stops(of: AngularGradient(gradient: ramp, center: .center)) == expected, "angular")
        #expect(stops(of: EllipticalGradient(gradient: ramp)) == expected, "elliptical")
        #expect(stops(of: AnyGradient(ramp)) == expected, "AnyGradient")
        // …and through the two wrappers, which resolve their base and so were
        // never part of the bug — pinned so they cannot become part of it.
        guard case .gradient(let faded) = ramp.opacity(0.5).paint(in: environment) else {
            Issue.record("opacity did not stay a gradient")
            return
        }
        #expect(faded.gradient.stops.allSatisfy { $0.color.rgbComponents != nil })
    }

    /// A lone `Color` goes through the same door, so a `Paint` is concrete by
    /// construction whichever style built it.
    @Test("A role used as a plain style resolves too")
    func plainColour() {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        #expect(Color.accentColor.paint(in: environment) == .color(accent))
    }

    /// `resolvingStops` returns the same value when there is nothing to look
    /// up, so the common ramp does not pay for a rebuild.
    @Test("A ramp with no roles in it is returned unchanged")
    func concreteRampIsUntouched() {
        let concrete = Gradient(colors: [.rgb(1, 2, 3), blue], colorSpace: .perceptual)
        let resolved = concrete.resolvingStops(with: SystemPalette.green)
        #expect(resolved == concrete)
        #expect(resolved.colorSpace == .perceptual, "and the rest of the ramp survives")
    }
}
