//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnyViewStorm.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - AnyView Storm

/// Every row is a different shape, funnelled through `AnyView`. Type erasure
/// defeats the concrete-type fast paths and forces the render pipeline's
/// erased fallback (the historically expensive render-to-measure path), so this
/// targets exactly the cost that concrete `measureChild`/`Layoutable` dispatch
/// avoids.
enum AnyViewStormScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "anyview",
        title: "AnyView Storm",
        blurb: "N heterogeneous rows, each erased through AnyView.",
        stresses: "type-erasure fallback · render-to-measure path · lost concrete dispatch",
        make: { config in AnyView(AnyViewStormView(config: config)) }
    )
}

private struct AnyViewStormView: View {
    let config: StressConfig

    var body: some View {
        let count = config.sized(500)
        VStack(alignment: .leading, spacing: 0) {
            Text("AnyView Storm — \(count) type-erased rows").bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        erasedRow(index, mix(config.seed, index))
                    }
                }
            }
        }
    }

    /// Returns a different concrete shape per `index`, all erased to `AnyView`.
    private func erasedRow(_ index: Int, _ h: UInt64) -> AnyView {
        switch index % 4 {
        case 0:
            return AnyView(Text("#\(index) \(Synth.slug(h))").foregroundStyle(.accent))
        case 1:
            return AnyView(HStack {
                Text("#\(index)").foregroundStyle(.secondary)
                Spacer()
                Text(Synth.status(h)).foregroundStyle(statusColor(h))
            })
        case 2:
            return AnyView(Text(Synth.bar(Double(h % 100) / 100, width: 18)).foregroundStyle(.success))
        default:
            return AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    Text(Synth.name(h)).bold()
                    Text(Synth.slug(h)).foregroundStyle(.secondary)
                }
                .padding(1)
                .border()
            )
        }
    }
}
