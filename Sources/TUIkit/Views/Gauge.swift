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
/// ```
/// CPU                                   42%
/// 0 ████████████▌░░░░░░░░░░░░░░░░░░░░░░░ 100
/// ```
///
/// - **Line 1** (when a label or current-value label is present): the label
///   left-aligned, the current-value label right-aligned.
/// - **Line 2**: the minimum-value label, the bar, and the maximum-value label.
///
/// ## Examples
///
/// ```swift
/// Gauge(value: 0.42) { Text("CPU") }
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

    /// The visual style of the bar (shared with ``ProgressView`` via
    /// ``TrackStyle``).
    var style: TrackStyle

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
            style: style,
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
        self.style = .block
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
        self.style = .block
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
        self.style = .block
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

// MARK: - Style Modifier

extension Gauge {
    /// Sets the visual style of the gauge's bar.
    ///
    /// TUIkit-specific: reuses the ``TrackStyle`` shared with ``ProgressView``.
    /// (SwiftUI's `gaugeStyle(_:)` takes a `GaugeStyle`, whose linear/circular
    /// variants don't map onto a single terminal row.)
    ///
    /// - Parameter style: The bar style.
    /// - Returns: A gauge with the specified bar style.
    public func gaugeStyle(_ style: TrackStyle) -> Gauge {
        var copy = self
        copy.style = style
        return copy
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
    let style: TrackStyle
    let label: Label
    let currentValueLabel: CurrentValueLabel?
    let minimumValueLabel: BoundsLabel?
    let maximumValueLabel: BoundsLabel?

    var body: Never {
        fatalError("_GaugeCore renders via Renderable")
    }

    /// The bar fills the available width; the height is one line for the bar
    /// plus one for the label line when it has visible content. Reporting this
    /// directly (rather than rendering to measure) keeps `sizeThatFits` and
    /// `renderToBuffer` in agreement.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let width = proposal.width ?? context.availableWidth
        let height = visibleLabelLine(width: width, context: context) != nil ? 2 : 1
        return ViewSize(width: width, height: height, isWidthFlexible: true, isHeightFlexible: false)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let width = context.availableWidth
        var lines: [String] = []
        if let labelLine = visibleLabelLine(width: width, context: context) {
            lines.append(labelLine)
        }
        lines.append(renderBarLine(width: width, palette: palette, context: context))
        return FrameBuffer(lines: lines)
    }

    // MARK: - Rendering

    /// Renders a label view to its first visible line, or `""` for an
    /// `EmptyView` / absent label.
    private func inlineText<V: View>(_ view: V?, context: RenderContext) -> String {
        guard let view, !(view is EmptyView) else { return "" }
        return TUIkit.renderToBuffer(view, context: context).lines.first ?? ""
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
    private func renderBarLine(width: Int, palette: any Palette, context: RenderContext) -> String {
        let minText = inlineText(minimumValueLabel, context: context)
        let maxText = inlineText(maximumValueLabel, context: context)
        let minPart = minText.strippedLength > 0 ? minText + " " : ""
        let maxPart = maxText.strippedLength > 0 ? " " + maxText : ""
        let barWidth = max(1, width - minPart.strippedLength - maxPart.strippedLength)
        let bar = TrackRenderer.render(
            fraction: fraction,
            width: barWidth,
            style: style,
            filledColor: palette.foregroundSecondary,
            emptyColor: palette.foregroundTertiary,
            accentColor: palette.accent
        )
        return minPart + bar + maxPart
    }
}
