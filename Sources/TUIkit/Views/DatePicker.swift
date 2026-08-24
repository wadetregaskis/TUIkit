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
/// components, Up/Down adjust the active one, Page Up/Down move it by a coarse
/// step (a decade, a quarter, a week — see `DateFieldModel.pageStep(_:)`),
/// Home/End send it to the ends of its own range, and typing digits sets it:
///
/// ```swift
/// @State private var when = Date()
/// DatePicker("Starts", selection: $when)
/// DatePicker("Date", selection: $when, displayedComponents: .date)
/// DatePicker("Time", selection: $when, in: earliest..., displayedComponents: .hourAndMinute)
/// ```
///
/// > Note: Unlike SwiftUI, this is an inline stepper-style field (no calendar
/// > popup), it lays the components out in a fixed `YYYY-MM-DD HH:MM` order
/// > rather than the environment locale's, and it omits the watchOS-only
/// > `.hourMinuteAndSecond` component. Components wrap within their field (no
/// > carry) and the whole date is clamped to the `in:` range.
/// >
/// > What it does take from the environment is the arithmetic:
/// > ``EnvironmentValues/calendar`` and ``EnvironmentValues/timeZone``, so the
/// > field counts in the subtree's calendar and shows the subtree's zone. Only
/// > `\.locale` is deliberately ignored, and only for the layout — a
/// > locale-ordered field would move its columns about under the caret, which
/// > the typing model depends on not happening.
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
        // `_CollapsingLabel` rather than the label and a stack gap: it is the
        // same "label, one separating space, or nothing at all" unit `Picker`,
        // `Slider` and `Stepper` use, and it is where `.labelsHidden()` is
        // honoured. Spacing 0 because the unit carries its own space.
        HStack(spacing: 0) {
            _CollapsingLabel(label: label, controlDisabled: isDisabled)
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
    /// Creates a date picker with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The three range-constrained siblings below take
    /// one the same way.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a localized title, constrained to a range.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection, in: range,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a localized title and a lower bound.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection, in: range,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a localized title and an upper bound.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection, in: range,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a string title, displayed as written.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: nil, displayedComponents: displayedComponents,
            label: Text(String(title)))
    }

    /// Creates a date picker with a string title, as written, within a range.
    @_disfavoredOverload
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

    /// Creates a date picker with a string title, as written, and a lower bound.
    @_disfavoredOverload
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

    /// Creates a date picker with a string title, as written, and an upper bound.
    @_disfavoredOverload
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
        let stateStorage = context.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "datepicker", propertyIndex: StateIndex.focusID)

        // The subtree's calendar, in the subtree's zone. Both are read here
        // rather than baked into the handler, because the model is rebuilt each
        // frame and reassigned below — so changing either takes effect on the
        // next frame, without the picker having to notice.
        var calendar = context.environment.calendar
        calendar.timeZone = context.environment.timeZone
        let model = DateFieldModel(
            calendar: calendar, components: displayedComponents, range: range)

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
        //
        // Only when it is actually out of range. Writing a binding writes a
        // `StateBox`, which invalidates the render cache and asks for another
        // render — and this runs on every render pass, including a measure. An
        // unconditional store therefore made every frame schedule the next one,
        // forever, drawing an identical picture; see the same shape in
        // `_TabViewCore.tabContentSizes`. `Date` is not `Equatable`-constrained
        // in `Binding`, so nothing upstream can notice the value did not change.
        let clamped = model.clamp(selection.wrappedValue)
        if clamped != selection.wrappedValue { selection.wrappedValue = clamped }

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let isHovered =
            !isDisabled
            && (context.stateStorage!.storage(
                for: StateStorage.StateKey(
                    identity: context.identity, propertyIndex: StateIndex.isHovered),
                default: false) as StateBox<Bool>).value
        let cells = model.cells(date: selection.wrappedValue, activeIndex: isFocused ? handler.activeIndex : -1)
        let activeKind: DateFieldModel.Kind? = isFocused ? handler.activeKind : nil

        // The focused, active component is drawn as a dark glyph on a *pulsing
        // accent* block — explicit palette colours (not SGR reverse-video, which
        // inverts the terminal's default colours and collapses to dark-on-dark
        // on a mid-tone theme), so it's readable on every palette and visibly
        // breathes while focused, the same affordance List/Picker rows use.
        //
        // The whole cycle, not the live phase: reading the phase marks the frame
        // as having consulted the clock, so every tick re-rendered the page to
        // repaint two or three cells. The block is left as an
        // ``AnimatedCellRun`` instead. Gated on `!isMeasuring` so the measure
        // pass never asks at all; it's colour-only, so the width is identical
        // whether or not it's applied.
        let cycle = context.environment.selectionEmphasis.cycle(
            isFocused && !context.isMeasuring)
        let (dimBlock, brightBlock) = palette.accentFillPulse()
        let activeHighlight: Color? = isFocused && !context.isMeasuring
            ? cycle.colorNow(dim: dimBlock, bright: brightBlock) : nil

        /// The active component's cell on its block — one description, used for
        /// the frame drawn now and for every frame of the run that replays it.
        func activeCell(_ text: String, on block: Color) -> String {
            var style = TextStyle()
            style.backgroundColor = block
            style.foregroundColor = palette.foreground
            style.isUnderlined = !isDisabled
            return ANSIRenderer.render(text, with: style.resolved(with: palette))
        }

        var line = ""
        var runs: [AnimatedCellRun] = []
        for cell in cells {
            var style = TextStyle()
            if cell.kind == nil {
                // Separators (the "-", ":" and spaces) stay quiet.
                style.foregroundColor = palette.foregroundSecondary
            } else if let activeKind, cell.kind == activeKind, activeHighlight != nil {
                // Bright text on the pulsing accent block — the same
                // high-contrast, readable affordance List/Picker focused rows use.
                // The block breathes on its own, at the column it lands in.
                if let run = cycle.run(
                    dim: dimBlock, bright: brightBlock, offsetX: line.strippedLength, offsetY: 0,
                    draw: { activeCell(cell.text, on: $0) })
                {
                    runs.append(run)
                }
                line += activeCell(cell.text, on: cycle.colorNow(dim: dimBlock, bright: brightBlock))
                continue
            } else {
                // Every editable component is underlined so the field reads as
                // fillable even before it takes focus.
                let resting =
                    isDisabled ? palette.foregroundTertiary : palette.foreground
                // …and lifts under the pointer, unless the field already has
                // the focus and is saying so with its pulsing block.
                style.foregroundColor =
                    isHovered ? palette.hoveredForeground(resting) : resting
                style.isUnderlined = !isDisabled
            }
            line += ANSIRenderer.render(cell.text, with: style.resolved(with: palette))
        }

        var buffer = FrameBuffer(lines: [line])
        buffer.animatedCells = runs
        registerMouse(context: context, buffer: &buffer, handler: handler, cells: cells, isDisabled: isDisabled)
        return buffer
    }

    /// One wide region: a left-click focuses the field and selects the component
    /// under the cursor; the wheel steps the component under the pointer (the
    /// active one if the pointer is on a separator) and is swallowed, so it
    /// never also scrolls an enclosing page.
    private func registerMouse(
        context: RenderContext, buffer: inout FrameBuffer, handler: DatePickerHandler,
        cells: [DateFieldModel.Cell], isDisabled: Bool
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        let focusID = handler.focusID
        let hoverBox: StateBox<Bool> = context.stateStorage!.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.isHovered),
            default: false)
        // An editable field answers the pointer like every other control.
        mouseDispatcher.requestFeature(.motion)
        let handlerID = mouseDispatcher.register { event in
            switch event.phase {
            case .entered, .moved:
                hoverBox.value = true
                return true
            case .exited:
                hoverBox.value = false
                return true
            default:
                break
            }
            switch event.button {
            case .scrollUp, .scrollDown:
                // The field under the pointer takes the step and becomes the
                // active one; over a separator the active field keeps it.
                if let index = componentIndex(at: event.x, cells: cells) {
                    handler.activeIndex = index
                }
                focusManager?.focus(id: focusID)
                // Wheel up goes towards SMALLER/earlier, as it does on every
                // other wheel control here (Stepper, Slider, and the scrollers
                // themselves). Rolling the wheel is scrolling THROUGH the
                // values, not pressing the Up arrow — the two need not agree,
                // and consistency across controls is what a user actually
                // carries from one to the next.
                handler.adjust(by: event.button == .scrollUp ? -1 : 1)
                // Swallowed, not chained: this is a value control, so the
                // wheel must not also scroll the page underneath it.
                return true
            default:
                break
            }
            switch event.phase {
            case .pressed where event.button == .left:
                // Claim the press so the dispatcher's drag capture pins the
                // matching release to this handler — without it, a press here
                // released over a neighbouring control acts as a click the
                // other control's handler never saw the press for (every
                // sibling control claims its press; see Menu's rationale).
                return true
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
