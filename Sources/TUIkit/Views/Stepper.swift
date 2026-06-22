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
    /// The binding to the current value.
    let value: Binding<Int>

    /// The optional range of valid values.
    let bounds: ClosedRange<Int>?

    /// The step size for increment/decrement.
    let step: Int

    /// The label view describing the stepper's purpose.
    let label: Label?

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

    public var body: some View {
        // The label renders inline to the left of the control (SwiftUI parity):
        // "Qty ◀ 5 ▶". An empty/absent label collapses so there's no stray
        // leading space ("◀ 5 ▶"). The control's mouse regions are offset by the
        // composing HStack, so `_StepperCore` is unchanged. `controlKind` lets the
        // label resolve `.stepperTextStyle` like the value.
        HStack(spacing: 0) {
            _CollapsingLabel(label: label)
            _StepperCore(
                value: value,
                bounds: bounds,
                step: step,
                label: Optional<EmptyView>.none,
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

/// Renders an inline control label followed by one separating space — or
/// nothing when the label is empty/blank/absent, so the control isn't preceded
/// by a stray space. Used by ``Stepper`` (and reusable by other inline-labelled
/// controls).
private struct _CollapsingLabel<Label: View>: View, Renderable, Layoutable {
    let label: Label?

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
        let buffer = TUIkit.renderToBuffer(label, context: context)
        guard !buffer.isBlank else { return FrameBuffer() }
        return FrameBuffer(lines: buffer.lines.map { $0 + " " })
    }
}

// MARK: - Stepper Initializers (Value Binding)

extension Stepper where Label == Text {
    /// Creates a stepper with a title and value binding.
    ///
    /// - Parameters:
    ///   - title: The title of the stepper.
    ///   - value: The binding to the current value.
    ///   - step: The step size. Defaults to `1`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<S: StringProtocol>(
        _ title: S,
        value: Binding<Int>,
        step: Int = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = nil
        self.step = step
        self.label = Text(String(title))
        self.onIncrement = nil
        self.onDecrement = nil
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }

    /// Creates a stepper with a title, value binding, and range.
    ///
    /// - Parameters:
    ///   - title: The title of the stepper.
    ///   - value: The binding to the current value.
    ///   - bounds: The range of valid values.
    ///   - step: The step size. Defaults to `1`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<S: StringProtocol>(
        _ title: S,
        value: Binding<Int>,
        in bounds: ClosedRange<Int>,
        step: Int = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.label = Text(String(title))
        self.onIncrement = nil
        self.onDecrement = nil
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
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
        self.value = Binding(get: { dummy }, set: { dummy = $0 })
        self.bounds = nil
        self.step = 1
        self.label = Text(String(title))
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
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
    public init(
        value: Binding<Int>,
        step: Int = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = nil
        self.step = step
        self.label = label()
        self.onIncrement = nil
        self.onDecrement = nil
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }

    /// Creates a stepper with a custom label, value binding, and range.
    ///
    /// - Parameters:
    ///   - value: The binding to the current value.
    ///   - bounds: The range of valid values.
    ///   - step: The step size. Defaults to `1`.
    ///   - label: A view describing the purpose of the stepper.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int>,
        step: Int = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.label = label()
        self.onIncrement = nil
        self.onDecrement = nil
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
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
        self.value = Binding(get: { dummy }, set: { dummy = $0 })
        self.bounds = nil
        self.step = 1
        self.label = label()
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
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

/// Internal view that handles the actual rendering of Stepper.
private struct _StepperCore<Label: View>: View, Renderable, Layoutable {
    let value: Binding<Int>
    let bounds: ClosedRange<Int>?
    let step: Int
    let label: Label?
    let onIncrement: (() -> Void)?
    let onDecrement: (() -> Void)?
    let focusID: String?
    let isDisabled: Bool
    let onEditingChanged: ((Bool) -> Void)?

    var body: Never {
        fatalError("_StepperCore renders via Renderable")
    }

    /// Size from one render (label + fixed stepper controls), flexibility from
    /// the label — a flexible label (e.g. a maxWidth frame) makes the row grow.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        let labelFlexible = label.map {
            measureChild($0, proposal: proposal, context: context).isWidthFlexible
        } ?? false
        return ViewSize(width: size.width, height: size.height, isWidthFlexible: labelFlexible)
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

        // Get or create persistent handler from state storage
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<StepperHandler<Int>> = stateStorage.storage(
            for: handlerKey,
            default: StepperHandler(
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
        handler: StepperHandler<Int>,
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
                action: { handler.increment() }
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
                action: { handler.decrement() }
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
        handler: StepperHandler<Int>,
        hoverBox: StateBox<Bool>,
        focusManager: FocusManager,
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
                handler.decrement()
                focusManager.focus(id: focusID)
                return true
            case .scrollDown:
                handler.increment()
                focusManager.focus(id: focusID)
                return true
            case .left:
                guard event.phase == .released else {
                    // Press / drag: claim so subsequent release
                    // routes here, but don't move the value.
                    return event.phase == .pressed
                }
                focusManager.focus(id: focusID)
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
        focusManager: FocusManager,
        focusID: String,
        action: @escaping @MainActor () -> Void
    ) -> @MainActor (MouseEvent) -> Bool {
        { event in
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                focusManager.focus(id: focusID)
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
            arrowColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
            valueColor = palette.foregroundTertiary
        } else if isFocused {
            // Pulse between 35% and 100% accent
            let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
            arrowColor = Color.lerp(dimAccent, palette.accent, phase: pulsePhase)
            valueColor = palette.foreground
        } else if isHovered {
            arrowColor = palette.accent.opacity(ViewConstants.hoverBackground)
            valueColor = palette.foregroundSecondary
        } else {
            // Dimmed arrows when unfocused
            arrowColor = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
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
            " \(value.wrappedValue) ",
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
