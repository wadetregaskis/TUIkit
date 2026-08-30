//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientBandingTests.swift
//
//  A gradient drawn on a 256-colour terminal is smooth when its cells move in
//  ONE direction. `Color.quantisedRamp(stops:count:depth:)` is what makes that
//  true; these are about everything that has to go through it.
//
//  The rule keeps being re-learned one strip at a time, because drawing a
//  gradient cell by cell is the obvious thing to write and looks right at
//  truecolor — so the assertions here are on the DRAWN output of the views that
//  draw one, not on the ramp function, which was never the part that was wrong.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("Gradients do not band at 256 colours")
struct GradientBandingTests {

    /// How many times a sequence turns back on itself: the runs of equal
    /// entries, and then any channel that moves against the way the source ramp
    /// moves it there. Zero is smooth.
    ///
    /// The same test ``Color/quantisedRamp(stops:count:depth:)`` repairs
    /// against, restated here rather than reached into — a test that asks the
    /// implementation what "correct" means asks nothing.
    private func reversals(_ entries: [Color], along ramp: [Color]) -> Int {
        var runs: [(start: Int, end: Int)] = []
        for index in entries.indices {
            if let last = runs.last, entries[index] == entries[last.start] {
                runs[runs.count - 1].end = index
            } else {
                runs.append((index, index))
            }
        }
        guard runs.count > 1 else { return 0 }
        var count = 0
        for step in 1..<runs.count {
            guard let a = entries[runs[step - 1].start].rgbComponents,
                let b = entries[runs[step].start].rgbComponents,
                let sourceA = ramp[runs[step - 1].start].rgbComponents,
                let sourceB = ramp[runs[step].start].rgbComponents
            else { continue }
            let entry = [
                Int(b.red) - Int(a.red), Int(b.green) - Int(a.green), Int(b.blue) - Int(a.blue),
            ]
            let source = [
                Int(sourceB.red) - Int(sourceA.red),
                Int(sourceB.green) - Int(sourceA.green),
                Int(sourceB.blue) - Int(sourceA.blue),
            ]
            if zip(entry, source).contains(where: { $0 != 0 && ($1 == 0 || ($0 > 0) != ($1 > 0)) }) {
                count += 1
            }
        }
        return count
    }

    /// The gradients the app actually ships — the Colors page's six strips and
    /// the two the gradient editor opens with.
    private static let shipped: [(name: String, stops: [Color])] = [
        ("redBlue", [.rgb(255, 0, 0), .rgb(0, 0, 255)]),
        ("yellowMagenta", [.rgb(255, 220, 0), .rgb(255, 0, 200)]),
        ("tealPurple", [.rgb(0, 180, 180), .rgb(140, 0, 200)]),
        ("fire", [.rgb(120, 0, 0), .rgb(255, 80, 0), .rgb(255, 220, 0)]),
        (
            "rainbow",
            [
                .rgb(255, 0, 0), .rgb(255, 165, 0), .rgb(255, 255, 0),
                .rgb(0, 200, 0), .rgb(0, 100, 255), .rgb(140, 0, 200),
            ]
        ),
        ("grayscale", [.rgb(0, 0, 0), .rgb(255, 255, 255)]),
        ("progress", [.rgb(0x3C, 0xC8, 0xBE), .rgb(0x50, 0x6E, 0xF0), .rgb(0xAA, 0x46, 0xDC)]),
        ("track", [.rgb(0xFF, 0x50, 0x50), .rgb(0xFF, 0xC8, 0x50), .rgb(0x50, 0xDC, 0x78)]),
    ]

    /// Every shipped gradient, at the widths the app draws them at.
    ///
    /// Drawn cell by cell these reverse 1–6 times each — measured, and the
    /// reason the report said "some of the default gradients STILL show
    /// out-of-place colours": the repair existed and three call sites were not
    /// using it.
    @Test("Every gradient the app ships is monotone once quantised as a ramp")
    func shippedGradientsAreSmooth() {
        for width in [8, 12, 36, 80, 104] {
            for (name, stops) in Self.shipped {
                let source = (0..<width).map {
                    Gradient(colors: stops).color(at: Double($0) / Double(width - 1))
                }
                let ramp = Color.quantisedRamp(Gradient(colors: stops), count: width, depth: .palette256)
                #expect(
                    reversals(ramp, along: source) == 0,
                    "\(name) at \(width): \(reversals(ramp, along: source)) reversals")
            }
        }
    }

    /// The per-cell answer, so the case above is not vacuous: if the naive
    /// route ever stopped banding, these tests would be pinning nothing.
    @Test("…and cell by cell, at least one of them does not")
    func theNaiveRouteStillBands() {
        let stops: [Color] = [.rgb(0, 180, 180), .rgb(140, 0, 200)]  // teal → purple
        let source = (0..<80).map { Gradient(colors: stops).color(at: Double($0) / 79) }
        let perCell = source.map { $0.downsampledToPalette256() }
        #expect(reversals(perCell, along: source) > 0, "the naive route is no longer a hazard")
    }

    /// The gradient editor's own preview, drawn.
    ///
    /// It configures a track that goes through the ramp and drew its preview
    /// cell by cell, so the picture in the dialog banded while the thing it was
    /// previewing did not.
    ///
    /// Asserted as "the strip IS the ramp" rather than "the strip is monotone":
    /// the line also carries the dialog's own chrome colours at each end, and a
    /// property measured over those says nothing about the preview. The ramp is
    /// monotone by the case above, so containing it is the stronger claim.
    @Test("The gradient editor's preview strip is drawn as a ramp")
    func editorPreviewIsSmooth() {
        var stops: [Color] = [
            .rgb(0xFF, 0x50, 0x50), .rgb(0xFF, 0xC8, 0x50), .rgb(0x50, 0xDC, 0x78),
        ]
        var presented = true
        let panel = GradientEditorPanel(
            "gradient",
            stops: Binding(get: { stops }, set: { stops = $0 }),
            isPresented: Binding(get: { presented }, set: { presented = $0 }))

        // Pinned to 256 colours for the length of the render: the banding this
        // is about only exists in the cube, and a test host is usually
        // truecolor. Task-local, so it cannot leak into another test.
        let context = makeRenderContext(width: 60, height: 30)
        let buffer = ColorDepth.withCurrent(.palette256) {
            renderToBuffer(panel, context: context)
        }
        let width = GradientEditorPanel.previewWidthForTesting
        let expected = Color.quantisedRamp(Gradient(colors: stops), count: width, depth: .palette256)
            .compactMap { colour -> UInt8? in
                if case .palette256(let index) = colour.value { return index }
                return nil
            }
        #expect(expected.count == width, "the ramp did not quantise: \(expected)")
        let drawn = buffer.lines.map(palette256Foregrounds)
        #expect(
            drawn.contains { contains($0, expected) },
            """
            no line drew the ramp \(expected); \
            the widest was \(drawn.max { $0.count < $1.count } ?? [])
            """)
    }

    /// Whether `sequence` appears contiguously in `line`.
    private func contains(_ line: [UInt8], _ sequence: [UInt8]) -> Bool {
        guard !sequence.isEmpty, line.count >= sequence.count else { return false }
        for start in 0...(line.count - sequence.count)
        where Array(line[start..<(start + sequence.count)]) == sequence {
            return true
        }
        return false
    }

    /// The 256-colour foreground indices a rendered line sets, in order.
    private func palette256Foregrounds(_ line: String) -> [UInt8] {
        var found: [UInt8] = []
        var rest = Substring(line)
        while let start = rest.range(of: "\u{1B}[38;5;") {
            rest = rest[start.upperBound...]
            let digits = rest.prefix { $0.isNumber }
            if let value = UInt8(digits) { found.append(value) }
            rest = rest.dropFirst(digits.count)
        }
        return found
    }
}
