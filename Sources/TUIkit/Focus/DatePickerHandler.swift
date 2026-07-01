//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DatePickerHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Date Picker Handler

/// The focus/keyboard behaviour behind ``DatePicker``, persisted across renders
/// so the active component and any half-typed digits survive re-render.
///
/// Left/Right move between components; Up/Down adjust the active component ±1;
/// typing digits sets it and auto-advances when full. Tab/Enter/Escape are not
/// consumed, so focus can leave the control. All calendar math is delegated to
/// the value-type ``DateFieldModel``.
final class DatePickerHandler: Focusable {
    let focusID: String
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
        case .character(let character) where character.isWholeNumber:
            typeDigit(character)
            return true
        default:
            // Tab/Enter/Escape and everything else propagate so focus can leave.
            return false
        }
    }

    private func typeDigit(_ character: Character) {
        digitBuffer += String(character)
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
