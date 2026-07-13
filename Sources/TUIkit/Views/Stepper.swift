//  TUIKit - Terminal UI Kit for Swift
//  Stepper.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Stepper

/// A control that performs increment and decrement actions.
///
/// A stepper displays a value with left and right arrows that the user
/// can use to increment or decrement the value using keyboard controls.
///
/// ## Rendering
///
/// ```
/// Unfocused:    ◀  5  ▶
/// Focused:    ❙ ◀  5  ▶ ❙    (bars + arrows pulsing in accent)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | `->` or `+` | Increment by step |
/// | `<-` or `-` | Decrement by step |
/// | `Home` | Jump to minimum (if range defined) |
/// | `End` | Jump to maximum (if range defined) |
///
/// ## Basic Example
///
/// ```swift
/// @State var quantity: Int = 1
///
/// Stepper("Quantity", value: $quantity)
/// ```
///
/// ## With Range and Step
///
/// ```swift
/// @State var rating: Int = 3
///
/// Stepper("Rating", value: $rating, in: 1...5, step: 1)
/// ```
///
/// ## With Custom Callbacks
///
/// ```swift
/// Stepper("Color") {
///     nextColor()
/// } onDecrement: {
///     previousColor()
/// }
/// ```
public struct Stepper<Label: View>: View {
    /// The label view describing the stepper's purpose.
    let label: Label?

    /// The current value rendered for display, with the value type erased.
    /// SwiftUI's `Stepper<Label>` never shows the value, so it can erase `V`
    /// outright; TUIkit *does* show it, so it captures a formatter here.
    let display: () -> String

    /// Builds the (value-type-erased) focus handler from a focusID and whether
    /// it may take focus. Captures the value binding, bounds, and step in `V`.
    let makeHandler: (String, Bool) -> any StepperDriving

    /// Re-points the persisted handler at this render's value binding — the only
    /// `V`-typed state that must be refreshed each frame.
    let syncValue: (any StepperDriving) -> Void

    /// Custom increment callback.
    let onIncrement: (() -> Void)?

    /// Custom decrement callback.
    let onDecrement: (() -> Void)?

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the stepper is disabled.
    var isDisabled: Bool

    /// Callback when editing begins or ends.
    let onEditingChanged: ((Bool) -> Void)?

    /// Designated initializer over the value-type-erased representation. The
    /// public inits below capture a `Binding<V>` into these closures via
    /// ``eraseStepperValue(value:bounds:step:)``.
    fileprivate init(
        label: Label?,
        display: @escaping () -> String,
        makeHandler: @escaping (String, Bool) -> any StepperDriving,
        syncValue: @escaping (any StepperDriving) -> Void,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self.label = label
        self.display = display
        self.makeHandler = makeHandler
        self.syncValue = syncValue
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        // The label renders inline to the left of the control (SwiftUI parity):
        // "Qty ◀ 5 ▶". An empty/absent label collapses so there's no stray
        // leading space ("◀ 5 ▶"). The control's mouse regions are offset by the
        // composing HStack. `controlKind` lets the label resolve
        // `.stepperTextStyle` like the value.
        HStack(spacing: 0) {
            _CollapsingLabel(label: label, controlDisabled: isDisabled)
            _StepperCore(
                display: display,
                makeHandler: makeHandler,
                syncValue: syncValue,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
                focusID: focusID,
                isDisabled: isDisabled,
                onEditingChanged: onEditingChanged
            )
        }
        .environment(\.controlKind, .stepper)
    }
}

/// Captures a `Binding<V>` (plus optional bounds and step) into the value-type-
/// erased closures ``Stepper`` stores, so `Stepper<Label>` need not be generic
/// over `V` — exactly as SwiftUI's `Stepper<Label>` is not. The persisted
/// ``StepperHandler`` carries all the `V` arithmetic; only its value binding
/// needs refreshing each frame (`syncValue`).
private func eraseStepperValue<V: Strideable>(
    value: Binding<V>,
    bounds: ClosedRange<V>?,
    step: V.Stride
) -> (
    display: () -> String,
    makeHandler: (String, Bool) -> any StepperDriving,
    syncValue: (any StepperDriving) -> Void
) {
    let display: () -> String = { "\(value.wrappedValue)" }
    let makeHandler: (String, Bool) -> any StepperDriving = { focusID, canBeFocused in
        StepperHandler(focusID: focusID, value: value, bounds: bounds, step: step, canBeFocused: canBeFocused)
    }
    // The handler persists across renders; EVERYTHING this render declared
    // must be refreshed on it, not just the value binding — a stale bounds
    // kept clamping increments to a range the view no longer declared
    // (e.g. a ceiling that grew when a mode picker changed).
    let syncValue: (any StepperDriving) -> Void = { handler in
        guard let handler = handler as? StepperHandler<V> else { return }
        handler.value = value
        handler.bounds = bounds
        handler.step = step
    }
    return (display, makeHandler, syncValue)
}

/// Shared treatment for a control's own label views.
enum _ControlLabel {
    /// A disabled control dims its label WITH it — the label is part of the
    /// control, not adjacent content. The dim is the same recipe every
    /// built-in control uses for its disabled chrome, applied as the
    /// environment foreground so a label with its own explicit colour still
    /// wins. Enabled controls get the label back untouched.
    ///
    /// - Parameter controlDisabled: The control's OWN `.disabled()` flag —
    ///   the per-control method bypasses the `\.isEnabled` environment, so
    ///   callers pass it explicitly; either source of disablement dims.
    @MainActor
    static func dimmingWhenDisabled<Label: View>(
        _ label: Label, context: RenderContext, controlDisabled: Bool = false
    ) -> AnyView {
        guard controlDisabled || !context.environment.isEnabled else { return AnyView(label) }
        let palette = context.environment.palette
        return AnyView(
            label.foregroundStyle(
                palette.foregroundTertiary.opacity(
                    ViewConstants.disabledForeground, over: palette.background)))
    }
}

/// Renders an inline control label followed by one separating space — or
/// nothing when the label is empty/blank/absent, so the control isn't preceded
/// by a stray space. Used by ``Stepper`` (and reusable by other inline-labelled
/// controls).
private struct _CollapsingLabel<Label: View>: View, Renderable, Layoutable {
    let label: Label?

    /// The control's own `.disabled()` flag — it bypasses the environment,
    /// so the label must be told explicitly.
    let controlDisabled: Bool

    var body: Never { fatalError("_CollapsingLabel renders via Renderable") }

    /// Size from one render (it drops to nothing for a blank label and adds a
    /// trailing space otherwise — both need the render), flexibility from the label.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        let labelFlexible = label.map {
            measureChild($0, proposal: proposal, context: context).isWidthFlexible
        } ?? false
        return ViewSize(width: size.width, height: size.height, isWidthFlexible: labelFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let label, !(label is EmptyView) else { return FrameBuffer() }
        let buffer = TUIkit.renderToBuffer(
            _ControlLabel.dimmingWhenDisabled(
                label, context: context, controlDisabled: controlDisabled),
            context: context)
        guard !buffer.isBlank else { return FrameBuffer() }
        return FrameBuffer(lines: buffer.lines.map { $0 + " " })
    }
}

// MARK: - Stepper Initializers (Value Binding)

extension Stepper where Label == Text {
    /// Creates a stepper with a title and value binding.
    ///
    /// The value is generic over any `Strideable` (`Int`, `Double`, `Float`, …),
    /// mirroring SwiftUI — a stepper's value is data-model data, not an interface
    /// measurement, so it is not pinned to `Int`.
    ///
    /// - Parameters:
    ///   - title: The title of the stepper.
    ///   - value: The binding to the current value.
    ///   - step: The step size. Defaults to `1`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<S: StringProtocol, V: Strideable>(
        _ title: S,
        value: Binding<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let erased = eraseStepperValue(value: value, bounds: nil, step: step)
        self.init(
            label: Text(String(title)),
            display: erased.display, makeHandler: erased.makeHandler, syncValue: erased.syncValue,
            onIncrement: nil, onDecrement: nil, onEditingChanged: onEditingChanged)
    }

    /// Creates a stepper with a title, value binding, and range.
    ///
    /// - Parameters:
    ///   - title: The title of the stepper.
    ///   - value: The binding to the current value.
    ///   - bounds: The range of valid values.
    ///   - step: The step size. Defaults to `1`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<S: StringProtocol, V: Strideable>(
        _ title: S,
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let erased = eraseStepperValue(value: value, bounds: bounds, step: step)
        self.init(
            label: Text(String(title)),
            display: erased.display, makeHandler: erased.makeHandler, syncValue: erased.syncValue,
            onIncrement: nil, onDecrement: nil, onEditingChanged: onEditingChanged)
    }
}

// MARK: - Stepper Initializers (Custom Callbacks)

extension Stepper where Label == Text {
    /// Creates a stepper with a title and custom increment/decrement callbacks.
    ///
    /// - Parameters:
    ///   - title: The title of the stepper.
    ///   - onIncrement: Callback when increment is requested.
    ///   - onDecrement: Callback when decrement is requested.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<S: StringProtocol>(
        _ title: S,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        var dummy = 0
        let value = Binding(get: { dummy }, set: { dummy = $0 })
        let erased = eraseStepperValue(value: value, bounds: nil, step: 1)
        self.init(
            label: Text(String(title)),
            display: erased.display, makeHandler: erased.makeHandler, syncValue: erased.syncValue,
            onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged)
    }
}

// MARK: - Stepper Initializers (ViewBuilder Label)

extension Stepper {
    /// Creates a stepper with a custom label and value binding.
    ///
    /// - Parameters:
    ///   - value: The binding to the current value.
    ///   - step: The step size. Defaults to `1`.
    ///   - label: A view describing the purpose of the stepper.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: Strideable>(
        value: Binding<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let erased = eraseStepperValue(value: value, bounds: nil, step: step)
        self.init(
            label: label(),
            display: erased.display, makeHandler: erased.makeHandler, syncValue: erased.syncValue,
            onIncrement: nil, onDecrement: nil, onEditingChanged: onEditingChanged)
    }

    /// Creates a stepper with a custom label, value binding, and range.
    ///
    /// - Parameters:
    ///   - value: The binding to the current value.
    ///   - bounds: The range of valid values.
    ///   - step: The step size. Defaults to `1`.
    ///   - label: A view describing the purpose of the stepper.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: Strideable>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let erased = eraseStepperValue(value: value, bounds: bounds, step: step)
        self.init(
            label: label(),
            display: erased.display, makeHandler: erased.makeHandler, syncValue: erased.syncValue,
            onIncrement: nil, onDecrement: nil, onEditingChanged: onEditingChanged)
    }

    /// Creates a stepper with a custom label and increment/decrement callbacks.
    ///
    /// - Parameters:
    ///   - label: A view describing the purpose of the stepper.
    ///   - onIncrement: Callback when increment is requested.
    ///   - onDecrement: Callback when decrement is requested.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init(
        @ViewBuilder label: () -> Label,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        var dummy = 0
        let value = Binding(get: { dummy }, set: { dummy = $0 })
        let erased = eraseStepperValue(value: value, bounds: nil, step: 1)
        self.init(
            label: label(),
            display: erased.display, makeHandler: erased.makeHandler, syncValue: erased.syncValue,
            onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged)
    }
}

// MARK: - Stepper Modifiers

extension Stepper {
    /// Creates a disabled version of this stepper.
    ///
    /// - Parameter disabled: Whether the stepper is disabled.
    /// - Returns: A new stepper with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Stepper {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this stepper.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A stepper with the specified focus identifier.
    public func focusID(_ id: String) -> Stepper {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_StepperCore``. Lifted
/// out of the generic struct because Swift does not allow
/// static stored properties in generic types.
private enum StepperStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
    static let incrementRepeat = 3
    static let decrementRepeat = 4
}

/// Internal view that handles the actual rendering of Stepper. The value type is
/// erased into `display`/`makeHandler`/`syncValue` (see ``Stepper``), so this
/// core is not generic over it. The label is a separate `_CollapsingLabel`
/// sibling in ``Stepper``'s body, so the core has none of its own.
private struct _StepperCore: View, Renderable, Layoutable {
    let display: () -> String
    let makeHandler: (String, Bool) -> any StepperDriving
    let syncValue: (any StepperDriving) -> Void
    let onIncrement: (() -> Void)?
    let onDecrement: (() -> Void)?
    let focusID: String?
    let isDisabled: Bool
    let onEditingChanged: ((Bool) -> Void)?

    var body: Never {
        fatalError("_StepperCore renders via Renderable")
    }

    /// Fixed-size: the arrows plus the value read-out. The label (and any
    /// flexibility it carries) lives in the sibling `_CollapsingLabel`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    private typealias StateIndex = StepperStateIndex

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.environment.stateStorage!
        let palette = context.environment.palette

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "stepper",
            propertyIndex: StateIndex.focusID
        )

        // Get or create the persistent (value-type-erased) handler.
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<any StepperDriving> = stateStorage.storage(
            for: handlerKey,
            default: makeHandler(persistedFocusID, !isDisabled)
        )
        let handler = handlerBox.value

        // Keep handler in sync with current values. `syncValue` refreshes the
        // one `V`-typed field (the value binding); the rest are value-type-free.
        syncValue(handler)
        handler.canBeFocused = !isDisabled
        // Captured at render so Shift+arrow can accelerate at event time.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.onIncrement = onIncrement
        handler.onDecrement = onDecrement
        handler.onEditingChanged = onEditingChanged
        handler.clampValue()

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && !isFocused && hoverBox.value

        // Build the stepper content
        let content = buildContent(
            isFocused: isFocused,
            isHovered: isHovered,
            palette: palette,
            pulsePhase: context.environment.pulsePhase,
            valueStyle: context.environment.styleCascade.resolve(
                for: [.all, .text, .control(.stepper)]),
            isDisabled: isDisabled
        )

        var buffer = FrameBuffer(text: content)

        attachMouseHandlers(
            to: &buffer,
            context: context,
            handler: handler,
            hoverBox: hoverBox,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage
        )

        return buffer
    }

    // MARK: - Mouse handler wiring

    /// Registers the whole-row, increment-arrow, and decrement-
    /// arrow mouse handlers and appends their hit-test regions
    /// to `buffer`. Splitting the row into discrete left-arrow /
    /// value / right-arrow regions mirrors the macOS / SwiftUI
    /// behaviour: clicking the numeric area moves the keyboard
    /// caret into the control without perturbing its value.
    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        handler: any StepperDriving,
        hoverBox: StateBox<Bool>,
        persistedFocusID: String,
        stateStorage: StateStorage
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        mouseDispatcher.requestFeature(.motion)

        let focusManager = context.environment.focusManager
        let totalWidth = buffer.width

        // Whole-row region: scroll-wheel anywhere, focus-only
        // click on the value area, hover state for the whole
        // row. Tagged with the persistent focusID so a
        // surrounding ScrollView's snap-to-focus locates the
        // entire stepper (the narrower arrow regions below
        // intentionally don't carry a focusID).
        let rowID = mouseDispatcher.register(
            wholeRowHandler(
                handler: handler,
                hoverBox: hoverBox,
                focusManager: focusManager,
                focusID: persistedFocusID
            )
        )
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: totalWidth, height: buffer.height,
                handlerID: rowID,
                focusID: persistedFocusID
            )
        )

        // Per-arrow auto-repeat timers, persisted across renders.
        let incrementTimer = autoRepeatTimer(
            stateStorage: stateStorage,
            context: context,
            propertyIndex: StateIndex.incrementRepeat
        )
        let decrementTimer = autoRepeatTimer(
            stateStorage: stateStorage,
            context: context,
            propertyIndex: StateIndex.decrementRepeat
        )

        // Right-arrow region — single cell at x = totalWidth - 1.
        // Closure literals (rather than bare `handler.increment`
        // method references) give Swift a proper
        // @MainActor @Sendable () -> Void to capture; an
        // unapplied method reference isn't Sendable on its own.
        let incrementID = mouseDispatcher.register(
            arrowHandler(
                timer: incrementTimer,
                focusManager: focusManager,
                focusID: persistedFocusID,
                action: { handler.increment(times: 1) }
            )
        )
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: totalWidth - 1, offsetY: 0,
                width: 1, height: buffer.height,
                handlerID: incrementID
            )
        )

        // Left-arrow region — single cell at x = 0.
        let decrementID = mouseDispatcher.register(
            arrowHandler(
                timer: decrementTimer,
                focusManager: focusManager,
                focusID: persistedFocusID,
                action: { handler.decrement(times: 1) }
            )
        )
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: 1, height: buffer.height,
                handlerID: decrementID
            )
        )
    }

    /// Builds the row-wide mouse handler closure: scroll-wheel,
    /// hover, focus-only clicks on the value area.
    private func wholeRowHandler(
        handler: any StepperDriving,
        hoverBox: StateBox<Bool>,
        focusManager: FocusManager?,
        focusID: String
    ) -> @MainActor (MouseEvent) -> Bool {
        { event in
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
                // Wheel up matches "scrolling up through the
                // values" — towards smaller / earlier.
                handler.decrement(times: 1)
                focusManager?.focus(id: focusID)
                return true
            case .scrollDown:
                handler.increment(times: 1)
                focusManager?.focus(id: focusID)
                return true
            case .left:
                guard event.phase == .released else {
                    // Press / drag: claim so subsequent release
                    // routes here, but don't move the value.
                    return event.phase == .pressed
                }
                focusManager?.focus(id: focusID)
                return true
            default:
                return false
            }
        }
    }

    /// Builds an arrow-cell mouse handler closure. Press-and-
    /// hold drives the supplied timer (which fires the action
    /// once immediately, then repeats at a fixed cadence).
    /// Release or drag-off stops the timer.
    private func arrowHandler(
        timer: AutoRepeatTimer,
        focusManager: FocusManager?,
        focusID: String,
        action: @escaping @MainActor () -> Void
    ) -> @MainActor (MouseEvent) -> Bool {
        { event in
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                focusManager?.focus(id: focusID)
                timer.start(action: action)
                return true
            case .released, .dragged:
                timer.stop()
                return true
            default:
                return false
            }
        }
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

    /// Builds the rendered stepper content.
    private func buildContent(
        isFocused: Bool,
        isHovered: Bool,
        palette: any Palette,
        pulsePhase: Double,
        valueStyle: StyleAttributes,
        isDisabled: Bool
    ) -> String {
        // Arrow and value colors:
        //   - Focused: pulsing accent
        //   - Hovered (not focused): static accent at the
        //     hoverBackground tint
        //   - Otherwise: dimmed
        let arrowColor: Color
        let valueColor: Color
        if isDisabled {
            arrowColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
            valueColor = palette.foregroundTertiary
        } else if isFocused {
            // Pulse between 35% and 100% accent
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background)
            arrowColor = Color.lerp(dimAccent, palette.accent, phase: pulsePhase)
            valueColor = palette.foreground
        } else if isHovered {
            arrowColor = palette.accent.opacity(ViewConstants.hoverBackground, over: palette.background)
            valueColor = palette.foregroundSecondary
        } else {
            // Dimmed arrows when unfocused
            arrowColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
            valueColor = palette.foregroundSecondary
        }

        // Build arrows
        let leftArrow = ANSIRenderer.colorize(TerminalSymbols.leftArrow, foreground: arrowColor)
        let rightArrow = ANSIRenderer.colorize(TerminalSymbols.rightArrow, foreground: arrowColor)

        // Build value display — its colour/weight inherit the stepper's scoped
        // style cascade (`.stepperTextStyle { … }`) as soft overrides.
        let effectiveValueColor =
            isDisabled ? valueColor : (valueStyle.foreground?.resolve(with: palette) ?? valueColor)
        let valueText = ANSIRenderer.colorize(
            " \(display()) ",
            foreground: effectiveValueColor,
            bold: !isDisabled && (valueStyle.bold ?? false),
            underline: !isDisabled && (valueStyle.underline ?? false))

        // Pulsing arrows indicate focus - no extra markers needed
        return "\(leftArrow)\(valueText)\(rightArrow)"
    }
}

extension View {
    /// Styles the *value read-out* text of every stepper in this view's subtree
    /// (a `.control(.stepper)`-scoped style entry). The +/- arrows are
    /// unaffected.
    public func stepperTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.stepper), build)
    }
}
