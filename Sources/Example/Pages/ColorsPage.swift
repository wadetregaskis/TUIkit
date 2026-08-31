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

            DemoSection("page.colors.section.gradientStyles") {
                VStack(alignment: .leading, spacing: 1) {
                    // A gradient is a `ShapeStyle`, so it goes wherever a
                    // colour goes. This is SwiftUI's own meaning and the
                    // default: every leaf runs the whole ramp inside itself.
                    Text("page.colors.gradientStyle.perLeaf")
                        .foregroundStyle(
                            LinearGradient(
                                colors: Self.warm, startPoint: .leading, endPoint: .trailing))

                    // And the TUI-specific extent, which SwiftUI has no way to
                    // say: ONE ramp across a set of views, each taking its own
                    // slice by where it sits.
                    Text("page.colors.gradientStyle.spanning")
                        .foregroundStyle(.palette.foregroundSecondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "LinearGradient")
                        Text(verbatim: "RadialGradient")
                        Text(verbatim: "EllipticalGradient")
                        Text(verbatim: "AngularGradient")
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: Self.warm, startPoint: .top, endPoint: .bottom)
                    )
                    .gradientExtent(.subtree)

                    Text("page.colors.gradientStyle.background")
                        .background(
                            LinearGradient(
                                colors: [.rgb(40, 60, 120), .rgb(120, 40, 90)],
                                startPoint: .leading, endPoint: .trailing))

                    // The four geometries answer one question differently:
                    // given a cell, how far along the ramp is it?
                    HStack(spacing: 2) {
                        GeometryBlock(
                            name: "linear",
                            style: AnyShapeStyle(
                                LinearGradient(
                                    colors: Self.warm, startPoint: .topLeading,
                                    endPoint: .bottomTrailing)))
                        GeometryBlock(
                            name: "radial",
                            style: AnyShapeStyle(
                                RadialGradient(
                                    colors: Self.warm, center: .center, startRadius: 0,
                                    endRadius: 6)))
                        GeometryBlock(
                            name: "elliptical",
                            style: AnyShapeStyle(EllipticalGradient(colors: Self.warm)))
                        GeometryBlock(
                            name: "angular",
                            style: AnyShapeStyle(
                                AngularGradient(
                                    gradient: Gradient(colors: Self.warm + [Self.warm[0]]),
                                    center: .center, angle: .zero)))
                    }
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

extension ColorsPage {
    /// The one ramp every style demo above draws with, so what changes between
    /// them is visibly the GEOMETRY and not the colours.
    fileprivate static let warm: [Color] = [.rgb(255, 80, 80), .rgb(80, 160, 255)]
}

/// One geometry, painted over a block and named underneath.
///
/// The block is a single multi-line `Text`, which is one leaf — so the ramp
/// resolves over the whole rectangle rather than per row, which is what makes
/// a radial gradient round instead of four independent stripes.
private struct GeometryBlock: View {
    let name: String
    let style: AnyShapeStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                verbatim: Array(repeating: String(repeating: "█", count: 12), count: 4)
                    .joined(separator: "\n")
            )
            .foregroundStyle(style)
            Text(verbatim: name)
                .foregroundStyle(.palette.foregroundSecondary)
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
