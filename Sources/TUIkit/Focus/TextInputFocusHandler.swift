//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputFocusHandler.swift
//
//  Created by Wade Tregaskis
//  License: MIT
/// A focus handler that consumes ordinary typed characters as CONTENT.
///
/// Adopting this is what puts a handler behind the input dispatcher's layer-0
/// gate: while one is focused, typed keys reach it BEFORE status-bar items and
/// `onKeyPress` handlers, so typing "q" into a field cannot quit the app. The
/// gate used to test `is TextFieldHandler` literally — which is how
/// `TextEditor`, a separate class, shipped with its keystrokes stealable by
/// any lettered status item on the page. A new text-consuming handler adopts
/// this marker; it does not extend a type test.
protocol TextInputFocusHandler: AnyObject {}

extension TextFieldHandler: TextInputFocusHandler {}
extension TextEditorHandler: TextInputFocusHandler {}
// Typed digits are the date picker's CONTENT (`typeDigit`); a lettered or
// digit-bound status item stole them the same way it stole an editor's
// letters. Everything the handler declines — letters, Tab, Escape — still
// falls through to the ordinary layers, so only its digits are protected.
extension DatePickerHandler: TextInputFocusHandler {}
