//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorEffectTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Colour effects")
struct ColorEffectTests {

    private var context: RenderContext {
        makeRenderContext(width: 12, height: 3)
    }

    /// The RGB the rendered line names, for a view drawn in a known colour.
    private func drawn<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: context).lines.first ?? ""
    }

    @Test("Brightness adds to every channel")
    func brightnessAdds() {
        let base = Text("ab").foregroundStyle(Color.rgb(100, 100, 100))
        #expect(drawn(base.brightness(0)) == drawn(base), "zero must be the identity")
        #expect(drawn(base.brightness(0.2)).contains("151;151;151"))
        #expect(drawn(base.brightness(1)).contains("255;255;255"), "it must clamp, not wrap")
        #expect(drawn(base.brightness(-1)).contains("0;0;0"))
    }

    @Test("Contrast pushes away from mid-grey")
    func contrastPushes() {
        let base = Text("ab").foregroundStyle(Color.rgb(160, 160, 160))
        #expect(drawn(base.contrast(1)) == drawn(base), "one must be the identity")
        // 160 is 32.5 above the midpoint; doubling that gives 192.5 → 193.
        #expect(drawn(base.contrast(2)).contains("193;193;193"))
        #expect(drawn(base.contrast(0)).contains("128;128;128"), "zero is flat mid-grey")
    }

    @Test("Grayscale and saturation are the same dial from opposite ends")
    func grayscaleIsInverseSaturation() {
        let base = Text("ab").foregroundStyle(Color.rgb(200, 40, 40))
        #expect(drawn(base.grayscale(0)) == drawn(base))
        #expect(drawn(base.saturation(1)) == drawn(base))
        #expect(drawn(base.grayscale(1)) == drawn(base.saturation(0)))
        #expect(drawn(base.grayscale(0.25)) == drawn(base.saturation(0.75)))
        // Fully grey means all three channels agree, whatever the luminance
        // rounds to.
        let grey = drawn(base.grayscale(1))
        let channels = Self.foregroundChannels(grey)
        #expect(channels?.count == 3, "no truecolor foreground in \(grey.debugDescription)")
        #expect(Set(channels ?? []).count == 1, "not a grey: \(String(describing: channels))")
    }

    /// The `r;g;b` of the first truecolor foreground a line names.
    private static func foregroundChannels(_ line: String) -> [Int]? {
        guard let range = line.range(of: "38;2;") else { return nil }
        let rest = line[range.upperBound...].prefix { $0.isNumber || $0 == ";" }
        return rest.split(separator: ";").compactMap { Int($0) }
    }

    @Test("Inverting twice is the identity")
    func invertRoundTrips() {
        let base = Text("ab").foregroundStyle(Color.rgb(200, 40, 90))
        #expect(drawn(base.colorInvert()).contains("55;215;165"))
        #expect(drawn(base.colorInvert().colorInvert()) == drawn(base))
    }

    @Test("Multiplying by white changes nothing, by black removes everything")
    func multiplyTints() {
        let base = Text("ab").foregroundStyle(Color.rgb(200, 100, 50))
        #expect(drawn(base.colorMultiply(.white)) == drawn(base))
        #expect(drawn(base.colorMultiply(.rgb(0, 0, 0))).contains("0;0;0"))
        // Keeping only the red channel.
        #expect(drawn(base.colorMultiply(.rgb(255, 0, 0))).contains("200;0;0"))
    }

    @Test("Hue rotation moves the hue and leaves the rest")
    func hueRotates() {
        let base = Text("ab").foregroundStyle(Color.rgb(255, 0, 0))
        #expect(drawn(base.hueRotation(.zero)) == drawn(base))
        // Red at 0°, rotated a third of the way round, is green.
        #expect(drawn(base.hueRotation(.degrees(120))).contains("0;255;0"))
        #expect(drawn(base.hueRotation(.degrees(240))).contains("0;0;255"))
    }

    @Test("A backwards hue rotation lands where the forwards one does")
    func hueRotatesBackwards() {
        // Not the pure red above: at saturation 100 / lightness 50 HSL's
        // `luminance` term is 0, so a channel that fell into the wrong segment
        // clamped to the same 0 the right one gives, and `hueRotates` stayed
        // green while `.degrees(-300)` drew this pale red's blue as 1, not 128.
        // Bytes are pinned rather than the two lines compared: `Angle` stores
        // radians, so -300 comes back a ULP off, and every channel here sits
        // well clear of a rounding boundary either way.
        let base = Text("ab").foregroundStyle(Color.rgb(255, 128, 128))
        let forwards = drawn(base.hueRotation(.degrees(60)))
        let backwards = drawn(base.hueRotation(.degrees(-300)))
        #expect(forwards.contains("255;255;128"), "\(forwards.debugDescription)")
        #expect(backwards.contains("255;255;128"), "\(backwards.debugDescription)")
    }

    @Test("An effect leaves the cells exactly where they were")
    func effectsAreSizeNeutral() {
        // Every one of these rewrites colours in place. A view that changed
        // size under a colour effect would reflow the page around it.
        let base = Text("hello").padding(1)
        let plain = renderToBuffer(base, context: context)
        for view in [
            AnyView(base.grayscale(1)), AnyView(base.brightness(0.5)),
            AnyView(base.contrast(3)), AnyView(base.colorInvert()),
            AnyView(base.hueRotation(.degrees(90))),
        ] {
            let effected = renderToBuffer(view, context: context)
            #expect(effected.lines.map(\.stripped) == plain.lines.map(\.stripped))
        }
    }

    @Test("An effect animates its amount")
    func effectsAnimate() {
        var context = makeRenderContext(width: 12, height: 3)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))

        func draw(_ amount: Double, atMillis millis: Int) -> String {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(
                Text("ab").foregroundStyle(Color.rgb(200, 40, 40)).grayscale(amount),
                context: context
            ).lines.first ?? ""
        }

        _ = draw(0, atMillis: 0)
        let start = draw(1, atMillis: 0)
        let half = draw(1, atMillis: 500)
        let end = draw(1, atMillis: 1000)
        #expect(start.contains("200;40;40"), "the frame the change lands on has not moved")
        #expect(half != start && half != end, "it jumped instead of ramping")
    }

    @Test("Angle converts both ways and animates")
    func angleBasics() {
        #expect(Angle.degrees(180).radians == .pi)
        #expect(Angle.radians(.pi).degrees == 180)
        #expect(Angle.zero < Angle.degrees(1))
        // Written as the animator writes it: read both ends, walk half way.
        var angle = Angle.zero
        let start: Double = angle.animatableData
        let end: Double = Angle.degrees(90).animatableData
        angle.animatableData = start + (end - start) * 0.5
        #expect(abs(angle.degrees - 45) < 1e-9)
    }

    /// `Angle` is `Codable`, as SwiftUI's is — so source that persists one
    /// compiles. Round-tripped rather than compared against a literal payload:
    /// the encoded shape is each framework's own business, and pinning JSON
    /// here would be pinning a synthesized detail.
    @Test("An Angle survives a Codable round trip")
    func angleRoundTrips() throws {
        let original = Angle(degrees: 137.5)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Angle.self, from: data)
        #expect(restored == original)
        #expect(abs(restored.degrees - 137.5) < 1e-9)
    }
}
