//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayeringPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Layering Page

/// Layering demo page: what a `ZStack` does with the cells a layer lands on,
/// and what `.opacity(_:)` changes about it.
///
/// The two used to be separate pages, and the separation was the problem: a
/// `ZStack` layer is opaque, `.opacity` is what makes it not, and neither
/// demonstrates anything about the other on its own. The ZStack bands and the
/// opacity demos now share one set of controls — where the top layer sits, how
/// opaque it is, and whether it paints colours of its own — because those three
/// together are the whole of what a composite depends on.
///
/// `.opacity(_:)` is compositing rather than a colour blend: the subtree becomes
/// a layer, and each of its cells is resolved against the cell beneath it. Every
/// demo here is over something DIFFERENT, because that is the whole of what the
/// change bought — over a plain page a blend toward the palette background and a
/// composite against what is there agree exactly, and the difference only shows
/// where something else has painted.
struct LayeringPage: View {
    @State private var opacity: Double = 0.5
    @State private var outer: Double = 1
    @State private var breathes = false
    @State private var breathingOpacity: Double = 1

    /// Where the ZStack demos' TOP layer sits, as a fraction of its full
    /// travel: `-1` is clear of the layer beneath it on the left, `0` is where
    /// its alignment puts it, `+1` is clear on the right.
    ///
    /// A fraction rather than a cell count, because the five bands are
    /// different widths and their top layers are aligned differently — so one
    /// count of cells would run out of travel in some and past the end in
    /// others. Each case turns the fraction into its own offset.
    ///
    /// - Note: internal rather than `private`, and it cannot be otherwise: the
    ///   demo that reads it is an `extension LayeringPage` in
    ///   `LayeringZStackDemos.swift`, and Swift's `private` is file-scoped.
    @State var zstackTravel = 0.0  // swiftlint:disable:this private_swiftui_state

    /// Whether the travel sweeps back and forth on its own.
    @State var zstackAnimates = false  // swiftlint:disable:this private_swiftui_state

    /// Whether the ZStack demos' top layer paints a foreground colour of its
    /// own, and whether it paints a background.
    ///
    /// The second is the one that changes what a composite DOES: a cell with a
    /// background of its own wins outright at full opacity, and a cell without
    /// one has nothing to win with, so what is behind it shows through at every
    /// alpha including 1. Two toggles rather than a note, because that sentence
    /// is only believable when you can turn it off and on.
    @State var zstackTopForeground = true  // swiftlint:disable:this private_swiftui_state
    @State var zstackTopBackground = false  // swiftlint:disable:this private_swiftui_state

    /// The opacity the ZStack demos' top layer is composited at — the same
    /// slider the demos below use, so one control means one thing on the page.
    var zstackOpacity: Double { opacity }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            controls
            zstackSection
            overField
            throughText
            nesting
            containerFill
            neverEnding
            KeyboardHelpSection(shortcuts: [
                "page.layering.help.tab",
                "page.layering.help.arrows",
                "page.layering.help.activate",
            ])
        }
        .padding(.horizontal, 1)
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.layering", subtitle: "page.layering.subtitle")
        }
    }

    // MARK: - The controls

    /// A `0...1` alpha as whole percent — the unit both sliders step in.
    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var controls: some View {
        DemoSection("page.layering.section.controls") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.layering.controls.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                // A percent a step, and read out as one: the rules these demos
                // show turn on where a value sits between 0 and 1, and "45%"
                // says that where "0.45" makes the reader do the conversion.
                Slider(value: $opacity, in: 0...1, step: 0.01) {
                    Text("\(L("page.layering.slider.inner")) \(Self.percent(opacity))")
                }
                Slider(value: $outer, in: 0...1, step: 0.01) {
                    Text(
                        "\(L("page.layering.slider.outer")) "
                            + "\(Self.percent(outer)) → \(Self.percent(outer * opacity))")
                }
                // What the top layer PAINTS, which is the other half of what a
                // composite depends on. Turning the background on makes the
                // layer opaque cell for cell whatever the alpha; turning the
                // foreground off leaves it painting nothing at all.
                HStack(spacing: 2) {
                    Toggle("page.layering.topForeground", isOn: $zstackTopForeground)
                    Toggle("page.layering.topBackground", isOn: $zstackTopBackground)
                }
            }
        }
    }

    // MARK: - Over a coloured field

    /// The case the old render-time fade got wrong, and the reason for the
    /// change: it faded toward the PAGE's background whatever the label was
    /// actually sitting on.
    private var overField: some View {
        DemoSection("page.layering.section.field") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.layering.field.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 2) {
                    field(.rgb(160, 30, 30))
                    field(.rgb(30, 90, 160))
                    field(.rgb(30, 120, 60))
                }
            }
        }
    }

    /// A label at the current opacity over a solid block of `color`.
    ///
    /// The block is a `Text` of spaces with a background rather than a `Color`
    /// view: there is no `Color`-as-a-`View` here, a terminal having nothing to
    /// fill an unbounded area with.
    private func field(_ color: Color) -> some View {
        ZStack(alignment: .leading) {
            block(color, width: 22, height: 3)
            Text("page.layering.field.label")
                .foregroundStyle(.rgb(255, 235, 120))
                .opacity(opacity)
        }
    }

    /// A solid rectangle of `color`.
    private func block(_ color: Color, width: Int, height: Int) -> some View {
        Text(String(repeating: "\n", count: max(0, height - 1)))
            .frame(width: width, height: height, alignment: .leading)
            .background(color)
    }

    // MARK: - Text through text

    private var throughText: some View {
        DemoSection("page.layering.section.text") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.layering.text.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ZStack(alignment: .leading) {
                    Text("page.layering.text.behind")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.layering.text.front")
                        .foregroundStyle(.palette.accent)
                        .opacity(opacity)
                }
            }
        }
    }

    // MARK: - Nesting

    private var nesting: some View {
        DemoSection("page.layering.section.nesting") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.layering.nesting.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ZStack(alignment: .leading) {
                    block(.rgb(40, 40, 90), width: 34, height: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.layering.nesting.plain")
                            .foregroundStyle(.rgb(255, 200, 90))
                        Text("page.layering.nesting.inner")
                            .foregroundStyle(.rgb(255, 200, 90))
                            .opacity(opacity)
                    }
                    .opacity(outer)
                }
            }
        }
    }

    // MARK: - A whole container

    /// The rule that keeps a faded container from punching a hole: a source
    /// SPACE composites its background and lets what is behind it through.
    private var containerFill: some View {
        DemoSection("page.layering.section.container") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.layering.container.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ZStack(alignment: .leading) {
                    block(.rgb(90, 40, 90), width: 40, height: 5)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.layering.container.first")
                        Text("page.layering.container.second")
                    }
                    .padding(1)
                    .opacity(opacity)
                }
            }
        }
    }

    // MARK: - The repeating fade

    private var neverEnding: some View {
        DemoSection("page.layering.section.forever") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.layering.forever.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                Toggle("page.layering.forever.toggle", isOn: $breathes)
                    .onChange(of: breathes) { _, isOn in
                        withAnimation(
                            isOn
                                ? .linear(duration: 0.6).repeatForever(autoreverses: true) : nil
                        ) {
                            breathingOpacity = isOn ? 0.5 : 1
                        }
                    }
                ZStack(alignment: .leading) {
                    block(.rgb(30, 70, 70), width: 34, height: 1)
                    Text("page.layering.forever.text")
                        .foregroundStyle(.rgb(255, 255, 200))
                        .opacity(breathingOpacity)
                }
            }
        }
    }
}
