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
                    // given a cell, how far along the ramp is it? Two across
                    // rather than four, because the answer only becomes
                    // legible at a size — a sweep across twelve cells by four
                    // is a smear, and the block has to be big enough that a
                    // circle looks like one.
                    Text("page.colors.gradientStyle.geometries")
                        .foregroundStyle(.palette.foregroundSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            // The direction is in the name because it is the
                            // point: a linear ramp's axis is any two points,
                            // and a diagonal one is the case that shows it.
                            // Unlabelled, the diagonal reads as a mistake.
                            GeometryBlock(name: "linear ↘") {
                                LinearGradient(
                                    colors: Self.warm, startPoint: .topLeading,
                                    endPoint: .bottomTrailing)
                            }
                            GeometryBlock(name: "radial") {
                                // The height, because a radius is horizontal
                                // cells and a row is two of them: this is
                                // exactly half the block's height on screen,
                                // so the circle touches the top and bottom
                                // edges and stops well short of the sides —
                                // round in a box that is not.
                                RadialGradient(
                                    colors: Self.warm, center: .center, startRadius: 0,
                                    endRadius: GeometryBlockSize.height)
                            }
                        }
                        HStack(spacing: 2) {
                            GeometryBlock(name: "elliptical") {
                                EllipticalGradient(colors: Self.warm)
                            }
                            GeometryBlock(name: "angular") {
                                AngularGradient(
                                    gradient: Gradient(colors: Self.warm + [Self.warm[0]]),
                                    center: .center, angle: .zero)
                            }
                        }
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

/// How big a geometry block is, outside the generic so a call site can reach it
/// from inside its own `@ViewBuilder`.
private enum GeometryBlockSize {
    static let width = 25

    /// Deliberately NOT square once the 2:1 cell aspect is counted: 25 × 7 is
    /// 25 × 14 on screen, a box half again as wide as it is tall.
    ///
    /// The block used to be 25 × 11 — visually square — and that made two of
    /// the four geometries indistinguishable, because in a square box a
    /// box-proportioned ellipse *is* a circle. Radial and elliptical differ
    /// only in whether the box's proportions reach the ramp, so a square box
    /// is precisely the one shape that hides the difference.
    static let height = 7
}

/// One geometry, painted as a block and named underneath.
///
/// The block is the gradient **itself**, used where a view goes — the four
/// geometries all conform to `View` and fill the space they are offered, so
/// there is nothing here to draw with. It used to be a wall of `█` under a
/// `.foregroundStyle`, which painted the same ramp onto glyphs rather than
/// into the field, and needed the reader to know that the glyphs were scenery.
///
/// The size is the demo. A geometry is a rule about where a cell sits in a
/// rectangle, so a rectangle too small has nothing to say: at twelve cells by
/// four the sweep and the diagonal were indistinguishable smears. 25 × 7 is
/// odd in both axes, which puts `.center` exactly on the middle cell, and
/// oblong on screen rather than square — see ``GeometryBlockSize/height``,
/// where the shape is the point rather than an accident of fitting.
private struct GeometryBlock<Style: View>: View {
    let name: String
    @ViewBuilder let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            style.frame(width: GeometryBlockSize.width, height: GeometryBlockSize.height)
            Text(verbatim: name)
                .foregroundStyle(.palette.foregroundSecondary)
        }
    }
}

// MARK: - Gradient Helpers

/// A single labelled horizontal gradient strip.
///
/// The strip is a ``LinearGradient`` used as a **view**, which fills the space
/// the row leaves it — so it claims the width without a `.frame`, and the
/// painting is the framework's own. This was forty lines of `Renderable` that
/// rendered a one-cell `Text` per column; the ramp, its quantisation and its
/// monotonicity repair are all things the style already does.
private struct GradientLine: View {
    /// The key for the label printed to the left of the gradient strip.
    let label: LocalizedStringKey

    /// The colour stops to interpolate between, in RGB.
    let stops: [(r: UInt8, g: UInt8, b: UInt8)]

    var body: some View {
        HStack(spacing: 1) {
            Text(label.localized.padded(to: 22))
                .foregroundStyle(.palette.foregroundSecondary)
            LinearGradient(
                colors: stops.map { Color.rgb($0.r, $0.g, $0.b) },
                startPoint: .leading, endPoint: .trailing)
        }
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
