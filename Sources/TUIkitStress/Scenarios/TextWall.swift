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
    let count: Int
    /// Per-paragraph header + body, synthesised ONCE in `init`.
    private let headers: [String]
    private let bodies: [String]

    init(config: StressConfig) {
        let count = config.sized(300)
        self.count = count
        // Synthesise the prose once, not in `body`. The text is a pure function
        // of (seed, index) and never changes between frames, so regenerating it
        // on every render — as the inline `Synth.sentence(...)` in `body` did —
        // measured the harness's RNG + string joins (~20% of the trace) instead
        // of TUIkit's text layout. A real app likewise computes its text once and
        // stores it, rather than rebuilding it in `body`. Regenerated only when
        // `count`/`seed` change (a new config makes a new view → new `init`).
        var headers: [String] = []
        var bodies: [String] = []
        headers.reserveCapacity(count)
        bodies.reserveCapacity(count)
        for index in 0..<count {
            let h = mix(config.seed, index)
            headers.append("¶ \(index) — \(Synth.name(h))")
            // 30–70 words, forcing multi-line wrap at terminal width.
            bodies.append(Synth.sentence(h, words: 30 + Int(h % 40)))
        }
        self.headers = headers
        self.bodies = bodies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Text Wall — \(count) wrapping paragraphs").bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(headers[index]).bold().foregroundStyle(.accent)
                            Text(bodies[index])
                        }
                    }
                }
            }
        }
    }
}
