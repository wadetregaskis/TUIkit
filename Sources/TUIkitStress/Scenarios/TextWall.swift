//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextWall.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Text Wall

/// Many long, wrapping paragraphs synthesised per index. Stresses text layout:
/// width measurement, word wrapping across the available columns, and the
/// throughput of rendering large amounts of glyph content (the work that scales
/// with characters rather than view nodes).
enum TextWallScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "textwall",
        title: "Text Wall",
        blurb: "N long wrapping paragraphs of synthesised prose.",
        stresses: "text width measurement · word wrapping · glyph throughput",
        make: { config in AnyView(TextWallView(config: config)) }
    )
}

private struct TextWallView: View {
    let config: StressConfig

    var body: some View {
        let count = config.sized(300)
        VStack(alignment: .leading, spacing: 0) {
            Text("Text Wall — \(count) wrapping paragraphs").bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<count, id: \.self) { index in
                        let h = mix(config.seed, index)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("¶ \(index) — \(Synth.name(h))").bold().foregroundStyle(.accent)
                            // 30–70 words, forcing multi-line wrap at terminal width.
                            Text(Synth.sentence(h, words: 30 + Int(h % 40)))
                        }
                    }
                }
            }
        }
    }
}
