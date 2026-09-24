//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRState.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The styling a run of SGR escapes leaves a terminal in, and the shortest
/// sequence that reproduces it.
///
/// ## Why this exists
///
/// "Restore the styling in force at column N" was answered by CONCATENATING
/// every SGR escape before that column and letting the terminal net them. That
/// is correct — an open and its reset cancel — and it is catastrophic when the
/// answer is itself written back into the line.
///
/// `FrameBuffer.insertOverlay` does exactly that: it rebuilds a row as
/// `prefix + overlay + <style at the suffix> + suffix`. Composite a second
/// child into the same row and the style it replays now includes the first
/// child's replay; a third includes the second's, which included the first's.
/// The row DOUBLES per child. Measured on the Example's Layout page, whose
/// custom `Flow` packs ~19 chips onto one line: **1,015,906 bytes for 129
/// visible cells** — 3,942 bytes per cell, against 3.8 for the same chips one
/// per row. A megabyte of escapes for one row is why that page could be watched
/// painting cell by cell.
///
/// Netting the escapes into a state and emitting it once bounds the replay to a
/// handful of codes no matter how many children a row carries.
///
/// ## What is preserved
///
/// The contract is terminal-state equivalence, not byte equality: feeding a
/// terminal the original run and feeding it ``rendered`` must leave the same
/// styling. Everything SGR can express and TUIkit emits is modelled — the
/// on/off attributes, the 16 foreground and background colours in both
/// brightness ranges, and the 256-colour and 24-bit forms of each.
///
/// A code outside that set is passed through verbatim, in order, ahead of the
/// netted state: unknown means "not safe to reason about", and dropping a code
/// is worse than emitting one too many.
///
/// ## Representation
///
/// A bitmask, two small colour values and a (nearly always empty) array — no
/// `Set`, no `[String]` per colour. This state is parsed and compared once per
/// CELL by the cell diff, the overlay split, the SGR collapse and the opacity
/// blend, on every frame; with a `Set<Int>` of attributes and parameter lists
/// of strings, every copy retained three heap objects and every `apply` split
/// the sequence into strings and parsed each. Numerals are spelled
/// canonically on the way out (`07` in reads back as `7`), which a terminal
/// cannot tell apart; every test model compares the state, not the spelling.
public struct SGRState: Sendable, Equatable {

    /// A colour as SGR spells it: a named code as given (`31`, `97`, `44`,
    /// `107`), a 256-colour index, or 24-bit components. Which slot it is in
    /// says whether the extended forms render as 38 or 48.
    ///
    /// `package`, not `private`, so a caller already holding a colour in a
    /// richer form can reduce it to these three shapes ONCE and state the
    /// result. `Color` lives in a sibling module this one cannot see (they are
    /// declared as siblings with no dependency either way), so the reduction
    /// cannot happen in here — it happens above both, and this is the shape it
    /// hands down. The CASES are the whole of the package surface; every method
    /// below stays internal to this module.
    package enum Colour: Sendable, Equatable {
        case named(Int)
        case indexed(Int)
        case rgb(Int, Int, Int)

        /// The parameters as `apply` would have been given them.
        func codes(introducer: Int) -> [String] {
            switch self {
            case .named(let code): return [String(code)]
            case .indexed(let index): return [String(introducer), "5", String(index)]
            case .rgb(let red, let green, let blue):
                return [String(introducer), "2", String(red), String(green), String(blue)]
            }
        }

        /// Appends the parameters to a sequence under construction.
        func append(to parameters: inout String, introducer: Int) {
            switch self {
            case .named(let code):
                parameters += String(code)
            case .indexed(let index):
                parameters += String(introducer)
                parameters += ";5;"
                parameters += String(index)
            case .rgb(let red, let green, let blue):
                parameters += String(introducer)
                parameters += ";2;"
                parameters += String(red)
                parameters += ";"
                parameters += String(green)
                parameters += ";"
                parameters += String(blue)
            }
        }

        /// A colour from a complete parameter list — one named code, or the
        /// three- or five-element extended forms — or `nil` for anything else.
        init?(parameters: [String]) {
            switch parameters.count {
            case 1:
                guard let code = Int(parameters[0]) else { return nil }
                self = .named(code)
            case 3:
                guard parameters[1] == "5", let index = Int(parameters[2]) else { return nil }
                self = .indexed(index)
            case 5:
                guard parameters[1] == "2", let red = Int(parameters[2]), let green = Int(parameters[3]),
                    let blue = Int(parameters[4])
                else { return nil }
                self = .rgb(red, green, blue)
            default:
                return nil
            }
        }
    }

    /// The on/off attributes: bit `n` is set when attribute `n` (1...9) is on.
    /// Rendered in ascending order, which is bit order.
    private var attributes: UInt16 = 0

    /// The foreground, or `nil` for the terminal's default.
    private var foreground: Colour?

    /// The background, or `nil` for the terminal's default.
    private var background: Colour?

    /// Codes this model does not understand, kept verbatim and in order.
    private var passthrough: [String] = []

    /// Whether the state is the terminal's default — nothing to emit.
    public var isDefault: Bool {
        attributes == 0 && foreground == nil && background == nil && passthrough.isEmpty
    }

    public init() {}

    /// The bits each off-code clears.
    ///
    /// 21 is included alongside 22 for bold: ECMA-48 assigns 21 to
    /// double-underline and many terminals treat it as bold-off, so honouring
    /// both is the conservative reading — this is netting, and treating an
    /// off-code as a no-op would leave styling ON that the original cleared.
    private static func attributesOff(by code: Int) -> UInt16 {
        switch code {
        case 21: return bit(1)
        case 22: return bit(1) | bit(2)  // normal intensity: clears bold and dim
        case 23: return bit(3)
        case 24: return bit(4)
        case 25: return bit(5) | bit(6)
        case 27: return bit(7)
        case 28: return bit(8)
        case 29: return bit(9)
        default: return 0
        }
    }

    private static func bit(_ attribute: Int) -> UInt16 { 1 << UInt16(attribute) }

    /// The attributes that put ink on a cell holding nothing but a space:
    /// underline, blink (both), reverse, strike.
    private static let visibleOnBlankCell: UInt16 = bit(4) | bit(5) | bit(6) | bit(7) | bit(9)

    /// Sets the foreground to a colour's SGR parameters — `["31"]`,
    /// `["38", "5", "n"]`, `["38", "2", "r", "g", "b"]` — or to the terminal's
    /// default for `nil` (what SGR 39 does).
    ///
    /// The same state ``apply(_:)`` reaches for `ESC[<parameters>m`. The parse
    /// is the way to learn a colour from text; this is the way to state one
    /// you already hold — `apply` rebuilt and re-split the sequence per cell
    /// of a translucent overlay, 17% of that page's frame. A list that is not
    /// a complete colour is applied as the sequence it spells.
    ///
    /// - Parameter parameters: A well-formed colour parameter list, or `nil`.
    public mutating func setForeground(parameters: [String]?) {
        guard let parameters else {
            foreground = nil
            return
        }
        // An EMPTY list says nothing, and must therefore do nothing. It is not
        // a colour, so it falls to the `apply` below — where it spells
        // `ESC[m`, a bare SGR 0, which resets the WHOLE state. `Color
        // .foregroundCodes()` returns `[]` at `ColorDepth.noColor`, so at the
        // one depth whose entire contract is "emit no colour", asking for a
        // colour stripped the bold, underline and inverse off the cell —
        // `.opacity()` composites through these setters, so a faded heading
        // came back unemphasised. `backgroundEscape(depth:)` already guards the
        // same emptiness on its own path.
        guard !parameters.isEmpty else { return }
        if let colour = Colour(parameters: parameters) {
            foreground = colour
        } else {
            apply("\u{1B}[" + parameters.joined(separator: ";") + "m")
        }
    }

    /// The background twin of ``setForeground(parameters:)`` (SGR 49 for `nil`).
    public mutating func setBackground(parameters: [String]?) {
        guard let parameters else {
            background = nil
            return
        }
        // See ``setForeground(parameters:)``: an empty list is not a sequence.
        guard !parameters.isEmpty else { return }
        if let colour = Colour(parameters: parameters) {
            background = colour
        } else {
            apply("\u{1B}[" + parameters.joined(separator: ";") + "m")
        }
    }

    /// Sets the foreground to a colour already reduced to the form this state
    /// keeps, or to the terminal's default (SGR 39) for `nil`.
    ///
    /// The third and last way in, and the cheapest: ``apply(_:)`` is for a
    /// colour that arrives as SGR TEXT, ``setForeground(parameters:)`` for one
    /// that arrives as a parameter LIST, and this for one the caller already
    /// holds as the numbers. Reaching the same state through the list costs an
    /// array and a `String` per code on the way out and an `Int` parse per code
    /// on the way back in — for values that were in hand. The opacity blend
    /// pays that once or twice per CELL of every translucent overlay, which is
    /// what this exists for.
    ///
    /// There is deliberately no depth and no "draw no colour" case here: at
    /// `ColorDepth.noColor` the answer is *change nothing*, which no colour
    /// value can say, so the caller decides before calling. `Color
    /// .foregroundCodes()` says the same thing by returning `[]`, which is why
    /// ``setForeground(parameters:)`` guards emptiness rather than applying it.
    ///
    /// - Parameter colour: The colour, or `nil` for the terminal's default.
    package mutating func setForeground(_ colour: Colour?) {
        foreground = colour
    }

    /// The background twin of ``setForeground(_:)`` (SGR 49 for `nil`).
    ///
    /// - Parameter colour: The colour, or `nil` for the terminal's default.
    package mutating func setBackground(_ colour: Colour?) {
        background = colour
    }

    /// Folds one complete escape sequence into the state.
    ///
    /// Non-SGR sequences (anything not ending in `m`) are ignored: they move the
    /// cursor or clear the screen, and neither is "styling in force".
    ///
    /// Walks the bytes and parses each parameter in place: no split, no
    /// `String` per code. A parameter that is not a number is passed through
    /// as the text it was.
    ///
    /// - Parameter sequence: A full escape, `ESC [ … m`.
    public mutating func apply(_ sequence: String) {
        applyReportingBackground(sequence)
    }

    /// What an SGR sequence said about the background.
    package enum BackgroundStatement: Sendable, Equatable {
        /// SGR 0 (or an empty parameter): the background back to the terminal's
        /// default, along with everything else.
        case reset
        /// SGR 49: the terminal's own field, stated as a field.
        case terminalDefault
        /// A colour: a named, 256-colour or 24-bit background.
        case colour
    }

    /// Folds `sequence` into the state exactly as ``apply(_:)`` does, and says
    /// what it said about the background — its LAST statement about it, since a
    /// later parameter overrides an earlier one — or `nil` if it said nothing.
    ///
    /// For a caller that tracks one more background than this state holds — the
    /// one its own output has in force — and would otherwise parse every sequence
    /// twice to keep the two in step: after a sequence that said something the
    /// output has exactly this state's background, and after one that said
    /// nothing it has whatever it had.
    ///
    /// - Parameter sequence: A full escape, `ESC [ … m`.
    /// - Returns: What the sequence last said about the background.
    @discardableResult
    package mutating func applyReportingBackground(_ sequence: String) -> BackgroundStatement? {
        let utf8 = sequence.utf8
        guard utf8.last == 0x6D else { return nil }  // 'm'
        // NOT the `reserveCapacity` that measured SLOWER on `Table.alignText`:
        // that one is about String's inline small-string storage, which an
        // Array does not have, so here it is strictly fewer allocations. The
        // list grows 1→2→4→8, so `ESC[38;2;r;g;bm` reallocates four times
        // for five parameters and throws three buffers away.
        //
        // Eight is the common ceiling, not a bound. A collapsed run carrying a
        // truecolour foreground AND background is spelled
        // `ESC[0;38;2;r;g;b;48;2;r;g;bm` — eleven parameters — which is what
        // `collapsingAdjacentSGR()` emits and what the cell diff re-parses; it
        // grows past this reservation exactly as it grew before.
        //
        // Below the guard, not above it: the opacity blend hands this every
        // cursor move and erase in a row as well as every colour, and those
        // must go on allocating nothing.
        var codes: [Parameter] = []
        codes.reserveCapacity(8)
        // The parameters run from after '[' to before 'm'; a sequence with no
        // '[' has no parameters, which is the same as an empty list.
        var index = utf8.startIndex
        while index < utf8.endIndex, utf8[index] != 0x5B { index = utf8.index(after: index) }  // '['
        if index < utf8.endIndex { index = utf8.index(after: index) }
        let end = utf8.index(before: utf8.endIndex)
        var start = index
        while true {
            var cursor = start
            var value = 0
            var numeric = true
            var empty = true
            while cursor < end, utf8[cursor] != 0x3B {  // ';'
                let byte = utf8[cursor]
                if numeric, byte >= 0x30, byte <= 0x39, value < 100_000_000 {
                    value = value * 10 + Int(byte - 0x30)
                } else {
                    numeric = false
                }
                empty = false
                cursor = utf8.index(after: cursor)
            }
            if empty {
                codes.append(.number(0))  // a bare ESC[m, or an empty slot, is 0
            } else if numeric {
                codes.append(.number(value))
            } else {
                codes.append(.text(String(sequence[start..<cursor])))
            }
            guard cursor < end else { break }
            start = utf8.index(after: cursor)
            if start == end { codes.append(.number(0)); break }  // a trailing ';'
        }
        return apply(codes)
    }

    /// One parsed parameter: a number, or text this model cannot read.
    private enum Parameter {
        case number(Int)
        case text(String)

        var text: String {
            switch self {
            case .number(let value): return String(value)
            case .text(let text): return text
            }
        }
    }

    /// Folds `codes` in, and returns what they last said about the background.
    private mutating func apply(_ codes: [Parameter]) -> BackgroundStatement? {
        var statement: BackgroundStatement?
        var index = 0
        while index < codes.count {
            guard case .number(let value) = codes[index] else {
                passthrough.append(codes[index].text)
                index += 1
                continue
            }
            switch value {
            case 0:
                self = Self()
                statement = .reset
            case 1...9:
                attributes |= Self.bit(value)
            case 21, 22, 23, 24, 25, 27, 28, 29:
                attributes &= ~Self.attributesOff(by: value)
            case 30...37, 90...97:
                foreground = .named(value)
            case 39:
                foreground = nil
            case 40...47, 100...107:
                background = .named(value)
                statement = .colour
            case 49:
                background = nil
                statement = .terminalDefault
            case 38, 48, 58:
                let (consumed, applied) = applyExtendedColour(value, codes, from: index)
                if applied, value == 48 { statement = .colour }
                index += consumed
                continue
            default:
                passthrough.append(String(value))
            }
            index += 1
        }
        return statement
    }

    /// Folds a `38;…`, `48;…` or `58;…` parameter group, and reports how many
    /// parameters it consumed and whether it was read as a colour. An incomplete
    /// group is consumed and ignored: it cannot be read as a colour, and its
    /// digits are not attributes.
    private mutating func applyExtendedColour(
        _ introducer: Int, _ codes: [Parameter], from index: Int
    ) -> (consumed: Int, applied: Bool) {
        let span = Self.extendedColourSpan(codes, from: index)
        let parameters = codes[index..<min(codes.count, index + span)]
        let colour: Colour?
        switch (parameters.count, parameters.dropFirst().first) {
        case (3, .number(5)):
            if case .number(let value) = parameters[index + 2] { colour = .indexed(value) } else { colour = nil }
        case (5, .number(2)):
            if case .number(let red) = parameters[index + 2], case .number(let green) = parameters[index + 3],
                case .number(let blue) = parameters[index + 4]
            {
                colour = .rgb(red, green, blue)
            } else {
                colour = nil
            }
        default:
            colour = nil
        }
        guard let colour else { return (span, false) }
        switch introducer {
        case 38: foreground = colour
        case 48: background = colour
        default: passthrough.append(parameters.map(\.text).joined(separator: ";"))
        }
        return (span, true)
    }

    private static func extendedColourSpan(_ codes: [Parameter], from index: Int) -> Int {
        guard index + 1 < codes.count else { return 1 }
        switch codes[index + 1] {
        case .number(5): return min(3, codes.count - index)
        case .number(2): return min(5, codes.count - index)
        default: return 1
        }
    }

    /// The shortest sequence that puts a default terminal into this state, or
    /// the empty string for the default state.
    public var rendered: String {
        guard !isDefault else { return "" }
        return "\u{1B}[" + parameters + "m"
    }

    /// The netted parameters, `;`-separated: passthrough first, then the
    /// attributes, then the colours.
    ///
    /// Ascending attribute order, so the same state always renders identically
    /// — an unstable rendering would make buffers that ARE equal compare
    /// unequal and defeat the render memo.
    public var parameters: String {
        var result = passthrough.joined(separator: ";")
        var attribute = 1
        while attribute <= 9 {
            if attributes & Self.bit(attribute) != 0 {
                if !result.isEmpty { result += ";" }
                result += String(attribute)
            }
            attribute += 1
        }
        if let foreground {
            if !result.isEmpty { result += ";" }
            foreground.append(to: &result, introducer: 38)
        }
        if let background {
            if !result.isEmpty { result += ";" }
            background.append(to: &result, introducer: 48)
        }
        return result
    }

    /// The shortest sequence that takes a terminal from `previous` to this
    /// state, or the empty string when they are the same.
    ///
    /// A delta — only the components that changed — where one can be spelled:
    /// an attribute that went OFF has no single off-code that is safe on every
    /// terminal, so that case falls back to a reset-prefixed absolute.
    public func rendered(changingFrom previous: Self) -> String {
        guard self != previous else { return "" }
        let absolute = isDefault ? "\u{1B}[0m" : "\u{1B}[0;" + parameters + "m"
        guard previous.attributes & ~attributes == 0,
            previous.passthrough == passthrough
        else { return absolute }

        var codes = ""
        let turnedOn = attributes & ~previous.attributes
        var attribute = 1
        while attribute <= 9 {
            if turnedOn & Self.bit(attribute) != 0 {
                if !codes.isEmpty { codes += ";" }
                codes += String(attribute)
            }
            attribute += 1
        }
        if foreground != previous.foreground {
            if !codes.isEmpty { codes += ";" }
            if let foreground { foreground.append(to: &codes, introducer: 38) } else { codes += "39" }
        }
        if background != previous.background {
            if !codes.isEmpty { codes += ";" }
            if let background { background.append(to: &codes, introducer: 48) } else { codes += "49" }
        }
        // Unreachable — equal attributes, foreground and background with equal
        // passthrough IS equality — but a delta that says nothing would silently
        // leave the previous styling in force, so spend the bytes rather than
        // trust the reasoning.
        guard !codes.isEmpty else { return absolute }
        let delta = "\u{1B}[" + codes + "m"
        // A delta is usually shorter, but not always: going back to the default
        // spells out `ESC[39;49m` where `ESC[0m` says the same in four bytes.
        // Both are correct, so take whichever is smaller.
        return delta.utf8.count <= absolute.utf8.count ? delta : absolute
    }

    /// Whether a cell holding nothing but a space looks the same under this
    /// state as under `other`: the background, the attributes that put ink on
    /// a blank cell, and — only when one of those is on — the foreground they
    /// draw in. A passthrough code is unknown and might draw, so it counts.
    public func paintsBlankCellsIdentically(to other: Self) -> Bool {
        guard background == other.background,
            passthrough.isEmpty, other.passthrough.isEmpty
        else { return false }
        let mine = attributes & Self.visibleOnBlankCell
        guard mine == other.attributes & Self.visibleOnBlankCell else { return false }
        // Those attributes draw in the foreground colour (or, for reverse, AS
        // the background), so with any of them in force the foreground is as
        // visible as the background is.
        return mine == 0 || foreground == other.foreground
    }

    /// Whether reverse video (SGR 7) is in force.
    package var reversesVideo: Bool { attributes & Self.bit(7) != 0 }

    /// Whether an attribute in force draws in the foreground colour on a blank
    /// cell — underline, blink, strike — so the foreground is visible there.
    package var paintsInkOnBlankCell: Bool {
        attributes & (Self.bit(4) | Self.bit(5) | Self.bit(6) | Self.bit(9)) != 0
    }

    /// Whether a background colour is in force (as opposed to the default).
    public var namesBackground: Bool { background != nil }

    /// The background in force, or `nil` for the terminal's default — the value
    /// ``renderedBackground`` spells, for a caller that compares backgrounds
    /// cell by cell and would otherwise build a `String` per cell to do it.
    var backgroundColour: Colour? { background }

    /// The foreground in force, or `nil` for the terminal's default — the ink
    /// twin of ``backgroundColour``, for the same kind of caller.
    var foregroundColour: Colour? { foreground }

    /// `colour` as the escape that puts it in force as the background: what
    /// ``renderedBackground`` spells for a state holding it, and `ESC[49m` for
    /// `nil`, which the rendered form spells as nothing because it starts from
    /// the default and this may not.
    static func backgroundEscape(_ colour: Colour?) -> String {
        guard let colour else { return "\u{1B}[49m" }
        var escape = "\u{1B}["
        colour.append(to: &escape, introducer: 48)
        return escape + "m"
    }

    /// Just the background, as a sequence — what a padded run needs restored
    /// under it — or the empty string when the default is in force.
    public var renderedBackground: String {
        guard let background else { return "" }
        var parameters = ""
        background.append(to: &parameters, introducer: 48)
        return "\u{1B}[" + parameters + "m"
    }
}
