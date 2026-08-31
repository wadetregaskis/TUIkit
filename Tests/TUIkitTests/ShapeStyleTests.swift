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
        #expect(gradient.paint(in: environment()) == .linear(gradient, from: .top, to: .bottom))
    }

    @Test("A LinearGradient keeps the direction it was given")
    func linearKeepsItsAxis() {
        let gradient = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        let style = LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
        #expect(style.paint(in: environment()) == .linear(gradient, from: .leading, to: .trailing))
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
                .paint(in: values) == .linear(gradient, from: .leading, to: .trailing))
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
        #expect(Paint.linear(gradient, from: .top, to: .bottom) != .linear(gradient, from: .leading, to: .trailing))
    }

    @Test("A paint collapses to one colour where a gradient cannot go")
    func collapsing() {
        #expect(Paint.color(.rgb(4, 5, 6)).representative == .rgb(4, 5, 6))
        #expect(Paint.color(.rgb(4, 5, 6)).solid == .rgb(4, 5, 6))
        let gradient = Gradient(colors: [.rgb(0, 0, 0), .rgb(255, 255, 255)])
        let ramp = Paint.linear(gradient, from: .top, to: .bottom)
        #expect(ramp.solid == nil, "a ramp is not a solid colour")
        #expect(ramp.representative == gradient.color(at: 0.5))
    }
}
