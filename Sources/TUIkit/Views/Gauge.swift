//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// Other styles are selected with ``View/gaugeStyle(_:)`` — see
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
    /// Creates a gauge with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for text describing what the gauge measures.
    ///   - value: The value to show.
    ///   - bounds: The range the value sits within (default `0...1`).
    public init<V: BinaryFloatingPoint>(
        _ titleKey: LocalizedStringKey,
        value: V,
        in bounds: ClosedRange<V> = 0...1
    ) {
        self.init(titleKey.localized, value: value, in: bounds)
    }

    /// Creates a gauge with a string title, displayed as written.
    ///
    /// - Parameters:
    ///   - title: A string describing what the gauge measures.
    ///   - value: The value to show.
    ///   - bounds: The range the value sits within (default `0...1`).
    @_disfavoredOverload
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

/// Child-identity indices for `_GaugeCore`'s four caller-supplied label
/// slots. File scope: a generic type cannot hold static storage.
private enum GaugeLabelSlot: Int {
    case label = 0
    case currentValue = 1
    case minimumValue = 2
    case maximumValue = 3
}

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
        let barRow = lines.count
        let bar = renderBarLine(width: width, style: style, palette: palette, context: context)
        lines.append(bar.line)
        var buffer = FrameBuffer(lines: lines)
        buffer.opacityRegions += bar.claims.map { $0.shifted(byX: 0, y: barRow) }
        return buffer
    }

    // MARK: - Rendering

    /// Renders a label view to its first visible line, or `""` for an
    /// `EmptyView` / absent label.
    ///
    /// The render happens under the slot's OWN child identity, not the core's.
    /// The four labels are caller-supplied `@ViewBuilder` content, and at one
    /// identity a composite label's first `@State` binds
    /// `StateKey(coreIdentity, 0)` — the same key for all four: a matching
    /// type silently shares one box, and a mismatched one makes
    /// `storage(for:)` replace the box every render, so both labels read
    /// their defaults every frame. The collision class 778699f5 closed and
    /// 6ab904e7 carried to ProgressView's two labels; these sites were missed
    /// instances. `minimumValueLabel` and `maximumValueLabel` are the same
    /// generic parameter, so the type could never have told them apart — the
    /// slot index is what does.
    private func inlineText<V: View>(
        _ view: V?, slot: GaugeLabelSlot, context: RenderContext
    ) -> String {
        guard let view, !(view is EmptyView) else { return "" }
        let slotContext = context.withChildIdentity(
            erasedType: type(of: view), index: slot.rawValue)
        return TUIkit.renderToBuffer(view, context: slotContext).lines.first ?? ""
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
        // The caption goes under `.labelsHidden()`; the bound and current-value
        // labels stay, being readouts of the value rather than names for it.
        // See the same split in `ProgressView.renderLabelLine`.
        let labelText =
            context.environment.controlLabelsAreHidden ? "" : inlineText(label, slot: .label, context: context)
        let valueText = inlineText(currentValueLabel, slot: .currentValue, context: context)
        guard !(labelText.stripped.allSatisfy(\.isWhitespace) && valueText.stripped.allSatisfy(\.isWhitespace))
        else { return nil }
        let gap = max(1, width - labelText.strippedLength - valueText.strippedLength)
        return labelText + String(asciiSpaces(gap)) + valueText
    }

    /// The bar line: `min bar max`, with the bar taking whatever width the
    /// bound labels leave.
    /// - Returns: The line, and the bar's claims already shifted past the minimum
    ///   label — the offset is known only here, and re-deriving `minPart` in the
    ///   caller is exactly the divergence one function per rule exists to prevent.
    private func renderBarLine(
        width: Int, style: GaugeStyle, palette: any Palette, context: RenderContext
    ) -> (line: String, claims: [OpacityRegion]) {
        let minText = inlineText(minimumValueLabel, slot: .minimumValue, context: context)
        let maxText = inlineText(maximumValueLabel, slot: .maximumValue, context: context)
        let minPart = minText.strippedLength > 0 ? minText + " " : ""
        let maxPart = maxText.strippedLength > 0 ? " " + maxText : ""
        let barWidth = max(1, width - minPart.strippedLength - maxPart.strippedLength)
        let bar = TrackRenderer.render(
            fraction: fraction,
            width: barWidth,
            style: trackStyle(for: style),
            filledColor: palette.foregroundSecondary,
            emptyColor: palette.foregroundTertiary,
            accentColor: palette.accent,
            fillScaling: context.environment.trackGradientScaling,
            emptyScaling: context.environment.trackBackgroundGradientScaling,
            palette: palette,
            graphics: context.gradientGraphics(token: "track-\(context.identity.path)")
        )
        return (
            minPart + bar.text + maxPart,
            bar.claims.map { $0.shifted(byX: minPart.strippedLength, y: 0) })
    }

    // MARK: - Circular rendering

    /// The tiny circular dial: a single pie glyph beside the current value, with
    /// the label (if any) on the row below.
    private func renderCircularTiny(palette: any Palette, context: RenderContext) -> FrameBuffer {
        // Through `ClaimingRow` rather than `colorize` directly, so a translucent
        // `.tint` states its opaque spelling and sends its alpha up as a region —
        // this dial is one of the four emit sites §31.4 found bypassing
        // `TrackRenderer` entirely.
        var row = ClaimingRow()
        row.append(
            String(GaugePieDial.glyph(for: fraction)), cells: 1, ink: palette.accent)
        let valueText = inlineText(currentValueLabel, slot: .currentValue, context: context)
        if valueText.strippedLength > 0 {
            row.skip(cells: 1)
            row.appendFinished(valueText, cells: valueText.strippedLength)
        }
        var lines = [row.text]
        let labelText = inlineText(label, slot: .label, context: context)
        if labelText.strippedLength > 0 {
            lines.append(labelText)
        }
        var buffer = FrameBuffer(lines: lines)
        buffer.opacityRegions += row.claims
        return buffer
    }

    /// The full ring dial: a rounded box whose border is the gauge track and
    /// whose centre holds the value. For `capacity` the border fills clockwise
    /// from the top-left, proportional to the value; otherwise a single bright
    /// cell marks the value's position on the ring. The label (if any) sits
    /// below. Uses more space than the tiny dial, for clarity.
    private func renderCircularDial(
        capacity: Bool, palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let valueText = inlineText(currentValueLabel, slot: .currentValue, context: context)
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

        // Perimeter cells in the order a SPEEDOMETER sweeps: starting at the
        // arc's most counter-clockwise cell — just left of the bottom-centre
        // break — and progressing clockwise all the way around to the cell
        // just right of the break. The break itself is excluded, so the fill
        // arc and the position marker never land on a gap cell and the ring
        // visibly opens there.
        var perimeter: [(r: Int, c: Int)] = []
        for col in stride(from: gapStart - 1, through: 0, by: -1) {
            perimeter.append((2, col))  // bottom-left arc: break → corner
        }
        perimeter.append((1, 0))  // left side, upward
        for col in 0...(inner + 1) { perimeter.append((0, col)) }  // top L→R
        perimeter.append((1, inner + 1))  // right side, downward
        for col in stride(from: inner + 1, through: gapStart + gapCells, by: -1) {
            perimeter.append((2, col))  // bottom-right arc: corner → break
        }

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

        var lines: [String] = []
        var claims: [OpacityRegion] = []
        for row in 0..<3 {
            // The middle row is assembled by CELLS, not grid columns. The glyph
            // grid holds one Character per column, and the ring's own glyphs
            // are all one cell wide — but the VALUE is arbitrary text, and a
            // wide character (CJK, emoji, a fun unit) in it occupies two cells
            // in one column, shoving the right wall out of the ring. `inner`
            // and `leftPad` are already cell counts (`strippedLength` sums
            // terminal widths), so composing wall + pad + value + wall directly
            // keeps all three rows the same visible width.
            var drawn = ClaimingRow()
            if row == 1 {
                let stripped = valueText.stripped
                let leftPad = max(0, inner - valueText.strippedLength)
                func wall(_ col: Int) {
                    drawn.append(
                        String(glyphs[1][col]), cells: 1, ink: colorAt["1,\(col)"])
                }
                wall(0)
                drawn.skip(cells: leftPad)
                if !stripped.isEmpty {
                    drawn.append(
                        stripped, cells: valueText.strippedLength, ink: palette.foreground)
                }
                wall(inner + 1)
            } else {
                for col in 0...(inner + 1) {
                    drawn.append(
                        String(glyphs[row][col]), cells: 1, ink: colorAt["\(row),\(col)"])
                }
            }
            claims += drawn.claims.map { $0.shifted(byX: 0, y: row) }
            lines.append(drawn.text)
        }
        let labelText = inlineText(label, slot: .label, context: context)
        if labelText.strippedLength > 0 {
            lines.append(labelText)
        }
        var buffer = FrameBuffer(lines: lines)
        buffer.opacityRegions += claims
        return buffer
    }

    /// The natural size of a circular gauge (kept in step with the renderers).
    private func circularSize(context: RenderContext) -> (width: Int, height: Int) {
        let valueWidth = inlineText(currentValueLabel, slot: .currentValue, context: context).strippedLength
        let labelWidth = inlineText(label, slot: .label, context: context).strippedLength
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
