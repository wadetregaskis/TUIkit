//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// The default track is a rail with a round knob at the value — distinct at a
/// glance from `ProgressView`'s solid block bar and `Gauge`'s shaded meter:
///
/// ```
/// Unfocused:    ◀ ━━━━━━━━●──────── ▶  50%
/// Focused:    ❙ ◀ ━━━━━━━━●──────── ▶ ❙ 50%
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
/// The `label` (or string title) describes the slider's purpose. TUIkit does
/// **not** draw it on the track — only the value readout is drawn. For a
/// visible caption, place a `Text` (or a `Section` header) next to the slider:
///
/// ```swift
/// VStack(alignment: .leading) {
///     Text("Volume")
///     Slider(value: $volume, in: 0...1)
/// }
/// ```
///
/// > Known deviation from macOS SwiftUI. Measured 2026-07-25 by hosting real
/// > `Slider`s in an `NSHostingView` and capturing the drawn AppKit controls:
/// > macOS SwiftUI draws a supplied label to the LEFT of the track on the same
/// > line, shortening the track to fit; with no label the track spans the full
/// > width. (Apple's own docs hedge this — "Not all slider styles show the
/// > label" — because iOS hides it and uses it only for accessibility. On a
/// > desktop-shaped framework the macOS behaviour is the relevant reference.)
/// > Matching it is tracked; it changes the width of every existing slider, so
/// > it is deliberately not a drive-by change.
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
        // The label renders inline to the left of the track (SwiftUI parity):
        // "Volume ◀ ━━━●─── ▶ 50%". An empty/absent label collapses, so an
        // unlabelled slider still starts at column 0 with a full-length track.
        //
        // Composed as an HStack sibling rather than drawn inside `_SliderCore`
        // on purpose: the core's geometry — `trackLeft`, the arrow click zones,
        // the track-drag mapping — is all measured from its OWN buffer, and the
        // stack shifts its hit regions for us. Prepending the label inside the
        // core would leave `trackLeft` pointing into the label, so clicking the
        // label would auto-repeat a decrement. `controlKind` lets the label
        // resolve `.sliderTextStyle` like the value read-out does.
        HStack(spacing: 0) {
            _CollapsingLabel(label: label, controlDisabled: isDisabled)
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
        .environment(\.controlKind, .slider)
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
        self.trackStyle = .knob
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
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key describing the slider's purpose (not rendered).
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        _ titleKey: LocalizedStringKey,
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            titleKey.localized, value: value, in: bounds, step: step,
            onEditingChanged: onEditingChanged)
    }

    /// Creates a slider with a title displayed as written.
    ///
    /// - Parameters:
    ///   - title: A description of the slider's purpose (not rendered).
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    @_disfavoredOverload
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
        self.trackStyle = .knob
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
        self.trackStyle = .knob
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
        let text = valueDisplayText
        guard text.count < valueFieldWidth else { return text }
        return text + String(repeating: " ", count: valueFieldWidth - text.count)
    }

    /// The value read-out with **no** field padding (`"52%"`) — the part the
    /// slider actually styles. Kept separate from ``valueLabelText`` so a themed
    /// style (colour / underline) applies to the digits only, not the trailing
    /// blank cell the fixed field pads to.
    private var valueDisplayText: String {
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = range > 0
            ? min(1.0, max(0.0, (value.wrappedValue - bounds.lowerBound) / range))
            : 0
        return "\(Int((fraction * 100).rounded()))%"
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
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette

        // Slider expands to fill available width. `sizeThatFits` REQUESTS at
        // least `minTrackWidth` of track, but at render time we fit whatever
        // width layout actually granted (e.g. a narrower explicit `.frame`):
        // flooring the track here would push the trailing chrome — the right
        // arrow and value field — past `availableWidth`, where it gets clipped
        // and overlaps the next view. Chrome integrity beats track length.
        let showsValue = context.environment.sliderShowsValue
        let trackWidth = max(1, context.availableWidth - chromeWidth(showsValue: showsValue))

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

        // Keep handler in sync with current values — EVERY field the view
        // declares, or the persisted handler keeps the creation render's
        // (stale bounds made clampValue force-write the app's value back
        // inside a range the view no longer declares).
        handler.value = value
        handler.bounds = bounds
        handler.step = step
        handler.canBeFocused = !isDisabled
        // Captured at render so Shift+arrow can accelerate at event time.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.onEditingChanged = onEditingChanged
        handler.clampValue()

        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        // Everything below this line is drawing, so the gate goes here —
        // see `RenderContext.indicatesFocus(_:)`. Key handling is the
        // registered handler's and is untouched: the slider still moves.
        let isFocused = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))

        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        // Calculate fraction, clamped to [0, 1] to handle out-of-bounds values
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = range > 0 ? min(1.0, max(0.0, (value.wrappedValue - bounds.lowerBound) / range)) : 0

        // The whole cycle, not the live phase: the arrows are handed to the run
        // loop to breathe on their own (see `AnimatedCellRun`). Asking for the
        // phase would mark the frame as having consulted the clock, and every
        // tick would then re-render the entire page to repaint two cells.
        let cycle = context.environment.selectionEmphasis.cycle(isFocused && !isDisabled)

        // Build the slider content. The track's DRAWN width comes back with it:
        // a coarse (multi-cell) track style renders narrower than it was asked
        // for, and everything positioned AFTER the track — the right arrow's
        // breathing run, its click zone, the drag mapping — has to be measured
        // from what was drawn, exactly as `Stepper.arrowRuns` measures its own
        // arrows from `buffer.width`. Taking the requested width put the run one
        // column past the arrow, on the blank before the read-out, where the
        // loop replayed a SECOND ▶ breathing out of step with the real one.
        let (content, drawnTrackWidth, valueClaim, trackClaims) = buildContent(
            fraction: fraction,
            isFocused: isFocused,
            isHovered: isHovered,
            palette: palette,
            indicator: cycle,
            trackWidth: trackWidth,
            valueStyle: context.environment.styleCascade.resolve(
                for: [.all, .text, .control(.slider)]),
            isDisabled: isDisabled,
            showsValue: showsValue,
            fillScaling: context.environment.trackGradientScaling,
            emptyScaling: context.environment.trackEmptyGradientScaling,
            graphics: context.gradientGraphics(token: "track-\(context.identity.path)")
        )

        var buffer = FrameBuffer(text: content)
        buffer.opacityRegions += valueClaim.map { [$0] } ?? []
        // The track's own claims, in the track's coordinates, moved to where the
        // layout actually puts it: `"◀ "` is two cells, which `arrowRuns` states as
        // `trackLeft` and this must not spell a second time. A disabled slider
        // produces none — `forState` composites every colour through
        // `opacity(_:over:)` and stamps the result opaque, so its alpha is spent
        // against the page rather than claimed. One colour, two answers, decided by
        // `isEnabled`; §31.3.
        buffer.opacityRegions += trackClaims.map { $0.shifted(byX: Self.trackLeft, y: 0) }
        if !context.isMeasuring {
            buffer.animatedCells = arrowRuns(
                cycle: cycle, palette: palette, drawnTrackWidth: drawnTrackWidth)
        }

        attachMouseHandlers(
            to: &buffer,
            context: context,
            handler: handler,
            hoverBox: hoverBox,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            drawnTrackWidth: drawnTrackWidth
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
        handler: SliderHandler<Double>,
        hoverBox: StateBox<Bool>,
        persistedFocusID: String,
        stateStorage: StateStorage,
        drawnTrackWidth: Int
    ) {
        // Own AND cascaded — `renderToBuffer`'s shadowing local does not reach
        // this helper, so the bare `self.isDisabled` here answered only for a
        // slider disabled by its own modifier. One inside a `.disabled()`
        // container, or under an unselected radio option, kept every mouse
        // handler it had: it dragged, it wheeled, and clicking it took the
        // focus that the keyboard could not reach.
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        mouseDispatcher.requestFeature(.motion)

        let focusManager = context.environment.focusManager
        let track = TrackGeometry(left: 2, width: drawnTrackWidth)  // 2 = "◀ "

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
                handler: handler,
                hoverBox: hoverBox,
                focusManager: focusManager,
                focusID: persistedFocusID,
                leftArrowTimer: leftArrowTimer,
                rightArrowTimer: rightArrowTimer,
                track: track
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
    /// Where the track sits in the slider's own buffer: the three numbers the
    /// arrow zones and the drag mapping are all measured from.
    ///
    /// One value because they are one fact and always travel together — and
    /// because carrying them separately is what pushed this closure's
    /// signature past what the linter will accept, which is the linter being
    /// right about it.
    private struct TrackGeometry {
        /// The track's first column. `"◀ "` precedes it.
        let left: Int
        /// One past its last column; from here on is `" ▶ "` and the value.
        let right: Int
        /// `right - left`.
        let width: Int

        /// The column the `"◀"` glyph occupies — the whole of the left arrow,
        /// not everything before the track: `left - 1` is the space between
        /// them, which is chrome and adjusts nothing.
        var leftArrow: Int { left - 2 }

        /// The column the `"▶"` glyph occupies. `right` itself is the space
        /// before it, and `rightArrow + 1` onwards is the space and the value
        /// read-out — six cells that are NOT the arrow, which is why the zone
        /// is this one column rather than everything from `right` on.
        var rightArrow: Int { right + 1 }

        init(left: Int, width: Int) {
            self.left = left
            self.width = width
            self.right = left + width
        }
    }

    private func mouseHandler(
        handler: SliderHandler<Double>,
        hoverBox: StateBox<Bool>,
        focusManager: FocusManager?,
        focusID: String,
        leftArrowTimer: AutoRepeatTimer,
        rightArrowTimer: AutoRepeatTimer,
        track: TrackGeometry
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
                //
                // A notch is a discrete adjustment like an arrow KEY, not a
                // drag: it begins the edit and, like a key, leaves the end to
                // focus loss. There is no release to end it on.
                handler.beginEditingIfNeeded()
                decrementOnce()
                focusManager?.focus(id: focusID)
                return true
            case .scrollDown:
                handler.beginEditingIfNeeded()
                incrementOnce()
                focusManager?.focus(id: focusID)
                return true
            case .left:
                return Self.handleLeftButton(
                    event: event,
                    handler: handler,
                    value: value,
                    bounds: bounds,
                    step: step,
                    track: track,
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

    /// Dispatches a `.left`-button mouse event among the zones
    /// Slider supports: the left arrow's cell, the right arrow's
    /// cell, the track in between, and the chrome around them
    /// (the spaces beside each arrow and the value read-out),
    /// which focuses but adjusts nothing. Static so it doesn't
    /// capture `self`, avoiding a reference cycle through the
    /// parent closure.
    private static func handleLeftButton( // swiftlint:disable:this function_parameter_count
        event: MouseEvent,
        handler: SliderHandler<Double>,
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        step: Double,
        track: TrackGeometry,
        leftArrowTimer: AutoRepeatTimer,
        rightArrowTimer: AutoRepeatTimer,
        decrementOnce: @escaping @MainActor () -> Void,
        incrementOnce: @escaping @MainActor () -> Void,
        stopArrowTimers: @MainActor () -> Void,
        focusManager: FocusManager?,
        focusID: String
    ) -> Bool {
        switch event.phase {
        case .pressed, .dragged:
            // Each zone is the cells it DRAWS, not the half-plane on its side
            // of the track: the arrows are one glyph each, and the spaces
            // around them plus the value read-out belong to neither. Splitting
            // on `< track.left` / `>= track.right` handed the right arrow the
            // six cells after the track, so a click on the read-out — the
            // natural place to click a slider to focus it — incremented the
            // value and a hold there auto-repeated. `Stepper` bounds its arrows
            // to one cell each for the same reason (see `attachMouseHandlers`
            // there); this does it inside one region because the slider's track
            // drag has to stay continuous across all three zones.
            switch event.x {
            case track.leftArrow:
                // The gesture `onEditingChanged` was designed around — SwiftUI:
                // "editing begins when the user starts to drag the thumb along
                // the slider's track". `.dragged` as well as `.pressed` because
                // a drag can arrive here having begun outside the track; the
                // guard inside makes the second and later reports free.
                handler.beginEditingIfNeeded()
                if event.phase == .pressed {
                    stopArrowTimers()
                    leftArrowTimer.start(action: decrementOnce)
                } else {
                    // .dragged onto the arrow from elsewhere —
                    // stop any track dragging, don't restart
                    // the auto-repeat.
                    stopArrowTimers()
                }
            case track.rightArrow:
                handler.beginEditingIfNeeded()
                if event.phase == .pressed {
                    stopArrowTimers()
                    rightArrowTimer.start(action: incrementOnce)
                } else {
                    stopArrowTimers()
                }
            case track.left..<track.right:
                handler.beginEditingIfNeeded()
                stopArrowTimers()
                applyTrackValue(
                    eventX: event.x,
                    value: value,
                    bounds: bounds,
                    step: step,
                    track: track
                )
            default:
                // Chrome: the gaps beside the arrows and the value read-out.
                // The click is still claimed and still focuses the slider (it
                // is the slider's own row), but it adjusts nothing — and it
                // reports no edit either, because `onEditingChanged` describes
                // a drag of the thumb and no value is about to move.
                stopArrowTimers()
            }
            focusManager?.focus(id: focusID)
            return true
        case .released:
            stopArrowTimers()
            handler.endEditingIfNeeded()
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
        track: TrackGeometry
    ) {
        let pos = max(0, min(track.width - 1, eventX - track.left))
        let range = bounds.upperBound - bounds.lowerBound
        let raw = bounds.lowerBound + (track.width > 1
            ? Double(pos) / Double(track.width - 1)
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

    /// Where the track starts: `"◀ "`, two cells.
    ///
    /// One number, because three things now depend on it — the right arrow's run, the
    /// value read-out's offset, and the track's own opacity claims — and a claim that
    /// disagreed with the runs by one cell would fade the arrow instead of the rail.
    static var trackLeft: Int { 2 }

    /// The runs that breathe the two arrows, so the loop can advance them
    /// without walking the view tree. Empty unless the slider is focused and
    /// the indicator style actually animates.
    ///
    /// The offsets follow the one layout `buildContent` emits — `"◀ TRACK ▶"` —
    /// and the same `trackLeft` the mouse handler maps clicks through, so the
    /// cells a run claims are the cells the arrows were drawn in.
    ///
    /// `drawnTrackWidth`, never the width the track was ASKED for: a coarse
    /// (multi-cell) track style renders narrower than its request, so the two
    /// differ by up to a glyph, and a run one column off the arrow is a second
    /// arrow the loop breathes out of step with the real one.
    @MainActor
    private func arrowRuns(
        cycle: SelectionEmphasisCycle, palette: any Palette, drawnTrackWidth: Int
    ) -> [AnimatedCellRun] {
        guard cycle.isAnimating else { return [] }
        let (dim, bright) = palette.accentPulse()
        let trackLeft = Self.trackLeft
        return [
            cycle.run(
                TerminalSymbols.leftArrow, dim: dim, bright: bright, offsetX: 0, offsetY: 0),
            cycle.run(
                TerminalSymbols.rightArrow, dim: dim, bright: bright,
                offsetX: trackLeft + drawnTrackWidth + 1, offsetY: 0),
        ].compactMap { $0 }
    }

    // Builds the rendered slider content. The nine inputs are all distinct render
    // parameters (geometry, the resolved interaction state, and the value-readout
    // style); bundling them into a throwaway struct only to satisfy the
    // parameter-count ceiling would scatter closely-related render inputs.
    // swiftlint:disable:next function_parameter_count
    private func buildContent(
        fraction: Double,
        isFocused: Bool,
        isHovered: Bool,
        palette: any Palette,
        indicator: SelectionEmphasisCycle,
        trackWidth: Int,
        valueStyle: StyleAttributes,
        isDisabled: Bool,
        showsValue: Bool,
        fillScaling: TrackGradientScaling,
        emptyScaling: TrackGradientScaling,
        graphics: GradientGraphicsContext?
    ) -> (
        content: String, drawnTrackWidth: Int, valueClaim: OpacityRegion?,
        trackClaims: [OpacityRegion]
    ) {
        // Arrow colors:
        //   - Focused: pulsing accent
        //   - Hovered: static accent at the hoverBackground tint, so the
        //     affordance is visible. Focus wins on these particular cells —
        //     they are the only thing either state has to say here, and a
        //     pointer resting on the arrow it already focused must not freeze
        //     the pulse. The hover still shows elsewhere on the control.
        //   - Otherwise: dimmed foregroundTertiary
        let arrowColor: Color
        if isDisabled {
            arrowColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isFocused {
            let (dimAccent, brightAccent) = palette.accentPulse()
            arrowColor = indicator.colorNow(dim: dimAccent, bright: brightAccent)
        } else if isHovered {
            arrowColor = palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
        } else {
            // Dimmed arrows when unfocused
            arrowColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        }

        // Build track. Every colour it is drawn from FADES toward the page when
        // the slider is disabled — the same treatment the arrows and the value
        // read-out already had, and the same expression. Only the filled colour
        // used to change, and only some track styles draw with it: `.bar` and
        // the gradients fill in the ACCENT, which was handed over undimmed, so
        // a disabled slider on the green palette drew a track indistinguishable
        // from a live one and only its label said otherwise.
        func forState(_ color: Color) -> Color {
            guard isDisabled else { return color }
            return color.opacity(ViewConstants.disabledForeground, over: palette.background)
        }
        let track = TrackRenderer.render(
            fraction: fraction,
            width: trackWidth,
            style: trackStyle,
            filledColor: forState(palette.foregroundSecondary),
            emptyColor: forState(palette.foregroundTertiary),
            accentColor: forState(palette.accent),
            fillScaling: fillScaling,
            emptyScaling: emptyScaling,
            palette: palette,
            graphics: graphics
        )

        // Build arrows
        let leftArrow = ANSIRenderer.colorize(TerminalSymbols.leftArrow, foreground: arrowColor)
        let rightArrow = ANSIRenderer.colorize(TerminalSymbols.rightArrow, foreground: arrowColor)

        // Build value label (percentage) — the same source of truth that
        // `chromeWidth` measures, so the label always fits the space reserved.
        // Its colour/weight inherit the slider's scoped style cascade
        // (`.sliderTextStyle { … }`) as soft overrides.
        let valueDisplay = valueDisplayText
        let valueLabelColor =
            isDisabled
            ? palette.foregroundTertiary
            : (valueStyle.foreground?.resolve(with: palette) ?? palette.foregroundSecondary)
        // Style only the digits; append the field padding UNSTYLED so a themed
        // underline sits under "52%", never the blank fourth cell.
        let padding = String(repeating: " ", count: max(0, valueFieldWidth - valueDisplay.count))
        let valueLabel = ANSIRenderer.colorize(
            valueDisplay,
            foreground: valueLabelColor.opaqueSpelling,
            bold: !isDisabled && (valueStyle.bold ?? false),
            underline: !isDisabled && (valueStyle.underline ?? false)) + padding

        // What the track came back as, in CELLS — which is not always the
        // `trackWidth` it was asked for. A multi-cell fill, unfilled or ramp
        // glyph quantises the track, and `TrackRenderer.renderCoarsePattern` then
        // shrinks it to the largest whole multiple of that quantum that fits;
        // deliberately and permanently, so a bar's width cannot wobble with its
        // fill ratio. Everything drawn to the RIGHT of the track moves with it,
        // so say where the track actually ended rather than let the caller
        // assume it got what it asked for.
        let drawnTrackWidth = track.cells

        // Pulsing arrows indicate focus - no extra markers needed. The value
        // read-out is omitted when `.sliderShowsValue(false)` (some surrounding
        // control shows the value instead).
        guard showsValue else {
            return (
                "\(leftArrow) \(track.text) \(rightArrow)", drawnTrackWidth, nil, track.claims)
        }
        // Where the read-out's digits start: `"◀ "` + the track as DRAWN + `" ▶ "`.
        // `drawnTrackWidth` and not `trackWidth`, for the reason `arrowRuns` takes
        // the same number — a coarse track renders narrower than it was asked for,
        // and everything to its right moves with it.
        //
        // The digits only. The field padding is appended unstyled on purpose (see
        // above), so it owes nothing, and the TRACK is deliberately not claimed:
        // its colours are §16.1 row 8, still open, and a rectangle over them here
        // would multiply with the claim that migration adds.
        return (
            "\(leftArrow) \(track.text) \(rightArrow) \(valueLabel)", drawnTrackWidth,
            OpacityRegion.claim(
                offsetX: 5 + drawnTrackWidth, width: valueDisplay.strippedLength, height: 1,
                ink: valueLabelColor),
            track.claims)
    }
}
