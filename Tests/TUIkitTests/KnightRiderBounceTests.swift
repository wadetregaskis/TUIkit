//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KnightRiderBounceTests.swift
//
//  The indeterminate bar's knightRider motion: a lead that bounces at a constant
//  speed, and a tail that fades by how long ago the lead was there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Reported by the owner: the lead should bounce between the ends at a uniform speed,
/// with a tail that FOLLOWS it — so when it bounces back it runs over its fading tail,
/// re-lighting those cells. The trail was laid out by direction and had no memory: at
/// each turn the lead stood alone, and the tail then appeared whole on the other side.
@MainActor
@Suite("knightRider bounces and re-lights its tail")
struct KnightRiderBounceTests {

    /// Five cells, a three-cell tail, a four-second period: eight steps of half a second.
    private let style = IndeterminateStyle.custom(
        IndeterminateConfiguration(motion: .knightRider, fill: "●", background: "·", period: 4, extent: 0.6))

    /// Which cells are lit `step` steps into the bounce, a hundredth into the step.
    private func lit(atStep step: Int) -> String {
        IndeterminateRenderer.render(
            width: 5, style: style, fillColor: .green, backgroundColor: .black, accentColor: .white,
            elapsed: Double(step) * 0.5 + 0.01, palette: SystemPalette(.green)
        ).text.stripped
    }

    /// At the far end the lead has just laid its tail down behind it — the lead is not
    /// alone, which is what the direction-based trail drew on the frame it turned.
    @Test("At the far end the lead has its tail behind it")
    func farEndKeepsTheTail() {
        #expect(lit(atStep: 4) == "··●●●", "\(lit(atStep: 4))")
    }

    /// One step after turning, the lead is back over the cell it just left: that cell is
    /// the lead again, the end cell is one step old, and the cell ahead of the lead —
    /// which the lead has not re-reached — is dark.
    @Test("Turning back, the lead runs over its own tail")
    func turningRelightsTheTail() {
        #expect(lit(atStep: 5) == "···●●", "\(lit(atStep: 5))")
    }

    /// Back at the near end, the tail left by the return pass is behind the lead, to its
    /// right.
    @Test("At the near end the returning tail follows the lead")
    func nearEndKeepsTheTail() {
        #expect(lit(atStep: 0) == "●●●··", "\(lit(atStep: 0))")
    }

    /// Uniform speed, read off the rendered bar alone: with a two-cell memory the lit
    /// pair is always the lead and the cell it stood on one step before, so the pairs
    /// trace the walk — out along 0…4 and back along 3…1, one cell a step, each end
    /// stood on once. The direction-based trail lit a single cell here.
    @Test("The lead walks one cell per step, standing on each end once")
    func leadWalksUniformly() {
        let pair = IndeterminateStyle.custom(
            IndeterminateConfiguration(motion: .knightRider, fill: "●", background: "·", period: 4, extent: 0.1))
        let walk = (0..<8).map { step in
            IndeterminateRenderer.render(
                width: 5, style: pair, fillColor: .green, backgroundColor: .black, accentColor: .white,
                elapsed: Double(step) * 0.5 + 0.01, palette: SystemPalette(.green)
            ).text.stripped
        }
        #expect(walk == ["●●···", "●●···", "·●●··", "··●●·", "···●●", "···●●", "··●●·", "·●●··"], "\(walk)")
    }
}
