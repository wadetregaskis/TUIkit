//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Gauge.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Gauge

/// A view that shows a value within a range.
///
/// Mirrors SwiftUI's `Gauge`. Unlike ``ProgressView`` (which measures progress
/// toward completion), a gauge shows where a value sits between a lower and
/// upper bound — with an optional label, current-value label, and
/// minimum/maximum bound labels.
///
/// A gauge is display-only: it takes no focus and has no interaction.
///
/// ## Visual output
///
/// The default (``GaugeStyle/linearCapacity``) is a shaded horizontal meter —
/// deliberately distinct from ``ProgressView``'s solid bar and ``Slider``'s
/// knob-on-a-rail:
///
/// ```
/// CPU                                   42%
/// 0 ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░ 100
/// ```
///
/// - **Line 1** (when a label or current-value label is present): the label
///   left-aligned, the current-value label right-aligned.
/// - **Line 2**: the minimum-value label, the bar, and the maximum-value label.
///
/// Other styles are selected with ``SwiftUI/View/gaugeStyle(_:)`` — see
/// ``GaugeStyle`` for the linear, accessory-linear and circular variants.
///
/// ## Examples
///
/// ```swift
/// Gauge(value: 0.42) { Text("CPU") }
///
/// Gauge(value: 0.7) { Text("Load") }
///     .gaugeStyle(.accessoryCircular)
///
/// Gauge(value: bpm, in: 60...180) {
///     Text("Heart rate")
/// } currentValueLabel: {
///     Text("\(Int(bpm)) BPM")
/// } minimumValueLabel: {
///     Text("60")
/// } maximumValueLabel: {
///     Text("180")
/// }
/// ```
public struct Gauge<Label: View, CurrentValueLabel: View, BoundsLabel: View>: View {
    /// The normalized position of the value within its bounds (0.0–1.0).
    let fraction: Double

    /// The label describing what the gauge measures.
    let label: Label

    /// The label showing the current value (right-aligned above the bar).
    let currentValueLabel: CurrentValueLabel?

    /// The label for the lower bound (left of the bar).
    let minimumValueLabel: BoundsLabel?

    /// The label for the upper bound (right of the bar).
    let maximumValueLabel: BoundsLabel?

    public var body: some View {
        _GaugeCore(
            fraction: fraction,
            label: label,
            currentValueLabel: currentValueLabel,
            minimumValueLabel: minimumValueLabel,
            maximumValueLabel: maximumValueLabel
        )
    }
}

// MARK: - Initializers

extension Gauge {
    /// Creates a gauge with a label, current-value label, and bound labels.
    ///
    /// - Parameters:
    ///   - value: The value to show.
    ///   - bounds: The range the value sits within (default `0...1`).
    ///   - label: A view describing what the gauge measures.
    ///   - currentValueLabel: A view showing the current value.
    ///   - minimumValueLabel: A view labelling the lower bound.
    ///   - maximumValueLabel: A view labelling the upper bound.
    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel,
        @ViewBuilder minimumValueLabel: () -> BoundsLabel,
        @ViewBuilder maximumValueLabel: () -> BoundsLabel
    ) {
        self.fraction = Gauge.normalized(value: value, in: bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
    }
}

extension Gauge where BoundsLabel == EmptyView {
    /// Creates a gauge with a label and a current-value label.
    ///
    /// - Parameters:
    ///   - value: The value to show.
    ///   - bounds: The range the value sits within (default `0...1`).
    ///   - label: A view describing what the gauge measures.
    ///   - currentValueLabel: A view showing the current value.
    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.fraction = Gauge.normalized(value: value, in: bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = nil
        self.maximumValueLabel = nil
    }
}

extension Gauge where CurrentValueLabel == EmptyView, BoundsLabel == EmptyView {
    /// Creates a gauge with only a label.
    ///
    /// - Parameters:
    ///   - value: The value to show.
    ///   - bounds: The range the value sits within (default `0...1`).
    ///   - label: A view describing what the gauge measures.
    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label
    ) {
        self.fraction = Gauge.normalized(value: value, in: bounds)
        self.label = label()
        self.currentValueLabel = nil
        self.minimumValueLabel = nil
        self.maximumValueLabel = nil
    }
}

extension Gauge where Label == Text, CurrentValueLabel == EmptyView, BoundsLabel == EmptyView {
    /// Creates a gauge with a string title.
    ///
    /// - Parameters:
    ///   - title: A string describing what the gauge measures.
    ///   - value: The value to show.
    ///   - bounds: The range the value sits within (default `0...1`).
    public init<S: StringProtocol, V: BinaryFloatingPoint>(
        _ title: S,
        value: V,
        in bounds: ClosedRange<V> = 0...1
    ) {
        self.init(value: value, in: bounds) { Text(String(title)) }
    }
}

// MARK: - Normalization Helper

extension Gauge {
    /// Normalizes a value within bounds to a 0.0–1.0 fraction, clamping.
    static func normalized<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V>) -> Double {
        let lower = Double(bounds.lowerBound)
        let upper = Double(bounds.upperBound)
        guard upper > lower else { return 0 }
        return min(1, max(0, (Double(value) - lower) / (upper - lower)))
    }
}

// MARK: - Internal Core View

/// Internal view that renders the gauge: an optional label line above a bar
/// flanked by optional bound labels.
private struct _GaugeCore<Label: View, CurrentValueLabel: View, BoundsLabel: View>: View, Renderable, Layoutable {
    let fraction: Double
    let label: Label
    let currentValueLabel: CurrentValueLabel?
    let minimumValueLabel: BoundsLabel?
    let maximumValueLabel: BoundsLabel?

    var body: Never {
        fatalError("_GaugeCore renders via Renderable")
    }

    /// A linear gauge fills the available width; a circular gauge hugs its dial
    /// and value. Either way the height is the label line (when present) plus
    /// the indicator row. Reporting this directly (rather than rendering to
    /// measure) keeps `sizeThatFits` and `renderToBuffer` in agreement.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if context.environment.gaugeStyle.isCircular {
            let size = circularSize(context: context)
            return ViewSize(
                width: size.width, height: size.height, isWidthFlexible: false, isHeightFlexible: false)
        }
        let width = proposal.width ?? context.availableWidth
        let height = visibleLabelLine(width: width, context: context) != nil ? 2 : 1
        return ViewSize(width: width, height: height, isWidthFlexible: true, isHeightFlexible: false)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let style = context.environment.gaugeStyle
        if style.isCircular {
            return renderCircular(capacity: style == .accessoryCircularCapacity, palette: palette, context: context)
        }
        let width = context.availableWidth
        var lines: [String] = []
        if let labelLine = visibleLabelLine(width: width, context: context) {
            lines.append(labelLine)
        }
        lines.append(renderBarLine(width: width, style: style, palette: palette, context: context))
        return FrameBuffer(lines: lines)
    }

    // MARK: - Rendering

    /// Renders a label view to its first visible line, or `""` for an
    /// `EmptyView` / absent label.
    private func inlineText<V: View>(_ view: V?, context: RenderContext) -> String {
        guard let view, !(view is EmptyView) else { return "" }
        return TUIkit.renderToBuffer(view, context: context).lines.first ?? ""
    }

    /// The bar glyph a linear gauge style draws with. The default (a shaded
    /// meter) is deliberately distinct from ``ProgressView`` (solid blocks) and
    /// ``Slider`` (a knob on a rail) so the three read differently at a glance.
    private func trackStyle(for style: GaugeStyle) -> TrackStyle {
        switch style {
        case .accessoryLinear: return .dot  // a marker on a thin line
        case .accessoryLinearCapacity: return .blockFine  // slim, sub-cell precise
        default: return .shade  // linearCapacity / automatic — a shaded meter
        }
    }

    /// The label line (label left, current-value right) if it has visible
    /// content, else `nil` — so a blank label doesn't push the bar down.
    private func visibleLabelLine(width: Int, context: RenderContext) -> String? {
        let labelText = inlineText(label, context: context)
        let valueText = inlineText(currentValueLabel, context: context)
        guard !(labelText.stripped.allSatisfy(\.isWhitespace) && valueText.stripped.allSatisfy(\.isWhitespace))
        else { return nil }
        let gap = max(1, width - labelText.strippedLength - valueText.strippedLength)
        return labelText + String(asciiSpaces(gap)) + valueText
    }

    /// The bar line: `min bar max`, with the bar taking whatever width the
    /// bound labels leave.
    private func renderBarLine(
        width: Int, style: GaugeStyle, palette: any Palette, context: RenderContext
    ) -> String {
        let minText = inlineText(minimumValueLabel, context: context)
        let maxText = inlineText(maximumValueLabel, context: context)
        let minPart = minText.strippedLength > 0 ? minText + " " : ""
        let maxPart = maxText.strippedLength > 0 ? " " + maxText : ""
        let barWidth = max(1, width - minPart.strippedLength - maxPart.strippedLength)
        let bar = TrackRenderer.render(
            fraction: fraction,
            width: barWidth,
            style: trackStyle(for: style),
            filledColor: palette.foregroundSecondary,
            emptyColor: palette.foregroundTertiary,
            accentColor: palette.accent
        )
        return minPart + bar + maxPart
    }

    // MARK: - Circular rendering

    /// The circular-dial rendering: a pie glyph beside the current value, with
    /// the label (if any) on the row below. `capacity` puts the value first.
    private func renderCircular(capacity: Bool, palette: any Palette, context: RenderContext) -> FrameBuffer {
        let dial = ANSIRenderer.colorize(String(GaugePieDial.glyph(for: fraction)), foreground: palette.accent)
        let valueText = inlineText(currentValueLabel, context: context)
        var row = dial
        if valueText.strippedLength > 0 {
            row = capacity ? valueText + " " + dial : dial + " " + valueText
        }
        var lines = [row]
        let labelText = inlineText(label, context: context)
        if labelText.strippedLength > 0 {
            lines.append(labelText)
        }
        return FrameBuffer(lines: lines)
    }

    /// The natural size of the circular dial (kept in step with
    /// `renderCircular`).
    private func circularSize(context: RenderContext) -> (width: Int, height: Int) {
        let valueWidth = inlineText(currentValueLabel, context: context).strippedLength
        let rowWidth = valueWidth > 0 ? 1 + 1 + valueWidth : 1  // dial + space + value
        let labelWidth = inlineText(label, context: context).strippedLength
        let width = max(1, max(rowWidth, labelWidth))
        let height = labelWidth > 0 ? 2 : 1
        return (width, height)
    }
}

// MARK: - GaugeStyle helpers

extension GaugeStyle {
    /// Whether this style renders as a compact circular dial rather than a bar.
    fileprivate var isCircular: Bool {
        self == .accessoryCircular || self == .accessoryCircularCapacity
    }
}

/// The pie glyphs a circular gauge dial fills through, and the nearest one for
/// a fraction. A free helper because `_GaugeCore` is generic (which can't hold
/// a static stored property).
private enum GaugePieDial {
    /// 0 % / 25 % / 50 % / 75 % / 100 %.
    static let glyphs: [Character] = ["○", "◔", "◑", "◕", "●"]

    static func glyph(for fraction: Double) -> Character {
        let index = min(glyphs.count - 1, max(0, Int((fraction * 4).rounded())))
        return glyphs[index]
    }
}
