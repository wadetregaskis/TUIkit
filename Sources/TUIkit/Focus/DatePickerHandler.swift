//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DatePickerHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Date Picker Handler

/// The focus/keyboard behaviour behind ``DatePicker``, persisted across renders
/// so the active component and any half-typed digits survive re-render.
///
/// Left/Right move between components; Up/Down adjust the active component ±1
/// and Page Up/Down by its coarse step (``DateFieldModel/pageStep(_:)``);
/// Home/End send it to the ends of its own range; typing digits sets it and
/// auto-advances when full. Tab/Enter/Escape are not consumed, so focus can
/// leave the control. All calendar math is delegated to the value-type
/// ``DateFieldModel``.
final class DatePickerHandler: PersistedFocusable {
    var focusID: String
    var canBeFocused: Bool
    var selection: Binding<Date>
    var model: DateFieldModel

    /// The index (into `model.orderedKinds()`) of the component being edited.
    var activeIndex = 0
    /// Digits typed into the active component before it auto-advances.
    private var digitBuffer = ""

    init(focusID: String, selection: Binding<Date>, model: DateFieldModel, canBeFocused: Bool = true) {
        self.focusID = focusID
        self.selection = selection
        self.model = model
        self.canBeFocused = canBeFocused
    }

    /// The editable components, in order.
    var kinds: [DateFieldModel.Kind] { model.orderedKinds() }

    /// The component currently being edited.
    var activeKind: DateFieldModel.Kind {
        let kinds = self.kinds
        return kinds[min(max(0, activeIndex), kinds.count - 1)]
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .left:
            activeIndex = max(0, activeIndex - 1)
            digitBuffer = ""
            return true
        case .right:
            activeIndex = min(kinds.count - 1, activeIndex + 1)
            digitBuffer = ""
            return true
        case .up:
            selection.wrappedValue = model.adjusted(date: selection.wrappedValue, kind: activeKind, by: 1)
            digitBuffer = ""
            return true
        case .down:
            selection.wrappedValue = model.adjusted(date: selection.wrappedValue, kind: activeKind, by: -1)
            digitBuffer = ""
            return true
        case .pageUp:
            adjust(by: model.pageStep(activeKind))
            return true
        case .pageDown:
            adjust(by: -model.pageStep(activeKind))
            return true
        case .home:
            jump(to: \.lowerBound)
            return true
        case .end:
            jump(to: \.upperBound)
            return true
        case .character(let character):
            // Not `where`-guarded: the digit test and the digit's VALUE are one
            // question, and asking it twice is what let the two answers drift.
            guard let digit = Self.positionalDigit(character) else { return false }
            typeDigit(digit)
            return true
        default:
            // Tab/Enter/Escape and everything else propagate so focus can leave.
            return false
        }
    }

    /// Moves the active component by `delta`, wrapping within the field exactly
    /// as Up/Down do — Page Up from December is March, not next year.
    ///
    /// Shared by Up/Down, Page Up/Down and the mouse wheel, so all three clear a
    /// half-typed digit the same way.
    func adjust(by delta: Int) {
        selection.wrappedValue = model.adjusted(
            date: selection.wrappedValue, kind: activeKind, by: delta)
        digitBuffer = ""
    }

    /// Sends the active component to one end of its own range (Home/End), the
    /// same move `Slider`/`Stepper` make for those keys.
    private func jump(to bound: KeyPath<ClosedRange<Int>, Int>) {
        let kind = activeKind
        let bounds = model.fieldBounds(kind, of: selection.wrappedValue)
        selection.wrappedValue = model.setting(
            date: selection.wrappedValue, kind: kind, to: bounds[keyPath: bound])
        digitBuffer = ""
    }

    /// The 0-9 value of `character` if it is a decimal digit in any script, and
    /// `nil` for everything else — including characters that carry a numeric
    /// value but cannot be typed into a positional field.
    ///
    /// `Character.isWholeNumber`, which this replaces, is the wrong question in
    /// both directions. It is true for `Ⅷ` (8), `③` (3) and `万` (10000), none
    /// of which is a digit you can append to a field; and the code behind it
    /// then read the character with `Int(_:)`, which parses ASCII only, so `٣`
    /// and `३` — what those keyboard layouts actually produce — were consumed
    /// and read as zero.
    ///
    /// Unicode's own `numericType == .decimal` is exactly "decimal digit in a
    /// positional system", so this is derived from the character database
    /// rather than from a hand-written list of ranges that would go stale with
    /// each new script. Every such scalar has a value of 0-9 by definition.
    private static func positionalDigit(_ character: Character) -> Int? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first,
            scalar.properties.numericType == .decimal,
            let value = scalar.properties.numericValue
        else { return nil }
        return Int(exactly: value)
    }

    private func typeDigit(_ digit: Int) {
        digitBuffer += String(digit)
        // Every character in the buffer is an ASCII digit that `String(digit)`
        // wrote, and the buffer is cleared once it reaches `model.width(kind)`,
        // so this parse can neither fail nor overflow.
        let raw = Int(digitBuffer) ?? 0
        let kind = activeKind
        selection.wrappedValue = model.setting(date: selection.wrappedValue, kind: kind, to: raw)
        // Advance once the component is full (max digits typed).
        if digitBuffer.count >= model.width(kind) {
            digitBuffer = ""
            if activeIndex < kinds.count - 1 { activeIndex += 1 }
        }
    }

    func onFocusReceived() {
        digitBuffer = ""
        selection.wrappedValue = model.clamp(selection.wrappedValue)
    }

    func onFocusLost() {
        digitBuffer = ""
    }
}
