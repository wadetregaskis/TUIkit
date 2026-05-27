//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorsPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Colors demo page.
///
/// Shows various color options including:
/// - Standard ANSI colors (8 colors)
/// - Bright colors (8 colors)
/// - RGB colors (24-bit true color)
/// - Semantic colors (primary, success, warning, error)
struct ColorsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Standard ANSI Colors") {
                HStack(spacing: 2) {
                    Text("Black").foregroundStyle(.black).background(.white)
                    Text("Red").foregroundStyle(.red)
                    Text("Green").foregroundStyle(.green)
                    Text("Yellow").foregroundStyle(.yellow)
                }
                HStack(spacing: 2) {
                    Text("Blue").foregroundStyle(.blue)
                    Text("Magenta").foregroundStyle(.magenta)
                    Text("Cyan").foregroundStyle(.cyan)
                    Text("White").foregroundStyle(.white)
                }
            }

            DemoSection("Bright Colors") {
                HStack(spacing: 2) {
                    Text("Bright Red").foregroundStyle(.brightRed)
                    Text("Bright Green").foregroundStyle(.brightGreen)
                    Text("Bright Yellow").foregroundStyle(.brightYellow)
                    Text("Bright Blue").foregroundStyle(.brightBlue)
                }
            }

            DemoSection("RGB Colors (24-bit)") {
                HStack(spacing: 2) {
                    Text("Orange").foregroundStyle(.rgb(255, 128, 0))
                    Text("Pink").foregroundStyle(.rgb(255, 105, 180))
                    Text("Teal").foregroundStyle(.rgb(0, 128, 128))
                    Text("Purple").foregroundStyle(.rgb(128, 0, 128))
                }
            }

            DemoSection("Semantic Colors") {
                HStack(spacing: 2) {
                    Text("Primary").foregroundStyle(.primary)
                    Text("Success").foregroundStyle(.success)
                    Text("Warning").foregroundStyle(.warning)
                    Text("Error").foregroundStyle(.error)
                }
            }

            DemoSection("Gradients") {
                VStack(alignment: .leading, spacing: 1) {
                    GradientLine(label: "red → blue",
                                 stops: [(255, 0, 0), (0, 0, 255)])
                    GradientLine(label: "yellow → magenta",
                                 stops: [(255, 220, 0), (255, 0, 200)])
                    GradientLine(label: "teal → purple",
                                 stops: [(0, 180, 180), (140, 0, 200)])
                    GradientLine(label: "fire (red → yellow)",
                                 stops: [(120, 0, 0), (255, 80, 0), (255, 220, 0)])
                    GradientLine(label: "rainbow",
                                 stops: [
                                    (255, 0, 0), (255, 165, 0), (255, 255, 0),
                                    (0, 200, 0), (0, 100, 255), (140, 0, 200),
                                 ])
                    GradientLine(label: "grayscale",
                                 stops: [(0, 0, 0), (255, 255, 255)])
                }
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Colors Demo")
        }
    }
}

// MARK: - Gradient Helpers

/// A single labelled horizontal gradient strip.
///
/// Renders a row of block glyphs whose colours interpolate smoothly
/// between an arbitrary list of RGB stops. The strip claims whatever
/// width the parent gives it (`.frame(maxWidth: .infinity)`) so the
/// demo fills the page no matter the terminal size, and the actual
/// painting happens in ``GradientStrip``, a `Renderable` that reads
/// `context.availableWidth` at draw time.
private struct GradientLine: View {
    /// The label printed to the left of the gradient strip.
    let label: String

    /// The colour stops to interpolate between, in RGB.
    let stops: [(r: UInt8, g: UInt8, b: UInt8)]

    var body: some View {
        HStack(spacing: 1) {
            Text(label.padded(to: 22))
                .foregroundStyle(.palette.foregroundSecondary)
            GradientStrip(stops: stops)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Renderable that paints a smoothly-interpolated horizontal gradient
/// across the full width its parent gives it.
///
/// The view conforms to `Renderable` so it can read `availableWidth`
/// at draw time and use it to choose the number of glyph cells —
/// without that we'd have to either bake a fixed width into the demo
/// (the old `40` constant) or pull in a `GeometryReader`-style helper.
private struct GradientStrip: View, Renderable {
    /// Piecewise-linear colour stops.
    let stops: [(r: UInt8, g: UInt8, b: UInt8)]

    /// The block glyph used to paint each gradient cell. ▇ is solid
    /// across most terminal fonts and reads as a flat colour band.
    private static var glyph: String { "▇" }

    var body: Never {
        fatalError("GradientStrip renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let cells = max(0, context.availableWidth)
        guard cells > 0 else { return FrameBuffer(lines: [""]) }

        var line = ""
        line.reserveCapacity(cells * 20)
        let denom = max(1, cells - 1)
        for index in 0..<cells {
            let parameter = Double(index) / Double(denom)
            let (r, g, b) = sampleStop(at: parameter)
            let styled = Text(Self.glyph).foregroundStyle(.rgb(r, g, b))
            let buffer = TUIkit.renderToBuffer(styled, context: context)
            line += buffer.lines.first ?? Self.glyph
        }
        return FrameBuffer(lines: [line])
    }

    /// Interpolates between the configured stops at a parameter in `0...1`.
    private func sampleStop(at parameter: Double) -> (UInt8, UInt8, UInt8) {
        guard stops.count >= 2 else {
            let stop = stops.first ?? (0, 0, 0)
            return (stop.r, stop.g, stop.b)
        }
        let segments = Double(stops.count - 1)
        let scaled = max(0.0, min(segments, parameter * segments))
        let lowerIndex = min(Int(scaled), stops.count - 2)
        let mix = scaled - Double(lowerIndex)
        let lower = stops[lowerIndex]
        let upper = stops[lowerIndex + 1]
        func lerp(_ start: UInt8, _ end: UInt8) -> UInt8 {
            let blended = Double(start) + (Double(end) - Double(start)) * mix
            return UInt8(max(0, min(255, Int(blended.rounded()))))
        }
        return (lerp(lower.r, upper.r), lerp(lower.g, upper.g), lerp(lower.b, upper.b))
    }
}

extension String {
    /// Right-pads `self` with spaces so the resulting string has at least
    /// `width` visible cells. Used to align the gradient labels into a
    /// neat column without reaching for a stack of `Spacer`s.
    fileprivate func padded(to width: Int) -> String {
        let visible = self.count
        guard visible < width else { return self }
        return self + String(repeating: " ", count: width - visible)
    }
}
