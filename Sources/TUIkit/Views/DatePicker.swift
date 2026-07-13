//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DatePicker.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - DatePickerComponents

/// The date/time components a ``DatePicker`` shows, mirroring SwiftUI's
/// `DatePickerComponents`.
public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// The year, month, and day.
    public static let date = Self(rawValue: 1 << 0)
    /// The hour and minute.
    public static let hourAndMinute = Self(rawValue: 1 << 1)
}

// MARK: - DatePicker

/// A control for selecting a date and/or time, mirroring SwiftUI's `DatePicker`.
///
/// It renders inline as an editable field — `YYYY-MM-DD HH:MM`, or just the date
/// or time components requested. When focused, Left/Right move between the
/// components, Up/Down adjust the active one, and typing digits sets it:
///
/// ```swift
/// @State private var when = Date()
/// DatePicker("Starts", selection: $when)
/// DatePicker("Date", selection: $when, displayedComponents: .date)
/// DatePicker("Time", selection: $when, in: earliest..., displayedComponents: .hourAndMinute)
/// ```
///
/// > Note: Unlike SwiftUI, this is an inline stepper-style field (no calendar
/// > popup), it uses a fixed numeric format rather than the environment
/// > locale/calendar, and it omits the watchOS-only `.hourMinuteAndSecond`
/// > component. Components wrap within their field (no carry) and the whole date
/// > is clamped to the `in:` range.
public struct DatePicker<Label: View>: View {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let displayedComponents: DatePickerComponents
    let label: Label
    var focusID: String?
    var isDisabled: Bool

    /// The set of date/time components a picker can show.
    public typealias Components = DatePickerComponents

    /// Designated initializer working in the normalized `ClosedRange<Date>?`.
    init(
        selection: Binding<Date>,
        range: ClosedRange<Date>?,
        displayedComponents: DatePickerComponents,
        label: Label
    ) {
        self.selection = selection
        self.range = range
        self.displayedComponents = displayedComponents
        self.label = label
        self.focusID = nil
        self.isDisabled = false
    }

    public var body: some View {
        HStack(spacing: 1) {
            label
            _DatePickerCore(
                selection: selection, range: range,
                displayedComponents: displayedComponents, focusID: focusID, isDisabled: isDisabled)
        }
    }
}

// MARK: - ViewBuilder-label initializers

extension DatePicker {
    /// Creates a date picker with a custom label.
    public init(
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(selection: selection, range: nil, displayedComponents: displayedComponents, label: label())
    }

    /// Creates a date picker constrained to a closed date range.
    public init(
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(selection: selection, range: range, displayedComponents: displayedComponents, label: label())
    }

    /// Creates a date picker with a lower bound.
    public init(
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            selection: selection, range: range.lowerBound...Date.distantFuture,
            displayedComponents: displayedComponents, label: label())
    }

    /// Creates a date picker with an upper bound.
    public init(
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            selection: selection, range: Date.distantPast...range.upperBound,
            displayedComponents: displayedComponents, label: label())
    }
}

// MARK: - String-titled initializers

extension DatePicker where Label == Text {
    /// Creates a date picker with a string title.
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: nil, displayedComponents: displayedComponents,
            label: Text(String(title)))
    }

    /// Creates a date picker with a string title, constrained to a range.
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: range, displayedComponents: displayedComponents,
            label: Text(String(title)))
    }

    /// Creates a date picker with a string title and a lower bound.
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: range.lowerBound...Date.distantFuture,
            displayedComponents: displayedComponents, label: Text(String(title)))
    }

    /// Creates a date picker with a string title and an upper bound.
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: Date.distantPast...range.upperBound,
            displayedComponents: displayedComponents, label: Text(String(title)))
    }
}

// MARK: - Modifiers

extension DatePicker {
    /// Disables the picker.
    public func disabled(_ disabled: Bool = true) -> DatePicker {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier.
    public func focusID(_ id: String) -> DatePicker {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core

private enum DatePickerStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
}

/// Renders the inline date/time field with the active component highlighted, and
/// wires focus + keyboard + click. Fixed size (it hugs the field).
private struct _DatePickerCore: View, Renderable, Layoutable {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let displayedComponents: DatePickerComponents
    let focusID: String?
    let isDisabled: Bool

    private typealias StateIndex = DatePickerStateIndex

    var body: Never {
        fatalError("_DatePickerCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "datepicker", propertyIndex: StateIndex.focusID)

        let model = DateFieldModel(
            calendar: .current, components: displayedComponents, range: range)

        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<DatePickerHandler> = stateStorage.storage(
            for: handlerKey,
            default: DatePickerHandler(
                focusID: persistedFocusID, selection: selection, model: model,
                canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.selection = selection
        handler.model = model
        handler.canBeFocused = !isDisabled
        handler.activeIndex = min(max(0, handler.activeIndex), max(0, model.orderedKinds().count - 1))
        // Keep the bound date within range (the binding is the source of truth).
        selection.wrappedValue = model.clamp(selection.wrappedValue)

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let cells = model.cells(date: selection.wrappedValue, activeIndex: isFocused ? handler.activeIndex : -1)
        let activeKind: DateFieldModel.Kind? = isFocused ? handler.activeKind : nil

        // The focused, active component is drawn as a dark glyph on a *pulsing
        // accent* block — explicit palette colours (not SGR reverse-video, which
        // inverts the terminal's default colours and collapses to dark-on-dark
        // on a mid-tone theme), so it's readable on every palette and visibly
        // breathes while focused, the same affordance List/Picker rows use.
        // Gated on `!isMeasuring` so the measure pass never reads `pulsePhase`;
        // it's colour-only, so width is identical whether or not it's applied.
        let activeHighlight: Color? = (isFocused && !context.isMeasuring)
            ? Color.lerp(
                palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background),
                palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background),
                phase: context.environment.pulsePhase)
            : nil

        var line = ""
        for cell in cells {
            var style = TextStyle()
            if cell.kind == nil {
                // Separators (the "-", ":" and spaces) stay quiet.
                style.foregroundColor = palette.foregroundSecondary
            } else if let activeKind, cell.kind == activeKind, let activeHighlight {
                // Bright text on the pulsing accent block — the same
                // high-contrast, readable affordance List/Picker focused rows use.
                style.backgroundColor = activeHighlight
                style.foregroundColor = palette.foreground
                style.isUnderlined = !isDisabled
            } else {
                // Every editable component is underlined so the field reads as
                // fillable even before it takes focus.
                style.foregroundColor = isDisabled ? palette.foregroundTertiary : palette.foreground
                style.isUnderlined = !isDisabled
            }
            line += ANSIRenderer.render(cell.text, with: style.resolved(with: palette))
        }

        var buffer = FrameBuffer(lines: [line])
        registerMouse(context: context, buffer: &buffer, handler: handler, cells: cells, isDisabled: isDisabled)
        return buffer
    }

    /// One wide region: a left-click focuses the field and selects the component
    /// under the cursor; the wheel adjusts the active component.
    private func registerMouse(
        context: RenderContext, buffer: inout FrameBuffer, handler: DatePickerHandler,
        cells: [DateFieldModel.Cell], isDisabled: Bool
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        let focusID = handler.focusID
        let handlerID = mouseDispatcher.register { event in
            switch event.phase {
            case .released where event.button == .left:
                focusManager?.focus(id: focusID)
                // Select the component whose columns contain the click.
                if let index = componentIndex(at: event.x, cells: cells) {
                    handler.activeIndex = index
                }
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID, focusID: focusID))
    }

    /// The editable-component index whose columns contain `column`, if any.
    private func componentIndex(at column: Int, cells: [DateFieldModel.Cell]) -> Int? {
        var editableIndex = 0
        for cell in cells where cell.kind != nil {
            if cell.columns.contains(column) { return editableIndex }
            editableIndex += 1
        }
        return nil
    }
}
