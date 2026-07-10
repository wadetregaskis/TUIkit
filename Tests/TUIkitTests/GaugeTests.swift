//  🖥️ TUIKit — Terminal UI Kit for Swift
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
        #expect((buffer.lines.first?.stripped ?? "").contains("▓"))
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
