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
            if style == .accessoryCircularTiny {
                return renderCircularTiny(palette: palette, context: context)
            }
            return renderCircularDial(
                capacity: style == .accessoryCircularCapacity, palette: palette, context: context)
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
        case .accessoryLinear: return .marker  // position only, no fill
        case .accessoryLinearCapacity: return .blockFine  // fills min→value, sub-cell precise
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

    /// The tiny circular dial: a single pie glyph beside the current value, with
    /// the label (if any) on the row below.
    private func renderCircularTiny(palette: any Palette, context: RenderContext) -> FrameBuffer {
        let dial = ANSIRenderer.colorize(String(GaugePieDial.glyph(for: fraction)), foreground: palette.accent)
        let valueText = inlineText(currentValueLabel, context: context)
        var lines = [valueText.strippedLength > 0 ? dial + " " + valueText : dial]
        let labelText = inlineText(label, context: context)
        if labelText.strippedLength > 0 {
            lines.append(labelText)
        }
        return FrameBuffer(lines: lines)
    }

    /// The full ring dial: a rounded box whose border is the gauge track and
    /// whose centre holds the value. For `capacity` the border fills clockwise
    /// from the top-left, proportional to the value; otherwise a single bright
    /// cell marks the value's position on the ring. The label (if any) sits
    /// below. Uses more space than the tiny dial, for clarity.
    private func renderCircularDial(
        capacity: Bool, palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let valueText = inlineText(currentValueLabel, context: context)
        // Fixed interior width so the dial never resizes as the value changes
        // ("67%" and "100%" both fit); only an unusually wide value grows it.
        let inner = max(gaugeCircularInnerWidth, valueText.strippedLength)
        let dim = palette.foregroundTertiary
        let accent = palette.accent

        // Border glyphs per cell of the 3×(inner+2) box.
        var glyphs: [[Character]] = [
            ["╭"] + Array(repeating: "─", count: inner) + ["╮"],
            ["│"] + Array(repeating: " ", count: inner) + ["│"],
            ["╰"] + Array(repeating: "─", count: inner) + ["╯"],
        ]
        // A centred break at the bottom edge shows where the ring starts and
        // ends. It is one cell when the ring's width (inner + 2) is odd and two
        // when it is even; since inner + 2 shares inner's parity, that is:
        let gapCells = inner.isMultiple(of: 2) ? 2 : 1
        let gapStart = 1 + (inner - gapCells) / 2  // symmetric: same parity as inner
        let gapCols = Set(gapStart..<(gapStart + gapCells))
        for col in gapCols { glyphs[2][col] = " " }

        // Perimeter cells in clockwise order from the top-left corner. The
        // bottom-centre break is excluded, so the fill arc and the position
        // marker never count or land on a gap cell and the ring visibly opens
        // there.
        var perimeter: [(r: Int, c: Int)] = []
        for col in 0...(inner + 1) { perimeter.append((0, col)) }  // top L→R
        perimeter.append((1, inner + 1))  // right side
        for col in stride(from: inner + 1, through: 0, by: -1) where !gapCols.contains(col) {
            perimeter.append((2, col))  // bottom R→L, skipping the break
        }
        perimeter.append((1, 0))  // left side

        // Which perimeter cells are "on" (accent): a filled arc for capacity,
        // a single marker for position.
        var isOn = [Bool](repeating: false, count: perimeter.count)
        if capacity {
            let filled = Int((fraction * Double(perimeter.count)).rounded())
            for index in 0..<min(filled, perimeter.count) { isOn[index] = true }
        } else {
            let marker = Int((fraction * Double(perimeter.count - 1)).rounded())
            isOn[min(max(0, marker), perimeter.count - 1)] = true
        }
        var colorAt: [String: Color] = [:]
        for (index, cell) in perimeter.enumerated() {
            colorAt["\(cell.r),\(cell.c)"] = isOn[index] ? accent : dim
        }

        // The value is right-aligned within the middle row's interior.
        let stripped = valueText.stripped
        let leftPad = max(0, inner - valueText.strippedLength)
        for (offset, char) in stripped.enumerated() where 1 + leftPad + offset <= inner {
            glyphs[1][1 + leftPad + offset] = char
        }

        var lines: [String] = []
        for row in 0..<3 {
            var line = ""
            for col in 0...(inner + 1) {
                let ch = String(glyphs[row][col])
                if let color = colorAt["\(row),\(col)"] {
                    line += ANSIRenderer.colorize(ch, foreground: color)
                } else {
                    // Interior: the value text (or a blank).
                    line += ch == " " ? " " : ANSIRenderer.colorize(ch, foreground: palette.foreground)
                }
            }
            lines.append(line)
        }
        let labelText = inlineText(label, context: context)
        if labelText.strippedLength > 0 {
            lines.append(labelText)
        }
        return FrameBuffer(lines: lines)
    }

    /// The natural size of a circular gauge (kept in step with the renderers).
    private func circularSize(context: RenderContext) -> (width: Int, height: Int) {
        let valueWidth = inlineText(currentValueLabel, context: context).strippedLength
        let labelWidth = inlineText(label, context: context).strippedLength
        if context.environment.gaugeStyle == .accessoryCircularTiny {
            let rowWidth = valueWidth > 0 ? 1 + 1 + valueWidth : 1  // dial + space + value
            return (max(1, max(rowWidth, labelWidth)), labelWidth > 0 ? 2 : 1)
        }
        // Ring dial: a 3-row box of width inner+2, plus a label row. Mirrors
        // renderCircularDial's fixed interior width so measure == render.
        let inner = max(gaugeCircularInnerWidth, valueWidth)
        let width = max(inner + 2, labelWidth)
        return (width, labelWidth > 0 ? 4 : 3)
    }
}

// MARK: - GaugeStyle helpers

extension GaugeStyle {
    /// Whether this style renders as a circular dial rather than a bar.
    fileprivate var isCircular: Bool {
        self == .accessoryCircular || self == .accessoryCircularCapacity
            || self == .accessoryCircularTiny
    }
}

/// The fixed interior width of the ring dial, sized so the widest common value
/// ("100%") always fits and the dial never resizes as the value changes. A free
/// constant because `_GaugeCore` is generic (which can't hold a static stored
/// property).
private let gaugeCircularInnerWidth = 4

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
