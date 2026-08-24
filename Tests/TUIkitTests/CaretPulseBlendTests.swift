//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CaretPulseBlendTests.swift
//
//  A pulsing caret dims toward the field it sits in, not toward black.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("A pulsing caret dims toward its field")
struct CaretPulseBlendTests {

    /// The dim end of the cycle, taken from the whole cycle rather than a
    /// clock: `computeCursorCycle` builds every tick up front.
    private func dimmestState(base: Color, over surface: Color) -> Color? {
        let cycle = TextFieldContentRenderer.computeCursorCycle(
            baseColor: base, over: surface, animation: .pulse, speed: .regular,
            cursorTimer: nil)
        return cycle.states
            .map(\.color)
            .min { ($0.relativeLuminance ?? 0) < ($1.relativeLuminance ?? 0) }
    }

    /// On a LIGHT field, a caret fading toward black gets *darker* as it dims —
    /// so the dim end reads as a heavier mark than the bright end, which is the
    /// opposite of what a pulse is for. Blended toward the field instead, every
    /// state of the cycle sits between the two colours it is interpolating.
    @Test("On a light field the pulse never goes darker than the caret itself")
    func lightFieldPulseStaysBetweenTheEnds() throws {
        let field = Color.rgb(240, 240, 235)
        let caret = Color.rgb(20, 60, 140)
        let dimmest = try #require(dimmestState(base: caret, over: field))

        let fieldLuminance = try #require(field.relativeLuminance)
        let caretLuminance = try #require(caret.relativeLuminance)
        let dimLuminance = try #require(dimmest.relativeLuminance)

        #expect(
            dimLuminance >= caretLuminance,
            "dim \(dimLuminance) is darker than the caret \(caretLuminance)")
        #expect(
            dimLuminance <= fieldLuminance,
            "dim \(dimLuminance) is lighter than the field \(fieldLuminance)")
    }

    /// The same rule on a dark field, where fading toward black happens to look
    /// right — which is why this went unnoticed. The assertion is the same one.
    @Test("On a dark field the pulse stays between the field and the caret")
    func darkFieldPulseStaysBetweenTheEnds() throws {
        let field = Color.rgb(12, 14, 12)
        let caret = Color.rgb(80, 240, 120)
        let dimmest = try #require(dimmestState(base: caret, over: field))

        let fieldLuminance = try #require(field.relativeLuminance)
        let caretLuminance = try #require(caret.relativeLuminance)
        let dimLuminance = try #require(dimmest.relativeLuminance)

        #expect(dimLuminance >= fieldLuminance, "dim is not darker than the field")
        #expect(dimLuminance <= caretLuminance, "dim is not brighter than the caret")
    }
}
