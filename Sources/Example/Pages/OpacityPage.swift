//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Opacity Page

/// Opacity demo page.
///
/// `.opacity(_:)` is compositing rather than a colour blend: the subtree becomes
/// a layer, and each of its cells is resolved against the cell beneath it. Every
/// demo here is over something DIFFERENT, because that is the whole of what the
/// change bought — over a plain page a blend toward the palette background and a
/// composite against what is there agree exactly, and the difference only shows
/// where something else has painted.
///
/// One slider drives all of them, so the rules are explorable rather than
/// described: colours blend continuously at every value, a character contested
/// by one underneath swaps at ½, and a character over anything blank simply
/// fades all the way out.
struct OpacityPage: View {
    @State private var opacity: Double = 0.5
    @State private var outer: Double = 1
    @State private var breathes = false
    @State private var breathingOpacity: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            controls
            overField
            throughText
            nesting
            containerFill
            neverEnding
            KeyboardHelpSection(shortcuts: [
                "page.opacity.help.tab",
                "page.opacity.help.arrows",
                "page.opacity.help.activate",
            ])
        }
        .padding(.horizontal, 1)
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.opacity", subtitle: "page.opacity.subtitle")
        }
    }

    // MARK: - The controls

    private var controls: some View {
        DemoSection("page.opacity.section.controls") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.opacity.controls.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                Slider(value: $opacity, in: 0...1, step: 0.05) {
                    Text("\(L("page.opacity.slider.inner")) \(String(format: "%.2f", opacity))")
                }
                Slider(value: $outer, in: 0...1, step: 0.05) {
                    Text(
                        "\(L("page.opacity.slider.outer")) "
                            + String(format: "%.2f → %.2f", outer, outer * opacity))
                }
            }
        }
    }

    // MARK: - Over a coloured field

    /// The case the old render-time fade got wrong, and the reason for the
    /// change: it faded toward the PAGE's background whatever the label was
    /// actually sitting on.
    private var overField: some View {
        DemoSection("page.opacity.section.field") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.opacity.field.hint")
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
            Text("page.opacity.field.label")
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
        DemoSection("page.opacity.section.text") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.opacity.text.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ZStack(alignment: .leading) {
                    Text("page.opacity.text.behind")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.opacity.text.front")
                        .foregroundStyle(.palette.accent)
                        .opacity(opacity)
                }
            }
        }
    }

    // MARK: - Nesting

    private var nesting: some View {
        DemoSection("page.opacity.section.nesting") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.opacity.nesting.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ZStack(alignment: .leading) {
                    block(.rgb(40, 40, 90), width: 34, height: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.opacity.nesting.plain")
                            .foregroundStyle(.rgb(255, 200, 90))
                        Text("page.opacity.nesting.inner")
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
        DemoSection("page.opacity.section.container") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.opacity.container.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ZStack(alignment: .leading) {
                    block(.rgb(90, 40, 90), width: 40, height: 5)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.opacity.container.first")
                        Text("page.opacity.container.second")
                    }
                    .padding(1)
                    .opacity(opacity)
                }
            }
        }
    }

    // MARK: - The repeating fade

    private var neverEnding: some View {
        DemoSection("page.opacity.section.forever") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.opacity.forever.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                Toggle("page.opacity.forever.toggle", isOn: $breathes)
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
                    Text("page.opacity.forever.text")
                        .foregroundStyle(.rgb(255, 255, 200))
                        .opacity(breathingOpacity)
                }
            }
        }
    }
}
