//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// ███████████████                 (default .block: █ fill, solid-bg empty)
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
    /// Creates an indeterminate progress view with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter titleKey: The key for text describing the task in progress.
    public init(_ titleKey: LocalizedStringKey) {
        self.init(titleKey.localized)
    }

    /// Creates an indeterminate progress view with a string title, as written.
    ///
    /// - Parameter title: A string that describes the task in progress.
    @_disfavoredOverload
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
    /// Creates a progress view with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for text describing the task in progress.
    ///   - value: The completed amount (nil for indeterminate).
    ///   - total: The total amount (default: 1.0).
    public init<V: BinaryFloatingPoint>(
        _ titleKey: LocalizedStringKey,
        value: V?,
        total: V = 1.0
    ) {
        self.init(titleKey.localized, value: value, total: total)
    }

    /// Creates a progress view with a string title, displayed as written.
    ///
    /// - Parameters:
    ///   - title: A string that describes the task in progress.
    ///   - value: The completed amount (nil for indeterminate).
    ///   - total: The total amount (default: 1.0).
    @_disfavoredOverload
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

/// Named indices, so no bare integer decides which slot holds what. Outside the
/// generic type because a generic may not carry static stored properties.
private enum ProgressStateIndex {
    static let cycle = 0
}

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
        let width = proposal.width ?? context.availableWidth
        // 2 lines only when the label line is actually visible (a blank label
        // like `ProgressView("")` collapses to just the bar). Rendering the
        // label here is cheap and — unlike the bar — starts no animation.
        let height =
            visibleLabelLine(width: width, palette: context.environment.palette, context: context) != nil
            ? 2 : 1
        return ViewSize(
            width: width,
            height: height,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let width = context.availableWidth
        var lines: [String] = []

        // Label line (optional): label left, currentValueLabel right. A blank
        // label (e.g. `ProgressView("")`) collapses so the bar isn't pushed
        // down by an empty line.
        if let labelLine = visibleLabelLine(width: width, palette: palette, context: context) {
            lines.append(labelLine)
        }

        // Where the animation is now: the frame clock, the instant the loop's content
        // clock was shown before this render (§74), so the frame drawn here is the one
        // a replay splices and a declined run needs no clock of its own. A determinate
        // bar ignores it entirely: its value comes from the caller's data, and it does
        // not animate.
        let elapsed = Double(context.environment.frameNowNanos) / 1_000_000_000

        // An indeterminate bar leaves its whole cycle behind, so the loop can
        // splice the next frame over these cells without re-rendering anything.
        // It used to ask to be re-rendered thirty times a second instead —
        // which is a full measure/layout/render/diff of the WHOLE screen, to
        // move one bar. See ``AnimatedCellRun``.
        let barRow = lines.count
        // A translucent bar cannot be pre-rendered: a run carries frames and no
        // alpha, and a sweep moves, so no static region describes every frame. It
        // falls back to what these bars did before runs existed — a re-render at the
        // cycle's own sampling rate, where each frame states its own exact claim.
        // Same shape as `Spinner`'s fallback for a mixed-width cycle, and for the
        // same reason: the run cannot express it, so the run is not used. §36.7.
        // Each render draws the frame the run would show at this instant, and asks for
        // one render when the next frame showing a different state begins on the frame
        // clock; that render asks for the one after. It used to ask for a render at the
        // end of every frame, most of which, on a narrow bar, draw the state already on
        // screen, and to draw the motion at a time scaled by its rate rather than the
        // run's frame.
        let canPreRender =
            IndeterminateRenderer.isOpaqueThroughout(
                style: context.environment.indeterminateStyle,
                fillColor: palette.foregroundSecondary, backgroundColor: palette.foregroundTertiary,
                accentColor: palette.accent, palette: palette)
        guard fractionCompleted == nil, !context.isMeasuring, width > 0, canPreRender else {
            let bar: ClaimingRow
            if fractionCompleted == nil, !context.isMeasuring, width > 0 {
                let frame = indeterminateFrame(width: width, palette: palette, context: context, elapsed: elapsed)
                if let next = frame.nextChangeNanos {
                    context.requestWake(token: "progress-\(context.identity.path)", atNanos: next)
                }
                bar = frame.row
            } else {
                bar = renderBarLine(width: width, palette: palette, context: context, elapsed: elapsed)
            }
            // The scheduler drives this path, not the cursor timer, which nothing keeps
            // running on a page holding only this (§66). The frame comes from the same
            // clock as the run path's.
            lines.append(bar.text)
            var buffer = FrameBuffer(lines: lines)
            // Down to the row the bar landed on. Nothing is composited over this
            // buffer here, so the claim goes on plainly — `ListRowStyleModifiers`'
            // two-branch punch rule does not apply.
            buffer.opacityRegions += bar.claims.map { $0.shifted(byX: 0, y: barRow) }
            return buffer
        }

        let cycle = indeterminateCycle(width: width, palette: palette, context: context)
        lines.append(cycle.frames[
            cycle.run.index(atElapsed: elapsed) % max(1, cycle.frames.count)])
        var buffer = FrameBuffer(lines: lines)
        buffer.animatedCells = [cycle.run.movedTo(row: barRow)]
        return buffer
    }

    // MARK: - The indeterminate cycle

    /// One built cycle, kept until something it depends on changes.
    ///
    /// Worth keeping because it is the one real cost of this approach: a
    /// 36-cell `.gradient` cycle is 72 frames, each a row re-colouring every cell,
    /// and rebuilding that on every render would move work onto the render path in
    /// exchange for taking it off the animation path. Every frame, and how long it is shown,
    /// is a pure function of these inputs, so anything else may change freely.
    private struct CachedCycle {
        let width: Int
        let style: IndeterminateStyle
        let filled: Color
        let empty: Color
        let accent: Color
        /// The style's stops, resolved against the palette, with the `.gradient`
        /// motion's default filled in (`IndeterminateConfiguration.resolvingColours(with:)`).
        /// Not the style's own: that names a role where a caller wrote one, and
        /// nothing at all for the default, so it compares equal after the roles
        /// change. Nor do the three colours above cover it, since a stop can be any
        /// role.
        let gradient: Gradient?
        /// The bar's speed. A pass at another speed has other frames and another
        /// frame duration, so a cycle built at one must not be served at another.
        let speed: IndicatorAnimationSpeed
        /// Whether the frames are pictures. A cycle of cells built for a
        /// glyph terminal must not be served where pictures are drawn, nor
        /// the other way round, so it is part of what the cache is keyed on.
        let pictures: Bool
        let frames: [String]
        let run: AnimatedCellRun
        /// How many picture tokens the build asked the image store for: one for each
        /// distinct shift of the pass when it was built with a graphics context, and
        /// 0 when it was not. The pictures it put in the store can be fewer, where
        /// shifts draw the same picture, and are the first tokens of these.
        /// A rebuild gives back the ones its replacement does not name.
        let pictureCount: Int

        func matches(
            width: Int, style: IndeterminateStyle, filled: Color, empty: Color, accent: Color,
            gradient: Gradient?, speed: IndicatorAnimationSpeed, pictures: Bool
        ) -> Bool {
            self.width == width && self.style == style && self.filled == filled
                && self.empty == empty && self.accent == accent && self.gradient == gradient
                && self.speed == speed && self.pictures == pictures
        }
    }

    private func indeterminateCycle(
        width: Int, palette: any Palette, context: RenderContext
    ) -> CachedCycle {
        let style = context.environment.indeterminateStyle
        let filled = palette.foregroundSecondary
        let empty = palette.foregroundTertiary
        let accent = palette.accent
        let speed = context.environment.indicatorAnimationSpeeds.speed(for: .indeterminateProgress)
        let layout = IndeterminateRenderer.layout(of: style, speed: speed)
        let configuration = style.configuration.resolvingColours(with: palette)
        let gradient = configuration.gradient
        // The `.gradient` motion over a solid fill is a colour field, and a
        // colour field can be pictures where the terminal draws them — see
        // ``IndeterminateRaster``. A pass of the glyph cycle's frame count, so a
        // bar steps at one rate whichever path draws it, showing one picture for
        // each whole-pixel shift it reaches: min(P, F), P the picture's width in
        // pixels. Counted before the context is asked for, because asking registers
        // that many tokens, each released when the bar goes.
        let frameCount = layout.frameCount
        let pictureToken = "track-\(context.identity.path)"
        let isPictureBar = configuration.motion == .gradient && configuration.fill == "█"
        let distinctPictures =
            isPictureBar
            ? min(
                frameCount,
                IndeterminateRenderer.states(
                    of: configuration, width: width, cellPixels: context.environment.imageCellPixels)
                    ?? frameCount)
            : 0
        let graphics = isPictureBar ? context.gradientGraphics(token: pictureToken, frames: distinctPictures) : nil
        let pictureCount = graphics == nil ? 0 : distinctPictures

        func build() -> CachedCycle {
            if let graphics,
                let rows = pictureFrames(
                    width: width, frameCount: frameCount, configuration: configuration, graphics: graphics,
                    palette: palette)
            {
                return CachedCycle(
                    width: width, style: style, filled: filled, empty: empty, accent: accent,
                    gradient: gradient, speed: speed, pictures: true, frames: rows,
                    run: AnimatedCellRun(
                        offsetX: 0, offsetY: 0, width: width, frames: rows,
                        frameTicks: layout.frameTicks, clock: .content),
                    pictureCount: pictureCount)
            }
            let built = IndeterminateRenderer.cycle(
                width: width, style: style, fillColor: filled,
                backgroundColor: empty, accentColor: accent, palette: palette, speed: speed)
            return CachedCycle(
                width: width, style: style, filled: filled, empty: empty, accent: accent,
                gradient: gradient, speed: speed, pictures: false, frames: built.frames,
                run: AnimatedCellRun(
                    offsetX: 0, offsetY: 0, width: width, frames: built.frames,
                    frameTicks: built.frameTicks, clock: .content),
                pictureCount: pictureCount)
        }

        guard let stateStorage = context.stateStorage else { return build() }
        // Without this the entry is swept at the end of every render pass —
        // `storage(for:default:)` does not mark an identity active — and the
        // cache that exists to build the cycle once would build it every time.
        stateStorage.markActive(context.identity)
        let box: StateBox<CachedCycle?> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: ProgressStateIndex.cycle),
            default: nil)
        if let cached = box.value,
            cached.matches(
                width: width, style: style, filled: filled, empty: empty, accent: accent,
                gradient: gradient, speed: speed, pictures: graphics != nil)
        {
            return cached
        }
        let built = build()
        // The bar's disappear handler is replaced at every render, and releases only
        // the frames of the cycle that render asked for. So the frames the old cycle
        // put in the store and the new one does not name are given back here, or
        // nothing ever gives them back. After the build, not before, so a new frame
        // that shares an old picture keeps it. A frame stays named only if it has
        // the same index and the same spelling, which depends on the count.
        if let stale = box.value, stale.pictureCount > 0,
            let store = context.environment.terminalImageStore
        {
            for index in 0..<stale.pictureCount {
                let old = GradientGraphicsContext.token(pictureToken, forFrame: index, of: stale.pictureCount)
                if index >= built.pictureCount
                    || old != GradientGraphicsContext.token(pictureToken, forFrame: index, of: built.pictureCount)
                {
                    store.release(token: old)
                }
            }
        }
        box.value = built
        return built
    }

    /// The rows of a picture bar's pass of `frameCount` frames: one picture for each
    /// distinct whole-pixel shift the pass reaches (`IndeterminateRaster.shifts(count:pixels:)`),
    /// or fewer where shifts draw the same pixels, sent once and named by every frame
    /// showing it, and the pass cut to one repeat where it repeats
    /// (`IndeterminateRenderer.repeatLength(of:)`) — or `nil` when the box has no
    /// pixels, or the store names no row, and the bar is drawn in glyphs.
    private func pictureFrames(
        width: Int, frameCount: Int, configuration: IndeterminateConfiguration,
        graphics: GradientGraphicsContext, palette: any Palette
    ) -> [String]? {
        guard
            let pixels = IndeterminateRenderer.states(
                of: configuration, width: width, cellPixels: graphics.cellPixels)
        else { return nil }
        let shifts = IndeterminateRaster.shifts(count: frameCount, pixels: pixels)
        // As many tokens as the context holds, which it releases, whether or not each
        // ends up naming a picture.
        guard shifts.distinct.count == graphics.frames,
            let drawn = IndeterminateRaster.frames(
                width: width, shifts: shifts.distinct, configuration: configuration,
                cellPixels: graphics.cellPixels, palette: palette)
        else { return nil }
        // Compared by their pixels before any is placed: a ramp that repeats across the
        // track draws one picture at two shifts, and each is sent and held once, under
        // the first tokens.
        var pictures: [GradientRaster.Picture] = []
        var indexOfPixels: [[UInt8]: Int] = [:]
        let pictureOfShift = drawn.map { picture in
            if let index = indexOfPixels[picture.bytes] { return index }
            indexOfPixels[picture.bytes] = pictures.count
            pictures.append(picture)
            return pictures.count - 1
        }
        let named = shifts.frames.map { pictureOfShift[$0] }
        let rows = pictures.enumerated().compactMap { index, picture in
            graphics.store.placeholderRows(
                token: graphics.token(forFrame: index),
                signature: IndeterminateFrameSignature(
                    configuration: configuration, width: picture.width,
                    height: picture.height, frame: index, count: pictures.count),
                columns: width, rows: 1,
                pixels: { (picture.bytes, picture.format, picture.width, picture.height) }
            )?.first
        }
        guard rows.count == pictures.count else { return nil }
        return named.prefix(IndeterminateRenderer.repeatLength(of: named)).map { rows[$0] }
    }

    // MARK: - Label Line Rendering

    /// Renders the label line with label left-aligned and currentValueLabel right-aligned.
    private func renderLabelLine(width: Int, palette: any Palette, context: RenderContext) -> String {
        let labelBuffer: FrameBuffer
        // `.labelsHidden()` takes the CAPTION, not the readout: the
        // `currentValueLabel` states the value the bar is showing, which is the
        // control's content rather than a name for it. With both gone the line
        // is blank and `visibleLabelLine` drops it, so the bar moves up.
        // Each label under its OWN child identity: they are caller-supplied
        // @ViewBuilder content, and rendered at the core's identity a
        // composite label's first @State landed on the core's cycle-cache
        // slot — and the two labels landed on each other. The collision class
        // 778699f5 closed; these two sites were missed instances.
        if let labelView = label, !(labelView is EmptyView),
            !context.environment.controlLabelsAreHidden {
            labelBuffer = TUIkit.renderToBuffer(
                labelView,
                context: context.withChildIdentity(erasedType: type(of: labelView), index: 0))
        } else {
            labelBuffer = FrameBuffer()
        }

        let valueBuffer: FrameBuffer
        if let valueView = currentValueLabel, !(valueView is EmptyView) {
            valueBuffer = TUIkit.renderToBuffer(
                valueView,
                context: context.withChildIdentity(erasedType: type(of: valueView), index: 1))
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

    /// The label line if it has visible content, else `nil` — so a blank label
    /// (`ProgressView("")`) doesn't push the bar down by an empty row. Used by
    /// both `sizeThatFits` and `renderToBuffer` so their heights agree.
    private func visibleLabelLine(width: Int, palette: any Palette, context: RenderContext) -> String? {
        guard hasLabelLine else { return nil }
        let line = renderLabelLine(width: width, palette: palette, context: context)
        return line.stripped.allSatisfy(\.isWhitespace) ? nil : line
    }

    // MARK: - Bar Line Rendering

    /// The indeterminate bar's frame at `elapsed` on the frame clock, as its run would
    /// show it, and when it next changes. See
    /// `IndeterminateRenderer.frame(atElapsed:width:style:fillColor:backgroundColor:accentColor:palette:speed:)`.
    private func indeterminateFrame(
        width: Int, palette: any Palette, context: RenderContext, elapsed: Double
    ) -> (row: ClaimingRow, nextChangeNanos: Int64?) {
        IndeterminateRenderer.frame(
            atElapsed: elapsed, width: width, style: context.environment.indeterminateStyle,
            fillColor: palette.foregroundSecondary, backgroundColor: palette.foregroundTertiary,
            accentColor: palette.accent, palette: palette,
            speed: context.environment.indicatorAnimationSpeeds.speed(for: .indeterminateProgress))
    }

    /// Renders the progress bar line — a determinate track, or an animated
    /// indeterminate sweep when there is no measurable progress.
    private func renderBarLine(
        width: Int, palette: any Palette, context: RenderContext, elapsed: Double
    ) -> ClaimingRow {
        guard let fraction = fractionCompleted else {
            // The frame's own claims, exact for the one frame this is. Reached by a
            // measure pass, which draws nothing, and by a track with no cells; the
            // fallback above draws the same frame.
            return indeterminateFrame(width: width, palette: palette, context: context, elapsed: elapsed).row
        }
        return TrackRenderer.render(
            fraction: fraction,
            width: width,
            style: style,
            fillColor: palette.foregroundSecondary,
            backgroundColor: palette.foregroundTertiary,
            accentColor: palette.accent,
            fillScaling: context.environment.trackFillGradientScaling,
            backgroundScaling: context.environment.trackBackgroundGradientScaling,
            palette: palette,
            graphics: context.gradientGraphics(token: "track-\(context.identity.path)")
        )
    }
}
