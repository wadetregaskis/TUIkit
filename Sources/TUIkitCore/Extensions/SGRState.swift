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
public struct SGRState: Sendable, Equatable {

    /// The on/off attributes, in the order they are emitted.
    ///
    /// Stored as a set of the codes that turn them ON, because that is what
    /// ``rendered`` needs and it makes the reset codes a plain removal.
    private var attributes: Set<Int> = []

    /// The foreground parameter list (e.g. `["31"]`, `["38", "5", "208"]`), or
    /// `nil` for the terminal's default.
    private var foreground: [String]?

    /// The background parameter list, or `nil` for the terminal's default.
    private var background: [String]?

    /// Codes this model does not understand, kept verbatim and in order.
    private var passthrough: [String] = []

    /// Whether the state is the terminal's default — nothing to emit.
    public var isDefault: Bool {
        attributes.isEmpty && foreground == nil && background == nil && passthrough.isEmpty
    }

    public init() {}

    /// The attribute codes and the codes that switch each one off.
    ///
    /// 21 is included alongside 22 for bold: ECMA-48 assigns 21 to
    /// double-underline and many terminals treat it as bold-off, so honouring
    /// both is the conservative reading — this is netting, and treating an
    /// off-code as a no-op would leave styling ON that the original cleared.
    private static let attributeOff: [Int: Set<Int>] = [
        22: [1, 2],  // normal intensity: clears bold and dim
        23: [3], 24: [4], 25: [5, 6], 27: [7], 28: [8], 29: [9],
        21: [1],
    ]

    /// Folds one complete escape sequence into the state.
    ///
    /// Non-SGR sequences (anything not ending in `m`) are ignored: they move the
    /// cursor or clear the screen, and neither is "styling in force".
    ///
    /// - Parameter sequence: A full escape, `ESC [ … m`.
    /// Sets the foreground to a colour's SGR parameters — `["31"]`,
    /// `["38", "5", "n"]`, `["38", "2", "r", "g", "b"]` — or to the terminal's
    /// default for `nil` (what SGR 39 does).
    ///
    /// Byte-for-byte what ``apply(_:)`` stores for `ESC[<parameters>m`: a
    /// named colour is kept as its one code and an extended one as its
    /// complete parameter list, and 39 clears. The parse is the way to learn
    /// a colour from text; this is the way to state one you already hold —
    /// `apply` rebuilt and re-split the sequence per cell of a translucent
    /// overlay, 17% of that page's frame.
    ///
    /// - Parameter parameters: A well-formed colour parameter list, or `nil`.
    public mutating func setForeground(parameters: [String]?) {
        foreground = parameters
    }

    /// The background twin of ``setForeground(parameters:)`` (SGR 49 for `nil`).
    public mutating func setBackground(parameters: [String]?) {
        background = parameters
    }

    public mutating func apply(_ sequence: String) {
        guard sequence.hasSuffix("m") else { return }
        var parameters = sequence.dropFirst().drop(while: { $0 != "[" }).dropFirst().dropLast()
        if parameters.isEmpty { parameters = "0" }  // a bare ESC[m is a reset

        let codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map {
            $0.isEmpty ? "0" : String($0)
        }
        var index = 0
        while index < codes.count {
            let code = codes[index]
            guard let value = Int(code) else {
                passthrough.append(code)
                index += 1
                continue
            }
            switch value {
            case 0:
                self = Self()
            case 1, 2, 3, 4, 5, 6, 7, 8, 9:
                attributes.insert(value)
            case 21, 22, 23, 24, 25, 27, 28, 29:
                attributes.subtract(Self.attributeOff[value] ?? [])
            case 30...37, 90...97:
                foreground = [code]
            case 39:
                foreground = nil
            case 40...47, 100...107:
                background = [code]
            case 49:
                background = nil
            case 38, 48, 58:
                index += applyExtendedColour(value, codes, from: index)
                continue
            default:
                passthrough.append(code)
            }
            index += 1
        }
    }

    /// Folds one extended-colour sequence — `5;n` (256) or `2;r;g;b` (24-bit)
    /// after a 38/48/58 introducer — and returns how many parameters it
    /// consumed. 58 is the underline colour: not a colour this models, but
    /// its arguments belong to IT and must not be re-parsed as top-level
    /// codes — `58;5;4` read that way nets to blink + underline, two
    /// attributes nobody set — so it rides passthrough as one atom.
    ///
    /// A truncated introducer — `38;5` with no index, `38;2` short of three
    /// channels — is dropped rather than stored: parameter lists are joined
    /// back to back on re-emission, so a stored fragment would consume
    /// whatever code came next (a following `41` becoming the "missing"
    /// palette index, and the background vanishing). What the terminal did
    /// with the malformed original is undefined; eating a neighbour is not.
    private mutating func applyExtendedColour(
        _ introducer: Int, _ codes: [String], from index: Int
    ) -> Int {
        let span = extendedColourSpan(codes, from: index)
        let parameters = Array(codes[index..<min(codes.count, index + span)])
        guard Self.isCompleteExtendedColour(parameters) else { return span }
        switch introducer {
        case 38: foreground = parameters
        case 48: background = parameters
        default: passthrough.append(parameters.joined(separator: ";"))
        }
        return span
    }

    /// How many parameters an extended-colour introducer consumes, including
    /// itself. A malformed run consumes only what is there.
    private func extendedColourSpan(_ codes: [String], from index: Int) -> Int {
        guard index + 1 < codes.count else { return 1 }
        switch codes[index + 1] {
        case "5": return min(3, codes.count - index)
        case "2": return min(5, codes.count - index)
        default: return 1
        }
    }

    /// Whether an extended-colour parameter list is whole: introducer, form,
    /// and every channel the form promises.
    private static func isCompleteExtendedColour(_ parameters: [String]) -> Bool {
        guard parameters.count >= 2 else { return false }
        switch parameters[1] {
        case "5": return parameters.count == 3
        case "2": return parameters.count == 5
        default: return false
        }
    }

    /// The shortest escape sequence that puts a freshly-reset terminal into this
    /// state, or `""` when it is already the default.
    ///
    /// One `ESC[…m` carrying every parameter, rather than one escape per
    /// attribute: same result, fewer bytes, and it is what a terminal parses
    /// fastest.
    public var rendered: String {
        guard !isDefault else { return "" }
        return "\u{1B}[" + parameters + "m"
    }

    /// ``rendered``'s parameter list on its own, for a caller assembling one
    /// escape out of several things — a reset and this state, say.
    public var parameters: String {
        var parameters: [String] = passthrough
        // Sorted so the same state always renders identically — a `Set` has no
        // order, and an unstable rendering would make buffers that ARE equal
        // compare unequal and defeat the render memo.
        parameters += attributes.sorted().map(String.init)
        if let foreground { parameters += foreground }
        if let background { parameters += background }
        return parameters.joined(separator: ";")
    }

    /// The shortest escape sequence that takes a terminal **already in
    /// `previous`** into this state, or `""` when it is already there.
    ///
    /// ``rendered`` answers the same question from a freshly-reset terminal,
    /// which is the only safe answer when the incoming state is unknown — but
    /// inside one built line it is known, because we put it there. Saying only
    /// what changed is most of a frame: the two commonest escapes in a divider
    /// drag were `ESC[0;48;5;16m` (12 bytes, and only the foreground was going
    /// back to default — `ESC[39m`, 5) and `ESC[0;38;5;22;48;5;16m` (19 bytes
    /// over a background that was already 16 — `ESC[38;5;22m`, 11).
    ///
    /// Two changes are NOT expressed as a delta, and both fall back to a
    /// reset-prefixed absolute:
    ///
    /// - **Turning an attribute off.** The off-codes are where terminals
    ///   genuinely disagree — ECMA-48 assigns 21 to double-underline while many
    ///   terminals read it as bold-off, which is why ``apply(_:)`` honours both
    ///   readings. Emitting one would be betting on the terminal's; a reset is
    ///   unambiguous everywhere, and this is the render path.
    /// - **A change in the passthrough codes.** Unknown means "not safe to
    ///   reason about", so it is not safe to reason about the difference either.
    ///
    /// Only `39` / `49` (default foreground / background) are added to the
    /// codes TUIkit emits, and both are universal — see
    /// `Documentation/Terminal-compatibility.md`.
    public func rendered(changingFrom previous: Self) -> String {
        guard self != previous else { return "" }
        let absolute = isDefault ? "\u{1B}[0m" : "\u{1B}[0;" + parameters + "m"
        guard previous.attributes.isSubset(of: attributes),
            previous.passthrough == passthrough
        else { return absolute }

        var codes = attributes.subtracting(previous.attributes).sorted().map(String.init)
        if foreground != previous.foreground { codes += foreground ?? ["39"] }
        if background != previous.background { codes += background ?? ["49"] }
        // Unreachable — equal attributes, foreground and background with equal
        // passthrough IS equality — but a delta that says nothing would silently
        // leave the previous styling in force, so spend the bytes rather than
        // trust the reasoning.
        guard !codes.isEmpty else { return absolute }
        let delta = "\u{1B}[" + codes.joined(separator: ";") + "m"
        // A delta is usually shorter, but not always: going back to the default
        // spells out `ESC[39;49m` where `ESC[0m` says the same in four bytes.
        // Both are correct, so take whichever is smaller.
        return delta.utf8.count <= absolute.utf8.count ? delta : absolute
    }

    /// Whether this state and `other` paint a **blank cell** — a cell holding
    /// nothing but a space — the same.
    ///
    /// Weaker than equality on purpose. Most of what SGR expresses is a
    /// property of a GLYPH, and a blank cell has none: bold, dim, italic and
    /// conceal are all unobservable on a space, and so is the foreground colour
    /// unless something is drawing in it. A screen full of background is
    /// exactly what a terminal UI mostly is — the gutters, the padding to the
    /// right edge, the space between a label and its value — so a diff that
    /// calls those cells dirty because an invisible foreground changed rewrites
    /// most of a row to change nothing anyone can see.
    ///
    /// What IS observable on a space, and so is still compared:
    ///
    /// - the **background**, which is the whole of what a blank cell shows;
    /// - **underline, strikethrough and blink** (4, 5, 6, 9), which draw ink on
    ///   an empty cell, and **reverse** (7), which makes the foreground the
    ///   colour the cell is painted;
    /// - the **foreground**, but only when one of those is in force — that is
    ///   precisely when it has something to colour;
    /// - any **passthrough** code, because unknown means "not safe to reason
    ///   about", and that includes reasoning about whether it is visible.
    ///
    /// The caller must have established that both cells hold a space. This says
    /// nothing about a cell with a glyph in it.
    public func paintsBlankCellsIdentically(to other: Self) -> Bool {
        guard background == other.background,
            passthrough.isEmpty, other.passthrough.isEmpty
        else { return false }
        let mine = attributes.intersection(Self.visibleOnBlankCell)
        guard mine == other.attributes.intersection(Self.visibleOnBlankCell) else { return false }
        // Those attributes draw in the foreground colour (or, for reverse, AS
        // the background), so with any of them in force the foreground is as
        // visible as the background is.
        return mine.isEmpty || foreground == other.foreground
    }

    /// The attributes that put ink on a cell holding nothing but a space.
    private static let visibleOnBlankCell: Set<Int> = [4, 5, 6, 7, 9]

    /// Whether reverse video (SGR 7) is in force — the foreground is the
    /// colour the cell is painted, and the background is the colour any ink
    /// draws in.
    ///
    /// Exposed for the opacity blend, which reasons about the colours a cell
    /// DISPLAYS: a reversed cell's field is its foreground, and a reversed
    /// space is a solid fill, not a blank.
    package var reversesVideo: Bool { attributes.contains(7) }

    /// Whether this state draws a PATTERN of ink on a cell holding nothing but
    /// a space — underline, blink and strikethrough all draw in the foreground
    /// colour with no glyph present.
    ///
    /// Reverse (7) is deliberately not included: it draws no pattern, it swaps
    /// which colour fills the cell, and is answered by ``reversesVideo``. The
    /// remaining codes here are `visibleOnBlankCell` minus it, and the two
    /// definitions must move together.
    package var paintsInkOnBlankCell: Bool {
        !attributes.isDisjoint(with: [4, 5, 6, 9])
    }

    /// Whether this state names a background at all.
    ///
    /// The cheap form of `!renderedBackground.isEmpty`, for the composite path,
    /// which asks it once per escape in an overlay and must not build a string
    /// to find out.
    public var namesBackground: Bool { background != nil }

    /// Just the BACKGROUND half of ``rendered`` — the escape that re-establishes
    /// this state's background colour and says nothing about anything else, or
    /// `""` when the background is the terminal's own.
    ///
    /// Wanted wherever a run of cells is redrawn *in place* over a surface that
    /// is not being redrawn with it. Such a redraw must land on the background
    /// that was already there, but must NOT inherit the foreground, bold or
    /// underline in force at that point — those belong to the text it is
    /// replacing, not to the surface under it.
    public var renderedBackground: String {
        guard let background else { return "" }
        return "\u{1B}[" + background.joined(separator: ";") + "m"
    }
}
