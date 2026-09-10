//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlphaRamps.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Alpha ramps

/// Translucent gradients — every ``RampSampler`` alpha shape at once, which
/// nothing else in this harness paints.
///
/// `gradients` covers the ramp's *colour* cost and every one of its ramps is
/// opaque, so the whole of `Documentation/Opacity as composition.md` §34 — a
/// ramp's alpha travelling as claims beside its bytes — was invisible to
/// `ab_bench.py`. That is the same hole `gradients` was written to fill for
/// gradients themselves, one layer down: a cost nothing measures is a cost
/// nobody can price, and §34.3 declined the per-cell shape on an *estimate*.
///
/// The four bands are the four shapes, and they cost different amounts because
/// the claim each owes is a different number of rectangles:
///
/// - **`uniform`** — every stop at one alpha. ONE rectangle over the block,
///   whatever its size. The cheap case, here so a regression that hits every
///   shape can be told from one that hits the expensive shapes only.
/// - **`perRow`** — a vertical ramp, which is what a scrim fading a list out at
///   the bottom is. One rectangle per row.
/// - **`perColumn`** — a horizontal ramp: a fade along a header or a bar, and
///   the commonest ramp anyone writes. One full-height strip per run of equal
///   alpha, so a smooth fade is a handful and not one per column.
/// - **`perCell`** — a diagonal linear ramp, and the three geometries with a
///   centre. The alpha changes along the row AND down the column, so no
///   rectangle spans more than a cell of it. This is the band the decline was
///   about, and the only one whose claim count grows with the AREA.
///
/// A `Table` under a diagonal ramp is its own band: a table's cells are painted
/// through the same `PaintRenderer.band` walk but their claims are assembled by
/// the row renderer, which is a second path over the same arithmetic.
///
/// Deterministic like every other scenario, and driven by the harness's tick so
/// the render memo cannot serve last frame's buffers: the tick rotates the
/// stops, exactly as `gradients` does.
enum AlphaRampsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "alpharamp",
        title: "Alpha ramps",
        blurb: "Translucent gradients in all four alpha shapes, as ink and as fills.",
        stresses:
            "claim derivation per cell · region carriage through composites · opacity resolution",
        make: { config in AnyView(AlphaRampsView(config: config)) }
    )
}

private struct AlphaRampsView: View {
    let config: StressConfig

    @Environment(StressClock.self) private var clock

    var body: some View {
        let rows = config.sized(120)
        let ramp = Self.ramp(rotatedBy: clock.tick)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.alpharamp.heading", rows)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Band 1: one alpha for the whole ramp — one rectangle.
                    band(rows / 4, seed: 1_001) {
                        LinearGradient(
                            gradient: Self.evenlyFaded(ramp), startPoint: .leading,
                            endPoint: .trailing)
                    }

                    // Band 2: a vertical ramp — one rectangle per row.
                    band(rows / 4, seed: 2_001) {
                        LinearGradient(gradient: ramp, startPoint: .top, endPoint: .bottom)
                    }

                    // Band 3: a horizontal ramp — one strip per run of equal alpha.
                    band(rows / 4, seed: 3_001) {
                        LinearGradient(gradient: ramp, startPoint: .leading, endPoint: .trailing)
                    }

                    // Band 4: the shapes whose alpha varies in BOTH directions.
                    band(rows / 4, seed: 4_001) {
                        LinearGradient(
                            gradient: ramp, startPoint: .topLeading, endPoint: .bottomTrailing)
                    }

                    // The same four as FILLS rather than ink: the claim is the
                    // FIELD channel and the bytes are a background, which is a
                    // different assembly in a different file.
                    ForEach(0..<config.sized(24), id: \.self) { index in
                        Text(Synth.slug(mix(config.seed, index &+ 9_001)))
                            .background(Self.fill(index, ramp: ramp))
                    }

                    // A block per geometry, where the alpha is per cell over an
                    // area rather than along a line of text.
                    ForEach(0..<config.sized(6), id: \.self) { index in
                        GeometryAlphaBand(ramp: ramp, index: index)
                    }

                    // And a table under the diagonal ramp — the row renderer's
                    // own copy of the per-cell walk.
                    Table(Self.tableRows(seed: config.seed, count: config.sized(40))) {
                        TableColumn("Name") { $0.name }
                        TableColumn("Status") { $0.status }
                    }
                    .foregroundStyle(
                        LinearGradient(
                            gradient: ramp, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
        }
    }

    /// One band of plain rows under `paint` as their ink.
    @ViewBuilder
    private func band<S: ShapeStyle>(
        _ rows: Int, seed offset: Int, paint: () -> S
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<max(1, rows), id: \.self) { index in
                Text(Synth.slug(mix(config.seed, index &+ offset)))
            }
        }
        .foregroundStyle(paint())
        .gradientExtent(.subtree)
    }

    /// Six stops, faded unevenly, so `alphaShape` cannot collapse the ramp to
    /// `uniform` and the alpha genuinely varies along it.
    private static func ramp(rotatedBy tick: Int) -> Gradient {
        let colours: [Color] = [
            .rgb(220, 60, 90).opacity(0.15), .rgb(230, 140, 50).opacity(0.4),
            .rgb(220, 210, 70).opacity(0.65), .rgb(70, 190, 110).opacity(0.85),
            .rgb(60, 140, 210).opacity(0.55), .rgb(140, 90, 210).opacity(0.25),
        ]
        let offset = tick % colours.count
        return Gradient(colors: Array(colours[offset...] + colours[..<offset]))
    }

    /// The same stops at ONE alpha — the `uniform` shape, which `Color.lerp`
    /// gives whenever the endpoints agree about it.
    private static func evenlyFaded(_ ramp: Gradient) -> Gradient {
        Gradient(colors: ramp.stops.map { $0.color.opacity(0.5) })
    }

    /// A fill per row, cycling the four shapes so one page pays for all of them.
    private static func fill(_ index: Int, ramp: Gradient) -> AnyShapeStyle {
        switch index % 4 {
        case 0:
            return AnyShapeStyle(
                LinearGradient(
                    gradient: evenlyFaded(ramp), startPoint: .leading, endPoint: .trailing))
        case 1:
            return AnyShapeStyle(
                LinearGradient(gradient: ramp, startPoint: .top, endPoint: .bottom))
        case 2:
            return AnyShapeStyle(
                LinearGradient(gradient: ramp, startPoint: .leading, endPoint: .trailing))
        default:
            return AnyShapeStyle(
                LinearGradient(
                    gradient: ramp, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private static func tableRows(seed: UInt64, count: Int) -> [AlphaRampRow] {
        (0..<max(1, count)).map { index in
            let hashed = mix(seed, index &+ 21_001)
            return AlphaRampRow(id: index, name: Synth.slug(hashed), status: Synth.status(hashed))
        }
    }
}

private struct AlphaRampRow: Identifiable {
    let id: Int
    let name: String
    let status: String
}

/// One block per geometry with a centre, painted as the style itself so the
/// ramp resolves over the whole rectangle — the per-cell alpha over an AREA.
private struct GeometryAlphaBand: View {
    let ramp: Gradient
    let index: Int

    var body: some View {
        HStack(spacing: 1) {
            RadialGradient(gradient: ramp, center: .center, startRadius: 0, endRadius: 9)
                .frame(width: 18, height: 5)
            EllipticalGradient(gradient: ramp, center: .center)
                .frame(width: 18, height: 5)
            AngularGradient(gradient: ramp, center: .center, angle: .zero)
                .frame(width: 18, height: 5)
            LinearGradient(gradient: ramp, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 18, height: 5)
        }
    }
}
