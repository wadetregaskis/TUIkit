//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ProgressView.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - ProgressView

/// A view that shows the progress toward completion of a task.
///
/// `ProgressView` renders a horizontal bar using Unicode block characters.
/// It matches SwiftUI's determinate progress API with `value` and `total`
/// parameters.
///
/// ## Visual Output
///
/// ```
/// Downloading                  50%
/// ████████████████▌░░░░░░░░░░░░░░░
/// ```
///
/// - **Line 1** (optional): Label (left-aligned) + CurrentValueLabel (right-aligned)
/// - **Line 2**: Progress bar
///
/// ## Styles
///
/// Set the style via the `progressViewStyle(_:)` modifier:
///
/// ```swift
/// ProgressView(value: 0.5)
///     .progressViewStyle(.shade)
/// ```
///
/// See ``TrackStyle`` for all available styles.
///
/// ## Examples
///
/// ```swift
/// // Simple progress bar (50%)
/// ProgressView(value: 0.5)
///
/// // With total
/// ProgressView(value: 3, total: 10)
///
/// // With string title
/// ProgressView("Loading...", value: 0.75)
///
/// // With label and current value label
/// ProgressView(value: 0.5) {
///     Text("Downloading")
/// } currentValueLabel: {
///     Text("50%")
/// }
/// ```
///
/// ## Colors
///
/// | Part | Color |
/// |------|-------|
/// | Filled bar | `palette.foregroundSecondary` |
/// | Empty bar | `palette.foregroundTertiary` |
/// | Dot head (`.dot` style only) | `palette.accent` |
/// | Label | inherited from environment |
/// | CurrentValueLabel | inherited from environment |
///
/// ## Size Behavior
///
/// The bar fills the full `availableWidth`. When a label or currentValueLabel
/// is provided, the view is 2 lines tall; otherwise 1 line.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    /// The normalized fraction completed (0.0–1.0), or nil for indeterminate.
    let fractionCompleted: Double?

    /// The visual style of the progress bar.
    var style: TrackStyle

    /// The label view displayed above the bar (left-aligned).
    let label: Label?

    /// The current value label displayed above the bar (right-aligned).
    let currentValueLabel: CurrentValueLabel?

    public var body: some View {
        _ProgressViewCore(
            fractionCompleted: fractionCompleted,
            style: style,
            label: label,
            currentValueLabel: currentValueLabel
        )
    }
}

// MARK: - Indeterminate Initializers

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    /// Creates an indeterminate progress view.
    ///
    /// Use this when a task's progress cannot be measured. The bar shows a
    /// highlighted segment sweeping continuously across the track.
    public init() {
        self.fractionCompleted = nil
        self.style = .block
        self.label = nil
        self.currentValueLabel = nil
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// Creates an indeterminate progress view with a string title.
    ///
    /// - Parameter title: A string that describes the task in progress.
    public init<S: StringProtocol>(_ title: S) {
        self.fractionCompleted = nil
        self.style = .block
        self.label = Text(String(title))
        self.currentValueLabel = nil
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    /// Creates an indeterminate progress view with a custom label.
    ///
    /// - Parameter label: A view that describes the task in progress.
    public init(@ViewBuilder label: () -> Label) {
        self.fractionCompleted = nil
        self.style = .block
        self.label = label()
        self.currentValueLabel = nil
    }
}

// MARK: - Initializers (value/total)

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    /// Creates a progress view with a fractional completion value.
    ///
    /// - Parameters:
    ///   - value: The completed amount (nil for indeterminate).
    ///   - total: The total amount (default: 1.0).
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        self.fractionCompleted = ProgressView.normalizedFraction(value: value, total: total)
        self.style = .block
        self.label = nil
        self.currentValueLabel = nil
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    /// Creates a progress view with a label.
    ///
    /// - Parameters:
    ///   - value: The completed amount (nil for indeterminate).
    ///   - total: The total amount (default: 1.0).
    ///   - label: A view that describes the task in progress.
    public init<V: BinaryFloatingPoint>(
        value: V?,
        total: V = 1.0,
        @ViewBuilder label: () -> Label
    ) {
        self.fractionCompleted = ProgressView.normalizedFraction(value: value, total: total)
        self.style = .block
        self.label = label()
        self.currentValueLabel = nil
    }
}

extension ProgressView {
    /// Creates a progress view with a label and current value label.
    ///
    /// - Parameters:
    ///   - value: The completed amount (nil for indeterminate).
    ///   - total: The total amount (default: 1.0).
    ///   - label: A view that describes the task in progress.
    ///   - currentValueLabel: A view showing the current progress value.
    public init<V: BinaryFloatingPoint>(
        value: V?,
        total: V = 1.0,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.fractionCompleted = ProgressView.normalizedFraction(value: value, total: total)
        self.style = .block
        self.label = label()
        self.currentValueLabel = currentValueLabel()
    }
}

// MARK: - String Title Initializer

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// Creates a progress view with a string title.
    ///
    /// - Parameters:
    ///   - title: A string that describes the task in progress.
    ///   - value: The completed amount (nil for indeterminate).
    ///   - total: The total amount (default: 1.0).
    public init<S: StringProtocol, V: BinaryFloatingPoint>(
        _ title: S,
        value: V?,
        total: V = 1.0
    ) {
        self.fractionCompleted = ProgressView.normalizedFraction(value: value, total: total)
        self.style = .block
        self.label = Text(String(title))
        self.currentValueLabel = nil
    }
}

// MARK: - Style Modifier

extension ProgressView {
    /// Sets the visual style of the progress view.
    ///
    /// ```swift
    /// ProgressView(value: 0.5)
    ///     .progressViewStyle(.shade)
    /// ```
    ///
    /// - Parameter style: The progress view style.
    /// - Returns: A progress view with the specified style.
    public func progressViewStyle(_ style: TrackStyle) -> ProgressView {
        var copy = self
        copy.style = style
        return copy
    }

    /// Sets the visual style of the progress view.
    ///
    /// - Parameter style: The progress view style.
    /// - Returns: A progress view with the specified style.
    /// - Note: Renamed to ``progressViewStyle(_:)`` for SwiftUI parity.
    @available(*, deprecated, renamed: "progressViewStyle(_:)")
    public func trackStyle(_ style: TrackStyle) -> ProgressView {
        progressViewStyle(style)
    }

    /// Sets the visual style of the progress view.
    ///
    /// - Parameter style: The progress view style.
    /// - Returns: A progress view with the specified style.
    /// - Note: Renamed to ``progressViewStyle(_:)`` for SwiftUI parity.
    @available(*, deprecated, renamed: "progressViewStyle(_:)")
    public func progressBarStyle(_ style: TrackStyle) -> ProgressView {
        progressViewStyle(style)
    }
}

// MARK: - Equatable Conformance

extension ProgressView: @preconcurrency Equatable where Label: Equatable, CurrentValueLabel: Equatable {
    public static func == (lhs: ProgressView<Label, CurrentValueLabel>, rhs: ProgressView<Label, CurrentValueLabel>) -> Bool {
        lhs.fractionCompleted == rhs.fractionCompleted && lhs.style == rhs.style && lhs.label == rhs.label
            && lhs.currentValueLabel == rhs.currentValueLabel
    }
}

// MARK: - Normalization Helper

extension ProgressView {
    /// Normalizes value/total to a 0.0–1.0 fraction, clamping out-of-range values.
    static func normalizedFraction<V: BinaryFloatingPoint>(value: V?, total: V) -> Double? {
        guard let value else { return nil }
        guard total > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(value) / Double(total)))
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of ProgressView.
private struct _ProgressViewCore<Label: View, CurrentValueLabel: View>: View, Renderable, Layoutable {
    let fractionCompleted: Double?
    let style: TrackStyle
    let label: Label?
    let currentValueLabel: CurrentValueLabel?

    var body: Never {
        fatalError("_ProgressViewCore renders via Renderable")
    }

    /// Whether a label line is drawn above the bar — shared by `sizeThatFits`
    /// and `renderToBuffer` so the height the two report cannot diverge.
    private var hasLabelLine: Bool {
        let hasLabel = label != nil && !(label is EmptyView)
        let hasValueLabel = currentValueLabel != nil && !(currentValueLabel is EmptyView)
        return hasLabel || hasValueLabel
    }

    /// The bar fills the available width; the height is one line for the bar plus
    /// one for the optional label line. Reporting this directly avoids the
    /// render-to-measure fallback — which rendered the whole bar (and, for an
    /// indeterminate bar, started its animation task) just to read back a size
    /// that is fully determined by the label's presence.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: proposal.width ?? context.availableWidth,
            height: hasLabelLine ? 2 : 1,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let width = context.availableWidth
        var lines: [String] = []

        // Label line (optional): label left, currentValueLabel right.
        if hasLabelLine {
            lines.append(
                renderLabelLine(
                    width: width,
                    palette: palette,
                    context: context
                )
            )
        }

        // Progress bar line
        lines.append(renderBarLine(width: width, palette: palette, context: context))

        // The indeterminate animation derives its phase from the wall clock, so
        // it only advances when the view is re-rendered over time. The run loop
        // is demand-driven (it won't re-render a static screen), so — like
        // Spinner — ask the scheduler to re-render this bar while it is on screen.
        // Keyed by the stable view identity: several indeterminate bars at this
        // rate coalesce onto a single render, and a bar that leaves the tree stops
        // re-declaring and is dropped. (Determinate bars don't animate — they make
        // no such request, so they drive no frames.)
        if fractionCompleted == nil {
            context.requestAnimation(
                token: "progress-indeterminate-\(context.identity.path)",
                frequency: 30)
        }

        return FrameBuffer(lines: lines)
    }

    // MARK: - Label Line Rendering

    /// Renders the label line with label left-aligned and currentValueLabel right-aligned.
    private func renderLabelLine(width: Int, palette: any Palette, context: RenderContext) -> String {
        let labelBuffer: FrameBuffer
        if let labelView = label, !(labelView is EmptyView) {
            labelBuffer = TUIkit.renderToBuffer(labelView, context: context)
        } else {
            labelBuffer = FrameBuffer()
        }

        let valueBuffer: FrameBuffer
        if let valueView = currentValueLabel, !(valueView is EmptyView) {
            valueBuffer = TUIkit.renderToBuffer(valueView, context: context)
        } else {
            valueBuffer = FrameBuffer()
        }

        let labelText = labelBuffer.lines.first ?? ""
        let valueText = valueBuffer.lines.first ?? ""

        let labelWidth = labelText.strippedLength
        let valueWidth = valueText.strippedLength
        let gap = max(1, width - labelWidth - valueWidth)

        return labelText + String(repeating: " ", count: gap) + valueText
    }

    // MARK: - Bar Line Rendering

    /// Renders the progress bar line — a determinate track, or an animated
    /// indeterminate sweep when there is no measurable progress.
    private func renderBarLine(width: Int, palette: any Palette, context: RenderContext) -> String {
        guard let fraction = fractionCompleted else {
            return IndeterminateRenderer.render(
                width: width,
                style: context.environment.indeterminateStyle,
                filledColor: palette.foregroundSecondary,
                emptyColor: palette.foregroundTertiary,
                accentColor: palette.accent
            )
        }
        return TrackRenderer.render(
            fraction: fraction,
            width: width,
            style: style,
            filledColor: palette.foregroundSecondary,
            emptyColor: palette.foregroundTertiary,
            accentColor: palette.accent
        )
    }
}
