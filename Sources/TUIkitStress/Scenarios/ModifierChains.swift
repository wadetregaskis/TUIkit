//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModifierChains.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Modifier Chains

/// Many rows, each buried under a long chain of modifiers
/// (`padding`→`border`→`foregroundStyle`→`frame`→`padding`→`border`…). Every
/// modifier is another wrapper node the render pipeline threads context and
/// buffers through, so this stresses the `ModifiedView` / environment-modifier
/// layering and per-node measure overhead independent of data size.
enum ModifierChainsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "modifiers",
        title: "Modifier Chains",
        blurb: "N rows, each wrapped in a long modifier chain.",
        stresses: "ModifiedView/environment-modifier layering · per-node measure overhead",
        make: { config in AnyView(ModifierChainsView(config: config)) }
    )
}

private struct ModifierChainsView: View {
    let config: StressConfig

    var body: some View {
        let count = config.sized(400)
        VStack(alignment: .leading, spacing: 0) {
            Text("Modifier Chains — \(count) deeply-modified rows").bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let h = mix(config.seed, index)
                        Text(Synth.slug(h))
                            .foregroundStyle(.accent)
                            .padding(1)
                            .border()
                            .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
                            .padding(1)
                            .border()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
