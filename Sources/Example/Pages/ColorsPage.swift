//  🖥️ TUIkit — Terminal UI Kit for Swift
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

            DemoSection("page.colors.section.standard") {
                HStack(spacing: 2) {
                    Text("page.colors.black").foregroundStyle(.black).background(.white)
                    Text("page.colors.red").foregroundStyle(.red)
                    Text("page.colors.green").foregroundStyle(.green)
                    Text("page.colors.yellow").foregroundStyle(.yellow)
                }
                HStack(spacing: 2) {
                    Text("page.colors.blue").foregroundStyle(.blue)
                    Text("page.colors.magenta").foregroundStyle(.magenta)
                    Text("page.colors.cyan").foregroundStyle(.cyan)
                    Text("page.colors.white").foregroundStyle(.white)
                }
            }

            DemoSection("page.colors.section.bright") {
                HStack(spacing: 2) {
                    Text("page.colors.brightRed").foregroundStyle(.brightRed)
                    Text("page.colors.brightGreen").foregroundStyle(.brightGreen)
                    Text("page.colors.brightYellow").foregroundStyle(.brightYellow)
                    Text("page.colors.brightBlue").foregroundStyle(.brightBlue)
                }
            }

            DemoSection("page.colors.section.rgb") {
                HStack(spacing: 2) {
                    Text("page.colors.orange").foregroundStyle(.rgb(255, 128, 0))
                    Text("page.colors.pink").foregroundStyle(.rgb(255, 105, 180))
                    Text("page.colors.teal").foregroundStyle(.rgb(0, 128, 128))
                    Text("page.colors.purple").foregroundStyle(.rgb(128, 0, 128))
                }
            }

            DemoSection("page.colors.section.semantic") {
                HStack(spacing: 2) {
                    Text("page.colors.primary").foregroundStyle(.primary)
                    Text("page.colors.success").foregroundStyle(.success)
                    Text("page.colors.warning").foregroundStyle(.warning)
                    Text("page.colors.error").foregroundStyle(.error)
                }
            }

            DemoSection("page.colors.section.gradients") {
                VStack(alignment: .leading, spacing: 1) {
                    GradientLine(label: "page.colors.gradient.redBlue",
                                 stops: [(255, 0, 0), (0, 0, 255)])
                    GradientLine(label: "page.colors.gradient.yellowMagenta",
                                 stops: [(255, 220, 0), (255, 0, 200)])
                    GradientLine(label: "page.colors.gradient.tealPurple",
                                 stops: [(0, 180, 180), (140, 0, 200)])
                    GradientLine(label: "page.colors.gradient.fire",
                                 stops: [(120, 0, 0), (255, 80, 0), (255, 220, 0)])
                    GradientLine(label: "page.colors.gradient.rainbow",
                                 stops: [
                                    (255, 0, 0), (255, 165, 0), (255, 255, 0),
                                    (0, 200, 0), (0, 100, 255), (140, 0, 200),
                                 ])
                    GradientLine(label: "page.colors.gradient.grayscale",
                                 stops: [(0, 0, 0), (255, 255, 255)])
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.colors")
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
    /// The key for the label printed to the left of the gradient strip.
    let label: LocalizedStringKey

    /// The colour stops to interpolate between, in RGB.
    let stops: [(r: UInt8, g: UInt8, b: UInt8)]

    var body: some View {
        HStack(spacing: 1) {
            Text(label.localized.padded(to: 22))
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

        // Quantised as a RAMP, not cell by cell. On a 256-colour terminal a
        // per-cell nearest match has no memory of its neighbours, and the
        // strip's smoothness is a property of the SEQUENCE — see
        // `Color.quantisedRamp(_:count:depth:)`. This demo had its own
        // interpolation and got the per-cell answer: "teal → purple" put three
        // out-of-place cells in every strip it drew.
        let ramp = Color.quantisedRamp(
            Gradient(colors: stops.map { Color.rgb($0.r, $0.g, $0.b) }),
            count: cells, depth: ColorDepth.current)
        var line = ""
        line.reserveCapacity(cells * 20)
        for colour in ramp {
            let styled = Text(Self.glyph).foregroundStyle(colour)
            let buffer = TUIkit.renderToBuffer(styled, context: context)
            line += buffer.lines.first ?? Self.glyph
        }
        return FrameBuffer(lines: [line])
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
