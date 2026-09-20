//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GaugeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// Coverage for ``Gauge``: value→bounds normalization, the label / current-value
/// / bound-label layout, the default shaded bar, and the ``GaugeStyle`` variants.
@MainActor
@Suite("Gauge")
struct GaugeTests {

    @Test("Normalizes a value within its bounds, clamping out-of-range")
    func normalization() {
        typealias PlainGauge = Gauge<Text, EmptyView, EmptyView>
        #expect(abs(PlainGauge.normalized(value: 90.0, in: 60.0...180.0) - 0.25) < 0.0001)  // 30/120
        #expect(PlainGauge.normalized(value: 200.0, in: 0.0...100.0) == 1.0)  // clamp high
        #expect(PlainGauge.normalized(value: -5.0, in: 0.0...100.0) == 0.0)  // clamp low
        #expect(PlainGauge.normalized(value: 0.5, in: 0.0...1.0) == 0.5)  // default bounds
    }

    @Test("Renders its label above a bar; the bar fills toward the value")
    func labelAndBar() {
        let buffer = renderToBuffer(
            Gauge(value: 0.5) { Text("CPU") }, context: makeRenderContext(width: 30, height: 4))
        let text = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("CPU"))
        #expect(buffer.height == 2)  // label line + bar line
        // The default gauge is a shaded meter (▓/░), distinct from ProgressView.
        let bar = buffer.lines.last?.stripped ?? ""
        #expect(bar.contains("▓"))
        #expect(bar.contains("░"))
    }

    @Test("Shows the current-value label and flanks the bar with bound labels")
    func fullLabels() {
        let buffer = renderToBuffer(
            Gauge(value: 42, in: 0...100) {
                Text("CPU")
            } currentValueLabel: {
                Text("42%")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("100")
            },
            context: makeRenderContext(width: 40, height: 4))
        let joined = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(joined.contains("CPU"))
        #expect(joined.contains("42%"))
        let bar = buffer.lines.last?.stripped ?? ""
        #expect(bar.hasPrefix("0 "))  // minimum label left of the bar
        #expect(bar.hasSuffix(" 100"))  // maximum label right of the bar
    }

    @Test("A string-title gauge renders the title")
    func stringTitle() {
        let text = renderToBuffer(Gauge("Volume", value: 0.7), context: makeRenderContext(width: 30, height: 4))
            .lines.map { $0.stripped }.joined()
        #expect(text.contains("Volume"))
    }

    @Test("A gauge with no labels is a single bar line")
    func barOnly() {
        let buffer = renderToBuffer(
            Gauge(value: 0.3) { EmptyView() }, context: makeRenderContext(width: 20, height: 4))
        #expect(buffer.height == 1)
        let bar = buffer.lines.first?.stripped ?? ""
        #expect(bar.contains("▓"))
    }

    // MARK: - GaugeStyle variants

    @Test("The accessory-circular style renders a ring dial around the value")
    func accessoryCircularDial() {
        let buffer = renderToBuffer(
            Gauge(value: 0.75) {
                Text("Load")
            } currentValueLabel: {
                Text("75%")
            }
            .gaugeStyle(.accessoryCircular),
            context: makeRenderContext(width: 30, height: 6))
        let joined = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        // A rounded-box ring (╭─╮ / │75%│ / ╰─╯) with the label below.
        #expect(joined.contains("╭"))
        #expect(joined.contains("╰"))
        #expect(joined.contains("75%"))
        #expect(joined.contains("Load"))
        #expect(buffer.height == 4)  // 3 ring rows + label
    }

    @Test("The circular dial right-aligns its interior value")
    func circularDialRightAligned() {
        // A value narrower than the 4-cell interior must sit flush against the
        // right border with the padding on the LEFT (right-aligned), e.g. the
        // middle ring row reads `│  7%│`, not centred/left `│7%  │`.
        let buffer = renderToBuffer(
            Gauge(value: 0.07) { EmptyView() } currentValueLabel: { Text("7%") }
                .gaugeStyle(.accessoryCircular),
            context: makeRenderContext(width: 30, height: 6))
        let mid = buffer.lines.map(\.stripped).first { $0.contains("7%") } ?? ""
        #expect(mid.hasSuffix("7%│"), "value flush-right against the border: '\(mid)'")
        #expect(mid.hasPrefix("│ "), "padding on the left proves right-alignment: '\(mid)'")
    }

    @Test("A wide-character value does not break the ring")
    func circularDialWideValue() {
        // The dial's glyph grid holds one Character per column, but a CJK or
        // emoji character in the VALUE is two cells wide: deposited per-column
        // it shoved the middle row's right wall a cell past the ring, so the
        // three rows no longer aligned. Cells, not characters.
        let buffer = renderToBuffer(
            Gauge(value: 0.5) { EmptyView() } currentValueLabel: { Text("五〇%") }
                .gaugeStyle(.accessoryCircular),
            context: makeRenderContext(width: 30, height: 6))
        let rows = buffer.lines.map(\.stripped).filter { !$0.isEmpty }
        #expect(rows.count >= 3, "the three ring rows render: \(rows)")
        let widths = rows.prefix(3).map(\.strippedLength)
        #expect(
            Set(widths).count == 1,
            "all three ring rows are the same cell width: \(widths) in \(rows)")
        let mid = rows.first { $0.contains("五〇%") } ?? ""
        #expect(mid.hasSuffix("五〇%│"), "the value sits flush against the right wall: '\(mid)'")
    }

    @Test("The accessory-circular-tiny style keeps the single pie glyph")
    func accessoryCircularTinyDial() {
        let buffer = renderToBuffer(
            Gauge(value: 0.75) { EmptyView() } currentValueLabel: { Text("75%") }
                .gaugeStyle(.accessoryCircularTiny),
            context: makeRenderContext(width: 30, height: 4))
        let joined = buffer.lines.map { $0.stripped }.joined()
        #expect(joined.contains("◕"))  // three-quarter pie glyph
        #expect(buffer.width < 10)
    }

    @Test("accessoryLinear marks position (no fill); accessoryLinearCapacity fills")
    func linearCapacityVsMarker() {
        let marker = renderToBuffer(
            Gauge(value: 0.5) { EmptyView() }.gaugeStyle(.accessoryLinear),
            context: makeRenderContext(width: 20, height: 4)
        ).lines.first?.stripped ?? ""
        // Position marker on a plain line: a ● surrounded by ─, and NO fill.
        #expect(marker.contains("●"))
        #expect(marker.contains("─"))
        #expect(!marker.contains("▓") && !marker.contains("▬"))

        let capacity = renderToBuffer(
            Gauge(value: 0.5) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity),
            context: makeRenderContext(width: 20, height: 4)
        ).lines.first?.stripped ?? ""
        // Capacity fills the range — a filled block bar, not a bare marker line.
        #expect(capacity.contains("█") || capacity.contains("░"))
    }

    @Test("The ring dial is a fixed size across value widths and has a bottom break")
    func circularDialFixedSizeAndBreak() {
        func dial(_ value: Double, _ text: String) -> FrameBuffer {
            renderToBuffer(
                Gauge(value: value) { EmptyView() } currentValueLabel: { Text(text) }
                    .gaugeStyle(.accessoryCircularCapacity),
                context: makeRenderContext(width: 30, height: 6))
        }
        let narrow = dial(0.67, "67%")  // 3 cells
        let wide = dial(1.0, "100%")  // 4 cells
        // The dial no longer resizes with the value's text width.
        #expect(narrow.width == wide.width)
        #expect(narrow.height == wide.height)

        // The bottom edge carries a centred break: an interior cell between the
        // rounded corners is blank.
        let bottom = wide.lines[2].stripped  // ╰ … ╯
        #expect(bottom.hasPrefix("╰"))
        #expect(bottom.hasSuffix("╯"))
        #expect(bottom.dropFirst().dropLast().contains(" "))
    }

    @Test("measure == render: a ring-dial gauge reports the size it draws")
    func circularSizeMatchesRender() {
        let gauge = Gauge(value: 0.5) {
            Text("L")
        } currentValueLabel: {
            Text("50%")
        }
        .gaugeStyle(.accessoryCircular)
        let context = makeRenderContext(width: 40, height: 4)
        let measured = measureChild(gauge, proposal: ProposedSize(width: 40, height: nil), context: context)
        let rendered = renderToBuffer(gauge, context: context)
        #expect(measured.width == rendered.width)
        #expect(measured.height == rendered.height)
    }
}

@MainActor
@Suite("Circular dial speedometer origin")
struct GaugeSpeedometerOriginTests {
    /// The raw (ANSI-coded) dial rows of a capacity ring at `fraction`.
    private func dialRows(fraction: Double) -> [String] {
        let buffer = renderToBuffer(
            Gauge(value: fraction) { EmptyView() } currentValueLabel: { Text("x") }
                .gaugeStyle(.accessoryCircularCapacity),
            context: makeRenderContext(width: 30, height: 6))
        return buffer.lines.filter { $0.stripped.contains("╭") || $0.stripped.contains("╰") || $0.stripped.contains("│") }
    }

    @Test("A small capacity fill lights the bottom-left arc, not the top")
    func lowFillStartsAtBottomLeft() {
        // The fill sweeps like a speedometer: from just left of the
        // bottom-centre break, clockwise. At ~10% only bottom-left cells are
        // lit, so the accent colour appears on the BOTTOM row and not the top.
        let rows = dialRows(fraction: 0.1)
        guard rows.count >= 3 else {
            Issue.record("expected a 3-row dial, got \(rows.count)")
            return
        }
        let top = rows[0]
        let bottom = rows[rows.count - 1]
        // The dim ring colour differs from the accent; count distinct SGR
        // colour codes per row — the lit row carries an extra one.
        func colourCodes(_ line: String) -> Set<Substring> {
            Set(line.split(separator: "\u{1B}").filter { $0.hasPrefix("[3") || $0.hasPrefix("[9") })
        }
        #expect(
            colourCodes(bottom).count > colourCodes(top).count,
            "the bottom row carries the accent at low fill; top: \(top.debugDescription) bottom: \(bottom.debugDescription)")
    }
}

// MARK: - Custom styles

/// A custom gauge style — five blocks and the gauge's own label.
///
/// This is `GaugeStyle`'s documentation example, kept here rather than only in
/// the doc comment so the shape a reader is taught is a shape the suite
/// compiles. Before `GaugeStyle` became a protocol this file could not build:
/// "inheritance from non-protocol type 'GaugeStyle'".
private struct BlocksGaugeStyle: GaugeStyle {
    func makeBody(configuration: Configuration) -> some View {
        let filled = Int((configuration.value * 5).rounded())
        return HStack(spacing: 1) {
            configuration.label
            Text(String(repeating: "▰", count: filled) + String(repeating: "▱", count: 5 - filled))
        }
    }
}

/// A custom style that places every label the configuration carries, so a test
/// can see which of the five reached it.
private struct EveryLabelGaugeStyle: GaugeStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
            configuration.currentValueLabel
            configuration.minimumValueLabel
            configuration.maximumValueLabel
        }
    }
}

@MainActor
@Suite("Custom GaugeStyle")
struct CustomGaugeStyleTests {

    @Test("A custom style draws the gauge through makeBody(configuration:)")
    func customStyleRenders() {
        let text = renderToBuffer(
            Gauge(value: 0.6) { Text("CPU") }.gaugeStyle(BlocksGaugeStyle()),
            context: makeRenderContext(width: 30, height: 4)
        ).lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("CPU"))
        #expect(text.contains("▰▰▰▱▱"))  // 0.6 × 5, rounded
        // And nothing of the built-in meter survives underneath it.
        #expect(!text.contains("▓"))
        #expect(!text.contains("░"))
    }

    @Test("A built-in style still renders procedurally, not through makeBody")
    func builtInStyleUnaffected() {
        let text = renderToBuffer(
            Gauge(value: 0.6) { Text("CPU") }.gaugeStyle(.linearCapacity),
            context: makeRenderContext(width: 30, height: 4)
        ).lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("▓"))
        #expect(!text.contains("▰"))
    }

    @Test("`.automatic` resolves to the same shaded meter as `.linearCapacity`")
    func automaticResolvesToLinearCapacity() {
        func lines(_ style: some GaugeStyle) -> [String] {
            renderToBuffer(
                Gauge(value: 0.42) { Text("CPU") }.gaugeStyle(style),
                context: makeRenderContext(width: 30, height: 4)
            ).lines.map { $0.stripped }
        }
        #expect(lines(.automatic) == lines(.linearCapacity))
    }

    @Test("The configuration carries the normalized value, not the raw one")
    func configurationValueIsNormalized() {
        // 90 in 60...180 is 0.25 → one block of five.
        let text = renderToBuffer(
            Gauge(value: 90.0, in: 60.0...180.0) { EmptyView() }.gaugeStyle(BlocksGaugeStyle()),
            context: makeRenderContext(width: 30, height: 4)
        ).lines.map { $0.stripped }.joined()
        #expect(text.contains("▰▱▱▱▱"))
    }

    @Test("Labels the gauge was not given arrive as nil, not as empty views")
    func absentLabelsAreNil() {
        // Built with a label and a current-value label only: a style that places
        // all four must draw two rows, not four.
        let twoLabels = renderToBuffer(
            Gauge(value: 0.5) {
                Text("L")
            } currentValueLabel: {
                Text("50%")
            }
            .gaugeStyle(EveryLabelGaugeStyle()),
            context: makeRenderContext(width: 30, height: 8))
        #expect(twoLabels.height == 2)
        let joined = twoLabels.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(joined.contains("L"))
        #expect(joined.contains("50%"))

        // All four supplied: four rows.
        let fourLabels = renderToBuffer(
            Gauge(value: 0.5, in: 0...100) {
                Text("L")
            } currentValueLabel: {
                Text("50%")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("100")
            }
            .gaugeStyle(EveryLabelGaugeStyle()),
            context: makeRenderContext(width: 30, height: 8))
        #expect(fourLabels.height == 4)
    }

    @Test("measure == render: a custom style reports the size its body draws")
    func customStyleSizeMatchesRender() {
        let gauge = Gauge(value: 0.6) { Text("CPU") }.gaugeStyle(BlocksGaugeStyle())
        let context = makeRenderContext(width: 40, height: 4)
        let measured = measureChild(gauge, proposal: ProposedSize(width: 40, height: nil), context: context)
        let rendered = renderToBuffer(gauge, context: context)
        #expect(measured.height == rendered.height)
        #expect(measured.width == rendered.width)
        // And it is the BODY's size, not the linear meter's. Without this the
        // test passes against a `_GaugeCore` that ignores custom styles
        // altogether: the built-in bar measures and renders at the full
        // proposal, so the two agree there too and the assertions above are
        // vacuous. `CPU` + a space + five blocks is nine cells, well under 40.
        #expect(rendered.width < 40, "a custom body hugs its content: \(rendered.width)")
        #expect(measured.width < 40)
    }
}
