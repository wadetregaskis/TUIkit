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
