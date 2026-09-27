//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ResidualRows.swift
//
//  The rows of the `residual` page, and what they read that is not their
//  element. Each is a shape a review of Option C named: a way a row can be
//  served wrongly once a parent's write stops clearing everything below it.
//  Each is right today for the same reason as the first three: the write that
//  changes it is one the page's body sees, so it clears the page.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - What rows read besides their element

/// A counter one row of the off-window stack reads in its body, and no other
/// row does.
///
/// A row off the window is measured, never drawn, and a body read while
/// measuring is not observed today: only the page's own read of every counter
/// (its status line's sum) invalidates anything when one moves.
@Observable
@MainActor
final class ResidualCounter {
    var value: Int
    init(value: Int) { self.value = value }
}

/// What the tasks' custom button style reads while it makes a button's body.
///
/// A style's body is evaluated inside the button's core, untracked today, so
/// only the page's own read (the status line) invalidates anything when it
/// moves.
@Observable
@MainActor
final class ResidualPalette {
    /// Angle brackets rather than square ones.
    var angled = false
}

/// An object the page injects into the environment, and swaps for another.
///
/// Compared by identity: a row that reads the object sees a different one
/// after the swap, though nothing in its value moved.
@Observable
@MainActor
final class ResidualTheme {
    let name: String
    init(name: String) { self.name = name }
}

/// A payload an existential row holds: which one it is, and what it says.
protocol ResidualPayload {
    var id: Int { get }
    var text: String { get }
}

/// The one kind of payload there is, behind the protocol.
struct ResidualNote: ResidualPayload {
    let id: Int
    var text: String
}

// MARK: - The extra rows

/// A flag drawn from a `Binding` into the page's own `@State`.
///
/// Its `==` leaves the binding out — a `Binding` is not `Equatable` — so two
/// rows over flags that differ compare equal. C refuses a row holding a
/// `Binding` for exactly this reason; this row is what it refuses.
struct ResidualFlagRow<Kind: ResidualRowKind>: View {
    let number: Int
    @Binding var isOn: Bool

    var body: some View {
        Text(verbatim: ResidualText.flag(number, isOn))
    }
}

/// A row holding an existential payload, whose `==` compares its id and not
/// its text: a hand-written `==` over an existential is partial of necessity,
/// which is why C refuses a row holding one.
struct ResidualPayloadRow<Kind: ResidualRowKind>: View {
    let payload: any ResidualPayload

    var body: some View {
        Text(verbatim: ResidualText.payload(payload.id, payload.text))
    }
}

/// An object from the environment: the theme the page injected, by name.
///
/// Its `==` compares only its number, as it must: the object is not part of
/// the row's value but of the environment it is drawn under, which C compares
/// separately.
struct ResidualSwatchRow<Kind: ResidualRowKind>: View {
    let number: Int
    @Environment(ResidualTheme.self) private var theme

    var body: some View {
        Text(verbatim: ResidualText.swatch(theme.name, number))
    }
}

/// One row of the off-window stack: its counter as a bar. The stack scrolls
/// both ways, so its horizontal extent is its widest row's width, and a
/// counter that moves in a row off the window moves the scroll bar.
struct ResidualCounterRow<Kind: ResidualRowKind>: View {
    let number: Int
    let counter: ResidualCounter

    var body: some View {
        Text(verbatim: "c\(number) " + String(repeating: "·", count: counter.value))
    }
}

/// A row that shows its counter as a bar when the bar fits the column, and a
/// word when it does not: a `ViewThatFits` over a candidate that reads the
/// counter and one that does not.
///
/// While the bar does not fit, its candidate is only MEASURED — its body is
/// evaluated to be asked its width, and never drawn — and a body read while
/// measuring is not observed today. The word drawn in its place reads
/// nothing. So when the counter falls back to where the bar fits, the only
/// read that could say so is the one nothing observed: the page's own read
/// (the status line's sum) is what redraws the row today.
struct ResidualFitRow<Kind: ResidualRowKind>: View {
    let number: Int
    let counter: ResidualCounter

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ResidualFitBar(number: number, counter: counter)
            Text(verbatim: ResidualText.fitWord(number))
        }
        .frame(width: ResidualColumns.itemsWidth, alignment: .leading)
    }
}

/// The candidate that reads the counter.
struct ResidualFitBar: View {
    let number: Int
    let counter: ResidualCounter

    var body: some View {
        Text(verbatim: ResidualText.fitBar(number, counter.value))
    }
}

/// An item in the pick list, which carries the page's badge.
struct ResidualPickRow<Kind: ResidualRowKind>: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
    }
}

// Hand-written where a field cannot be compared, and exactly the shape of the
// `==` an app writes there. Isolated, as the views are.
extension ResidualFlagRow: @MainActor Equatable where Kind == EquatableRows {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number }
}
extension ResidualPayloadRow: @MainActor Equatable where Kind == EquatableRows {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.payload.id == rhs.payload.id }
}
extension ResidualSwatchRow: @MainActor Equatable where Kind == EquatableRows {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number }
}
extension ResidualCounterRow: @MainActor Equatable where Kind == EquatableRows {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number && lhs.counter === rhs.counter }
}
extension ResidualPickRow: @MainActor Equatable where Kind == EquatableRows {}
extension ResidualFitRow: @MainActor Equatable where Kind == EquatableRows {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number && lhs.counter === rhs.counter }
}

// MARK: - A custom style that reads a model

/// The tasks' button style: the label in square brackets, or angle ones when
/// the palette says so, and a marker when the button holds the focus.
///
/// `Equatable`, as `ButtonStyle`'s documentation asks of a custom style so
/// that memoization stays on beneath it, and compared by the palette it
/// reads — which does not change when what the palette says does.
struct ResidualButtonStyle: ButtonStyle, Equatable {
    let palette: ResidualPalette

    func makeBody(configuration: Configuration) -> some View {
        Text(verbatim: ResidualText.button(configuration.label, angled: palette.angled, focused: configuration.isFocused))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.palette === rhs.palette }
}

// MARK: - What the rows say

/// The text each extra row draws, in one place, so the page and its check
/// spell it the same way.
enum ResidualText {
    static func flag(_ number: Int, _ isOn: Bool) -> String { "\(isOn ? "[x]" : "[ ]") flag \(number)" }
    static func payload(_ id: Int, _ text: String) -> String { "p\(id) \(text)" }
    static func token(_ number: Int, _ token: String) -> String { "t\(number) \(token)" }
    static func swatch(_ theme: String, _ number: Int) -> String { "\(theme) swatch \(number)" }
    static func fitBar(_ number: Int, _ value: Int) -> String { "f\(number) " + String(repeating: "=", count: value) }
    static func fitWord(_ number: Int) -> String { "f\(number) long" }
    static func button(_ label: String, angled: Bool, focused: Bool) -> String {
        (focused ? ">" : " ") + (angled ? "<\(label)>" : "[\(label)]")
    }
}
