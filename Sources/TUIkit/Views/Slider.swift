//  TUIKit - Terminal UI Kit for Swift
//  Slider.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Slider

/// A control for selecting a value from a bounded linear range of values.
///
/// A slider displays a visual track that the user can adjust using keyboard
/// controls. The track shows the current position within the range.
///
/// ## Rendering
///
/// ```
/// Unfocused:    ◀ ████████████░░░░░░░░ ▶  50%
/// Focused:    ❙ ◀ ████████████░░░░░░░░ ▶ ❙ 50%
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | `→` or `+` | Increment by step |
/// | `←` or `-` | Decrement by step |
/// | `Home` | Jump to minimum |
/// | `End` | Jump to maximum |
///
/// ## Basic Example
///
/// ```swift
/// @State var volume: Double = 0.5
///
/// Slider(value: $volume)
/// ```
///
/// ## With Range and Step
///
/// ```swift
/// @State var brightness: Double = 50
///
/// Slider(value: $brightness, in: 0...100, step: 5)
/// ```
///
/// ## With a Description
///
/// The `label` (or string title) describes the slider's purpose. As in
/// SwiftUI, it is **not drawn on the track** — only the value readout is. For
/// a visible caption, place a `Text` (or a `Section` header) next to the
/// slider:
///
/// ```swift
/// VStack(alignment: .leading) {
///     Text("Volume")
///     Slider(value: $volume, in: 0...1)
/// }
/// ```
///
/// ## With Editing Callback
///
/// ```swift
/// Slider(value: $volume, in: 0...1) { isEditing in
///     print("Editing: \(isEditing)")
/// }
/// ```
public struct Slider<Label: View, ValueLabel: View>: View {
    /// The binding to the current value.
    let value: Binding<Double>

    /// The range of valid values.
    let bounds: ClosedRange<Double>

    /// The step size for increment/decrement.
    let step: Double

    /// The label view describing the slider's purpose. As in SwiftUI this is a
    /// description only — it is not drawn on the track.
    let label: Label?

    /// The value label showing the current value.
    let valueLabel: ValueLabel?

    /// The visual style of the track.
    var trackStyle: TrackStyle

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the slider is disabled.
    var isDisabled: Bool

    /// Callback when editing begins or ends.
    let onEditingChanged: ((Bool) -> Void)?

    /// Default track width when no explicit frame is set.
    private static var defaultTrackWidth: Int { 20 }

    public var body: some View {
        _SliderCore(
            value: value,
            bounds: bounds,
            step: step,
            label: label,
            valueLabel: valueLabel,
            trackStyle: trackStyle,
            focusID: focusID,
            isDisabled: isDisabled,
            onEditingChanged: onEditingChanged
        )
    }
}

// MARK: - Slider Initializers (No Label)

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    /// Creates a slider to select a value from a given range.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = Double(step)
        self.label = nil
        self.valueLabel = nil
        self.trackStyle = .block
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }
}

// MARK: - Slider Initializers (String Title)

extension Slider where Label == Text, ValueLabel == EmptyView {
    /// Creates a slider with a title string.
    ///
    /// The title describes the slider but, as in SwiftUI, is not drawn on the
    /// track. Pair the slider with a `Text` for a visible caption.
    ///
    /// - Parameters:
    ///   - title: A description of the slider's purpose (not rendered).
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<S: StringProtocol, V: BinaryFloatingPoint>(
        _ title: S,
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = Double(step)
        self.label = Text(String(title))
        self.valueLabel = nil
        self.trackStyle = .block
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }
}

// MARK: - Slider Initializers (ViewBuilder Label)

extension Slider where ValueLabel == EmptyView {
    /// Creates a slider with a custom label.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - label: A view describing the purpose of the slider.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = Double(step)
        self.label = label()
        self.valueLabel = nil
        self.trackStyle = .block
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }
}

// MARK: - Slider Modifiers

extension Slider {
    /// Sets the visual style of the slider track.
    ///
    /// ```swift
    /// Slider(value: $volume)
    ///     .trackStyle(.dot)
    /// ```
    ///
    /// - Parameter style: The track style.
    /// - Returns: A slider with the specified track style.
    public func trackStyle(_ style: TrackStyle) -> Slider {
        var copy = self
        copy.trackStyle = style
        return copy
    }

    /// Creates a disabled version of this slider.
    ///
    /// - Parameter disabled: Whether the slider is disabled.
    /// - Returns: A new slider with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Slider {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this slider.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A slider with the specified focus identifier.
    public func focusID(_ id: String) -> Slider {
        var copy = self
        copy.focusID = id
        return copy
    }
}

extension View {
    /// Styles the *value read-out* text of every slider in this view's subtree
    /// (a `.control(.slider)`-scoped style entry). The track and arrows are
    /// unaffected — their accent is the tint axis.
    ///
    /// ```swift
    /// Mixer().sliderTextStyle { $0.bold = true; $0.foreground = .palette.accent }
    /// ```
    public func sliderTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.slider), build)
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_SliderCore``. Lifted
/// out of the generic struct because Swift does not allow
/// static stored properties in generic types.
private enum SliderStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
    static let leftArrowRepeat = 3
    static let rightArrowRepeat = 4
}

/// Internal view that handles the actual rendering of Slider.
private struct _SliderCore<Label: View, ValueLabel: View>: View, Renderable, Layoutable {
    let value: Binding<Double>
    let bounds: ClosedRange<Double>
    let step: Double
    let label: Label?
    let valueLabel: ValueLabel?
    let trackStyle: TrackStyle
    let focusID: String?
    let isDisabled: Bool
    let onEditingChanged: ((Bool) -> Void)?

    /// Minimum track width.
    private let minTrackWidth = 10

    /// Default track width when no explicit frame is set.
    private let defaultTrackWidth = 20

    /// Width of the value field, in columns: the width of the widest value the
    /// slider can show, `"100%"`. Shorter values are padded to this width (see
    /// ``valueLabelText``) so the field — and therefore the track and arrows —
    /// never change size as the value changes.
    private var valueFieldWidth: Int { 4 }

    /// The `"NN%"` value drawn at the trailing edge, padded to a FIXED field
    /// (``valueFieldWidth``) so the slider keeps a constant length and the right
    /// arrow doesn't shift when the value crosses 10%/100%. Shorter values are
    /// left-aligned with trailing spaces (`"50% "`), matching a fixed numeric
    /// field; this also fills the trailing cell the old hard-coded chrome left
    /// blank. The fraction is clamped exactly as it is for display, so the
    /// width is stable across the value-clamping that happens mid-render.
    private var valueLabelText: String {
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = range > 0
            ? min(1.0, max(0.0, (value.wrappedValue - bounds.lowerBound) / range))
            : 0
        let text = "\(Int((fraction * 100).rounded()))%"
        guard text.count < valueFieldWidth else { return text }
        return text + String(repeating: " ", count: valueFieldWidth - text.count)
    }

    /// Columns consumed by everything other than the track:
    /// `"◀ " + track + " ▶ " + value field`, i.e. the two arrows, the three
    /// spaces around them, and the fixed-width value field.
    ///
    /// Constant (5 + ``valueFieldWidth`` = 9), because the value field is padded
    /// to a fixed width — so the track and arrows hold a constant position as
    /// the value changes (the slider never changes length). Used by BOTH
    /// `sizeThatFits` and `renderToBuffer` so the two agree, and because the
    /// field is padded the track + chrome fills the available width exactly
    /// (the value padding occupies the cell the old hard-coded 9 left blank for
    /// values narrower than "100%").
    private func chromeWidth(showsValue: Bool) -> Int {
        // "◀" + " " (before track) + " " + "▶" + " " (after track) = 5 columns,
        // then the value field. With the value hidden the trailing space + field
        // drop, leaving "◀ track ▶" — 4 columns of chrome.
        guard showsValue else { return 4 }
        return 5 + valueLabelText.count
    }

    var body: Never {
        fatalError("_SliderCore renders via Renderable")
    }

    /// Returns the size this slider needs.
    ///
    /// Slider is width-flexible: it has a minimum width but expands
    /// to fill available horizontal space in HStack.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let chrome = chromeWidth(showsValue: context.environment.sliderShowsValue)
        let proposedWidth = proposal.width ?? (defaultTrackWidth + chrome)
        let trackWidth = max(minTrackWidth, proposedWidth - chrome)
        return ViewSize(
            width: trackWidth + chrome,
            height: 1,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    private typealias StateIndex = SliderStateIndex

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.environment.stateStorage!
        let palette = context.environment.palette

        // Slider expands to fill available width (with minimum). Subtracting
        // the chrome here means track + chrome fills exactly `availableWidth`,
        // matching what `sizeThatFits` reports.
        let showsValue = context.environment.sliderShowsValue
        let trackWidth = max(minTrackWidth, context.availableWidth - chromeWidth(showsValue: showsValue))

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "slider",
            propertyIndex: StateIndex.focusID
        )

        // Get or create persistent handler from state storage
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<SliderHandler<Double>> = stateStorage.storage(
            for: handlerKey,
            default: SliderHandler(
                focusID: persistedFocusID,
                value: value,
                bounds: bounds,
                step: step,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value

        // Keep handler in sync with current values
        handler.value = value
        handler.canBeFocused = !isDisabled
        handler.onEditingChanged = onEditingChanged
        handler.clampValue()

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // Calculate fraction, clamped to [0, 1] to handle out-of-bounds values
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = range > 0 ? min(1.0, max(0.0, (value.wrappedValue - bounds.lowerBound) / range)) : 0

        // Build the slider content
        let content = buildContent(
            fraction: fraction,
            isFocused: isFocused,
            isHovered: isHovered,
            palette: palette,
            indicator: SelectionIndicator.resolve(isFocused: isFocused, context: context),
            trackWidth: trackWidth,
            valueStyle: context.environment.styleCascade.resolve(
                for: [.all, .text, .control(.slider)]),
            isDisabled: isDisabled,
            showsValue: showsValue
        )

        var buffer = FrameBuffer(text: content)

        attachMouseHandlers(
            to: &buffer,
            context: context,
            hoverBox: hoverBox,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            trackWidth: trackWidth
        )

        return buffer
    }

    // MARK: - Mouse handler wiring

    /// Registers the slider's single buffer-wide mouse handler
    /// (which routes wheel + arrow + track behaviour) and emits
    /// its hit-test region. The handler is composed from the
    /// per-axis helpers below.
    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        hoverBox: StateBox<Bool>,
        persistedFocusID: String,
        stateStorage: StateStorage,
        trackWidth: Int
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        mouseDispatcher.requestFeature(.motion)

        let focusManager = context.environment.focusManager
        let trackLeft = 2  // "◀ "
        let trackRight = trackLeft + trackWidth  // exclusive

        let leftArrowTimer = autoRepeatTimer(
            stateStorage: stateStorage,
            context: context,
            propertyIndex: StateIndex.leftArrowRepeat
        )
        let rightArrowTimer = autoRepeatTimer(
            stateStorage: stateStorage,
            context: context,
            propertyIndex: StateIndex.rightArrowRepeat
        )

        let handlerID = mouseDispatcher.register(
            mouseHandler(
                hoverBox: hoverBox,
                focusManager: focusManager,
                focusID: persistedFocusID,
                leftArrowTimer: leftArrowTimer,
                rightArrowTimer: rightArrowTimer,
                trackLeft: trackLeft,
                trackRight: trackRight,
                trackWidth: trackWidth
            )
        )
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: handlerID,
                focusID: persistedFocusID
            )
        )
    }

    /// The single mouse handler for the slider's hit-test
    /// region. Routes hover, wheel, arrow-click + auto-repeat,
    /// and track drag-set behaviour. Returns a closure rather
    /// than a method so the captures (which include the
    /// `value` and `bounds` from the surrounding view) are
    /// fixed at the moment of registration.
    private func mouseHandler(
        hoverBox: StateBox<Bool>,
        focusManager: FocusManager,
        focusID: String,
        leftArrowTimer: AutoRepeatTimer,
        rightArrowTimer: AutoRepeatTimer,
        trackLeft: Int,
        trackRight: Int,
        trackWidth: Int
    ) -> @MainActor (MouseEvent) -> Bool {
        let value = self.value
        let bounds = self.bounds
        let step = self.step

        let decrementOnce: @MainActor () -> Void = {
            value.wrappedValue = min(
                bounds.upperBound,
                max(bounds.lowerBound, value.wrappedValue - step))
        }
        let incrementOnce: @MainActor () -> Void = {
            value.wrappedValue = min(
                bounds.upperBound,
                max(bounds.lowerBound, value.wrappedValue + step))
        }
        let stopArrowTimers: @MainActor () -> Void = {
            leftArrowTimer.stop()
            rightArrowTimer.stop()
        }

        return { event in
            switch event.phase {
            case .entered:
                hoverBox.value = true
                return true
            case .exited:
                hoverBox.value = false
                return true
            default:
                break
            }
            switch event.button {
            case .scrollUp:
                // Wheel up scrolls toward smaller / earlier values; wheel down
                // advances. Matches Stepper, Menu, List and ScrollView — the
                // slider previously had this inverted, so a horizontal slider
                // adjusted the opposite way from every other wheel control.
                decrementOnce()
                focusManager.focus(id: focusID)
                return true
            case .scrollDown:
                incrementOnce()
                focusManager.focus(id: focusID)
                return true
            case .left:
                return Self.handleLeftButton(
                    event: event,
                    value: value,
                    bounds: bounds,
                    step: step,
                    trackLeft: trackLeft,
                    trackRight: trackRight,
                    trackWidth: trackWidth,
                    leftArrowTimer: leftArrowTimer,
                    rightArrowTimer: rightArrowTimer,
                    decrementOnce: decrementOnce,
                    incrementOnce: incrementOnce,
                    stopArrowTimers: stopArrowTimers,
                    focusManager: focusManager,
                    focusID: focusID
                )
            default:
                return false
            }
        }
    }

    /// Dispatches a `.left`-button mouse event among the three
    /// regions Slider supports: the left arrow, the right arrow,
    /// and the track in between. Static so it doesn't capture
    /// `self`, avoiding a reference cycle through the parent
    /// closure.
    private static func handleLeftButton( // swiftlint:disable:this function_parameter_count
        event: MouseEvent,
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        step: Double,
        trackLeft: Int,
        trackRight: Int,
        trackWidth: Int,
        leftArrowTimer: AutoRepeatTimer,
        rightArrowTimer: AutoRepeatTimer,
        decrementOnce: @escaping @MainActor () -> Void,
        incrementOnce: @escaping @MainActor () -> Void,
        stopArrowTimers: @MainActor () -> Void,
        focusManager: FocusManager,
        focusID: String
    ) -> Bool {
        switch event.phase {
        case .pressed, .dragged:
            if event.x < trackLeft {
                // Left arrow.
                if event.phase == .pressed {
                    stopArrowTimers()
                    leftArrowTimer.start(action: decrementOnce)
                } else {
                    // .dragged onto the arrow from elsewhere —
                    // stop any track dragging, don't restart
                    // the auto-repeat.
                    stopArrowTimers()
                }
            } else if event.x >= trackRight {
                // Right arrow.
                if event.phase == .pressed {
                    stopArrowTimers()
                    rightArrowTimer.start(action: incrementOnce)
                } else {
                    stopArrowTimers()
                }
            } else {
                stopArrowTimers()
                applyTrackValue(
                    eventX: event.x,
                    value: value,
                    bounds: bounds,
                    step: step,
                    trackLeft: trackLeft,
                    trackWidth: trackWidth
                )
            }
            focusManager.focus(id: focusID)
            return true
        case .released:
            stopArrowTimers()
            return true
        default:
            return false
        }
    }

    /// Maps a track-area cursor x to a snapped slider value and
    /// applies it. Snaps to the nearest multiple of `step` so
    /// keyboard and mouse adjustments stay in lockstep —
    /// dragging across the track lands on the same values you'd
    /// reach by tapping →.
    private static func applyTrackValue(
        eventX: Int,
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        step: Double,
        trackLeft: Int,
        trackWidth: Int
    ) {
        let pos = max(0, min(trackWidth - 1, eventX - trackLeft))
        let range = bounds.upperBound - bounds.lowerBound
        let raw = bounds.lowerBound + (trackWidth > 1
            ? Double(pos) / Double(trackWidth - 1)
            : 0) * range
        let snapped: Double
        if step > 0 {
            let stepsFromLow = ((raw - bounds.lowerBound) / step).rounded()
            snapped = bounds.lowerBound + stepsFromLow * step
        } else {
            snapped = raw
        }
        value.wrappedValue = min(bounds.upperBound, max(bounds.lowerBound, snapped))
    }

    /// Fetches (or creates) the auto-repeat timer at the given
    /// `propertyIndex` on the current view identity.
    private func autoRepeatTimer(
        stateStorage: StateStorage,
        context: RenderContext,
        propertyIndex: Int
    ) -> AutoRepeatTimer {
        let key = StateStorage.StateKey(
            identity: context.identity, propertyIndex: propertyIndex)
        let box: StateBox<AutoRepeatTimer> = stateStorage.storage(
            for: key, default: AutoRepeatTimer())
        return box.value
    }

    /// Builds the rendered slider content.
    private func buildContent(
        fraction: Double,
        isFocused: Bool,
        isHovered: Bool,
        palette: any Palette,
        indicator: SelectionIndicator.Resolution,
        trackWidth: Int,
        valueStyle: StyleAttributes,
        isDisabled: Bool,
        showsValue: Bool
    ) -> String {
        // Arrow colors:
        //   - Focused: pulsing accent
        //   - Hovered (not focused): static accent at the
        //     hoverBackground tint so the affordance is visible
        //     without competing with the focus pulse
        //   - Otherwise: dimmed foregroundTertiary
        let arrowColor: Color
        if isDisabled {
            arrowColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        } else if isFocused {
            // Pulse between 35% and 100% accent
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
            arrowColor = indicator.color(dim: dimAccent, bright: palette.accent)
        } else if isHovered {
            arrowColor = palette.accent.opacity(ViewConstants.hoverBackground)
        } else {
            // Dimmed arrows when unfocused
            arrowColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        }

        // Build track
        let track = TrackRenderer.render(
            fraction: fraction,
            width: trackWidth,
            style: trackStyle,
            filledColor: isDisabled ? palette.foregroundTertiary : palette.foregroundSecondary,
            emptyColor: palette.foregroundTertiary,
            accentColor: palette.accent
        )

        // Build arrows
        let leftArrow = ANSIRenderer.colorize(TerminalSymbols.leftArrow, foreground: arrowColor)
        let rightArrow = ANSIRenderer.colorize(TerminalSymbols.rightArrow, foreground: arrowColor)

        // Build value label (percentage) — the same source of truth that
        // `chromeWidth` measures, so the label always fits the space reserved.
        // Its colour/weight inherit the slider's scoped style cascade
        // (`.sliderTextStyle { … }`) as soft overrides.
        let valueText = valueLabelText
        let valueLabelColor =
            isDisabled
            ? palette.foregroundTertiary
            : (valueStyle.foreground?.resolve(with: palette) ?? palette.foregroundSecondary)
        let valueLabel = ANSIRenderer.colorize(
            valueText,
            foreground: valueLabelColor,
            bold: !isDisabled && (valueStyle.bold ?? false),
            underline: !isDisabled && (valueStyle.underline ?? false))

        // Pulsing arrows indicate focus - no extra markers needed. The value
        // read-out is omitted when `.sliderShowsValue(false)` (some surrounding
        // control shows the value instead).
        guard showsValue else { return "\(leftArrow) \(track) \(rightArrow)" }
        return "\(leftArrow) \(track) \(rightArrow) \(valueLabel)"
    }
}
