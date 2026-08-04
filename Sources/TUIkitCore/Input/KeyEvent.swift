//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyEvent.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Key Event

/// Represents a keyboard event.
public struct KeyEvent: Equatable, Sendable {
    /// The key that was pressed.
    public let key: Key

    /// Whether the Ctrl modifier was held.
    public let ctrl: Bool

    /// Whether the Alt/Option modifier was held.
    public let alt: Bool

    /// Whether the Shift modifier was held.
    public let shift: Bool

    /// Creates a key event.
    public init(key: Key, ctrl: Bool = false, alt: Bool = false, shift: Bool = false) {
        self.key = key
        self.ctrl = ctrl
        self.alt = alt
        self.shift = shift
    }

    /// Creates a key event from a character.
    public init(character: Character) {
        self.key = .character(character)
        self.ctrl = false
        self.alt = false
        self.shift = character.isUppercase
    }
}

// MARK: - Key

/// Represents a keyboard key.
public enum Key: Hashable, Sendable {
    // Special keys
    case escape
    case enter
    case tab
    case backspace
    case delete
    case space

    // Arrow keys
    case up
    case down
    case left
    case right

    // Navigation keys
    case home
    case end
    case pageUp
    case pageDown

    // Function keys
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    /// VT220's extra function keys, the legacy CSI-tilde block 25…34.
    ///
    /// Real keys on DEC and full-size PC keyboards. On a Mac they are also
    /// what Apple Terminal sends for **Shift+F5…Shift+F12**, because it has no
    /// modifier encoding for function keys at all and re-codes the chord as a
    /// different key — see ``KeyEvent/normalizingLegacyShiftedFunctionKeys()`` and
    /// `Documentation/Terminal-compatibility.md`.
    case f13, f14, f15, f16, f17, f18, f19, f20

    // Character key
    case character(Character)

    // Bracketed paste (bulk text from terminal paste operation)
    case paste(String)

    /// Creates a Key from a character if it's a simple character.
    public static func from(_ char: Character) -> Self {
        .character(char)
    }
}

// MARK: - ASCII Byte Constants

/// Named constants for ASCII byte values used in terminal input parsing.
///
/// Replaces raw hex literals (e.g. `0x1B`, `0x0D`) with readable names,
/// making the key parsing logic self-documenting.
private enum ASCIIByte {
    // Control characters
    static let backspace: UInt8 = 0x08
    static let tab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let escape: UInt8 = 0x1B
    static let delete: UInt8 = 0x7F

    // Ctrl+key range (Ctrl+A = 0x01 … Ctrl+Z = 0x1A)
    static let ctrlRangeStart: UInt8 = 0x01
    static let ctrlRangeEnd: UInt8 = 0x1A
    static let ctrlToLowerOffset: UInt8 = 0x60

    // Printable ASCII range
    static let printableStart: UInt8 = 0x20
    static let printableEnd: UInt8 = 0x7E

    // CSI introducer
    static let openBracket: UInt8 = 0x5B  // '['

    // Arrow / navigation keys (CSI final byte)
    static let arrowUp: UInt8 = 0x41  // 'A'
    static let arrowDown: UInt8 = 0x42  // 'B'
    static let arrowRight: UInt8 = 0x43  // 'C'
    static let arrowLeft: UInt8 = 0x44  // 'D'
    static let home: UInt8 = 0x48  // 'H'
    static let end: UInt8 = 0x46  // 'F'
    static let tilde: UInt8 = 0x7E  // '~' (extended key terminator)
    static let shiftTab: UInt8 = 0x5A  // 'Z' (Shift+Tab / backtab)
}

// MARK: - Key Parsing

extension KeyEvent {
    /// Parses raw terminal input into a KeyEvent.
    ///
    /// Terminal sends escape sequences for special keys:
    /// - Arrow keys: ESC [ A/B/C/D
    /// - Function keys: ESC [ 1~, ESC [ 2~, etc.
    /// - Ctrl+key: ASCII 1-26
    ///
    /// Reads the VT220 F13…F20 keys as Shift+F5…Shift+F12 instead.
    ///
    /// Apple Terminal has no modifier encoding for function keys: rather than
    /// the `ESC[21;2~` form every other terminal uses, its shipped key map
    /// re-codes **Shift+Fn** (n = 5…12) as the *F(n+8)* sequence, so Shift+F10
    /// arrives as `ESC[32~` — byte-identical to a real F18.
    ///
    /// The collision cannot be resolved from the bytes, so this picks the
    /// reading that is reachable on a Mac keyboard: F13…F20 are keys most Macs
    /// do not have, and Shift+F10 is one anybody can press. Deliberately does
    /// NOT do the same for Apple Terminal's Option aliasing (Opt+Fn → F(n+5)),
    /// which overlaps the *plain* F6…F12 that people press all the time.
    ///
    /// Pure, so it can be tested without a terminal; the host gate lives at the
    /// input edge in `Terminal.finalize`.
    public func normalizingLegacyShiftedFunctionKeys() -> KeyEvent {
        let base: Key
        switch key {
        case .f13: base = .f5
        case .f14: base = .f6
        case .f15: base = .f7
        case .f16: base = .f8
        case .f17: base = .f9
        case .f18: base = .f10
        case .f19: base = .f11
        case .f20: base = .f12
        default: return self
        }
        return KeyEvent(key: base, ctrl: ctrl, alt: alt, shift: true)
    }

    /// - Parameter bytes: The raw input bytes.
    /// - Returns: The parsed key event, or nil if incomplete.
    public static func parse(_ bytes: [UInt8]) -> KeyEvent? {
        guard !bytes.isEmpty else { return nil }

        // Single byte
        if bytes.count == 1 {
            return parseSingleByte(bytes[0])
        }

        // Escape sequence
        if bytes[0] == ASCIIByte.escape {
            return parseEscapeSequence(bytes)
        }

        // UTF-8 character
        if let string = String(bytes: bytes, encoding: .utf8),
            let char = string.first
        {
            return KeyEvent(character: char)
        }

        return nil
    }

    /// Parses a single byte into a key event.
    private static func parseSingleByte(_ byte: UInt8) -> KeyEvent? {
        switch byte {
        case ASCIIByte.escape:
            return KeyEvent(key: .escape)
        case ASCIIByte.carriageReturn, ASCIIByte.lineFeed:
            return KeyEvent(key: .enter)
        case ASCIIByte.tab:
            return KeyEvent(key: .tab)
        case ASCIIByte.delete, ASCIIByte.backspace:
            return KeyEvent(key: .backspace)
        case 0x20:  // Space
            return KeyEvent(key: .space)
        case ASCIIByte.ctrlRangeStart...ASCIIByte.ctrlRangeEnd:
            let char = Character(UnicodeScalar(byte + ASCIIByte.ctrlToLowerOffset))
            return KeyEvent(key: .character(char), ctrl: true)
        case (ASCIIByte.printableStart + 1)...ASCIIByte.printableEnd:  // Skip space (0x20), handled above
            let char = Character(UnicodeScalar(byte))
            return KeyEvent(character: char)
        default:
            return nil
        }
    }

    /// Parses an escape sequence into a key event.
    private static func parseEscapeSequence(_ bytes: [UInt8]) -> KeyEvent? {
        guard bytes.count >= 2 else {
            // Just ESC alone
            return KeyEvent(key: .escape)
        }

        // Meta-prefixed sequence ("option as meta key"): ESC + a full escape
        // sequence — e.g. Option-Shift-Tab arrives as ESC ESC [ Z. Parse the
        // inner sequence and mark alt.
        if bytes[1] == 0x1B {
            if bytes.count > 2, let inner = parseEscapeSequence(Array(bytes.dropFirst())) {
                return KeyEvent(key: inner.key, ctrl: inner.ctrl, alt: true, shift: inner.shift)
            }
            return KeyEvent(key: .escape, alt: true)
        }

        // CSI sequences: ESC [
        if bytes[1] == ASCIIByte.openBracket {
            return parseCSISequence(Array(bytes.dropFirst(2)))
        }

        // SS3 sequences: ESC O (F1-F4 on some terminals)
        if bytes[1] == 0x4F && bytes.count >= 3 {  // 'O'
            return parseSS3Sequence(bytes[2])
        }

        // Alt+key: ESC followed by key
        if bytes.count == 2 {
            if let keyEvent = parseSingleByte(bytes[1]) {
                return KeyEvent(key: keyEvent.key, ctrl: keyEvent.ctrl, alt: true, shift: keyEvent.shift)
            }
        }

        // Alt + a multi-byte UTF-8 character: a meta-sending terminal
        // prefixes whatever the keyboard produced, ASCII or not (Option+ß on
        // a German layout arrives as ESC + the two bytes of ß).
        if bytes.count > 2,
            let string = String(bytes: bytes.dropFirst(), encoding: .utf8),
            string.count == 1, let character = string.first
        {
            return KeyEvent(key: .character(character), alt: true)
        }

        return KeyEvent(key: .escape)
    }

    /// Parses SS3 (Single Shift 3) sequences for F1-F4.
    ///
    /// Some terminals send F1-F4 as `ESC O P/Q/R/S`.
    private static func parseSS3Sequence(_ byte: UInt8) -> KeyEvent? {
        switch byte {
        case 0x50: return KeyEvent(key: .f1)  // 'P'
        case 0x51: return KeyEvent(key: .f2)  // 'Q'
        case 0x52: return KeyEvent(key: .f3)  // 'R'
        case 0x53: return KeyEvent(key: .f4)  // 'S'
        default: return nil
        }
    }

    /// Parses a CSI (Control Sequence Introducer) sequence.
    ///
    /// CSI format: `ESC [ <params> <final-byte>`.
    /// The final byte identifies the key (e.g. `A` = up arrow).
    /// Numeric parameters before the final byte encode extended keys
    /// like Page Up/Down (`ESC [ 5 ~`).
    ///
    /// Modifier keys are encoded as `ESC [ 1 ; <modifier> <key>`:
    /// - 2 = Shift
    /// - 3 = Alt
    /// - 4 = Shift+Alt
    /// - 5 = Ctrl
    /// - 6 = Shift+Ctrl
    /// - 7 = Alt+Ctrl
    /// - 8 = Shift+Alt+Ctrl
    private static func parseCSISequence(_ params: [UInt8]) -> KeyEvent? {
        guard !params.isEmpty else { return nil }

        // Extract modifier from params if present (format: "1;2A" for Shift+Up)
        let modifiers = extractModifiers(from: params)

        // The last byte is the CSI function identifier
        switch params.last {
        case ASCIIByte.arrowUp:
            return KeyEvent(key: .up, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.arrowDown:
            return KeyEvent(key: .down, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.arrowRight:
            return KeyEvent(key: .right, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.arrowLeft:
            return KeyEvent(key: .left, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.home:
            return KeyEvent(key: .home, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.end:
            return KeyEvent(key: .end, ctrl: modifiers.ctrl, alt: modifiers.alt, shift: modifiers.shift)
        case ASCIIByte.tilde:
            return parseExtendedKey(params, modifiers: modifiers)
        case ASCIIByte.shiftTab:
            // Shift+Tab: ESC [ Z (CSI Z / backtab)
            return KeyEvent(key: .tab, shift: true)
        default:
            return nil
        }
    }

    /// Extracts modifier flags from CSI parameters.
    ///
    /// Format: `1;2` where 2 is the modifier code.
    /// Modifier codes (xterm standard):
    /// - 2 = Shift
    /// - 3 = Alt
    /// - 4 = Shift+Alt
    /// - 5 = Ctrl
    /// - 6 = Shift+Ctrl
    /// - 7 = Alt+Ctrl
    /// - 8 = Shift+Alt+Ctrl
    private static func extractModifiers(from params: [UInt8]) -> (shift: Bool, alt: Bool, ctrl: Bool) {
        // Look for semicolon separator
        guard let semicolonIndex = params.firstIndex(of: 0x3B) else {  // ';' = 0x3B
            return (shift: false, alt: false, ctrl: false)
        }

        // Extract modifier number after semicolon (before final byte)
        let modifierBytes = params[(semicolonIndex + 1)..<(params.count - 1)]
        guard let string = String(bytes: modifierBytes, encoding: .ascii),
            let modifier = Int(string)
        else {
            return (shift: false, alt: false, ctrl: false)
        }

        // Decode modifier bits (modifier - 1 gives the bit flags)
        // Bit 0 = Shift, Bit 1 = Alt, Bit 2 = Ctrl
        let bits = modifier - 1
        let shift = (bits & 1) != 0
        let alt = (bits & 2) != 0
        let ctrl = (bits & 4) != 0

        return (shift: shift, alt: alt, ctrl: ctrl)
    }

    // The complexity is the VT-key switch itself; splitting it into
    // per-group helpers fragments the table without simplifying. The
    // suppression is in block form so the doc comment stays adjacent to
    // the function (the `:next` form would orphan it).
    // swiftlint:disable cyclomatic_complexity
    /// Parses extended key sequences (`ESC [ n ~` or `ESC [ n ; m ~`).
    ///
    /// These are VT-style sequences where `n` is a numeric key identifier:
    /// - 1=Home, 2=Insert, 3=Delete, 4=End, 5=PageUp, 6=PageDown
    /// - 11-15=F1-F5, 17-21=F6-F10, 23-24=F11-F12, 25-34=F13-F20
    ///
    /// The gaps are historical: 16, 22, 27 and 30 were never assigned.
    ///
    /// With modifiers: `ESC [ 3 ; 2 ~` = Shift+Delete
    private static func parseExtendedKey(
        _ params: [UInt8],
        modifiers: (shift: Bool, alt: Bool, ctrl: Bool) = (false, false, false)
    ) -> KeyEvent? {
        // Extract the numeric identifier before the '~' terminator or ';'
        let numberBytes: ArraySlice<UInt8>
        if let semicolonIndex = params.firstIndex(of: 0x3B) {
            numberBytes = params[..<semicolonIndex]
        } else {
            numberBytes = params.dropLast()
        }

        guard let string = String(bytes: numberBytes, encoding: .ascii),
            let number = Int(string)
        else {
            return nil
        }

        let shift = modifiers.shift
        let alt = modifiers.alt
        let ctrl = modifiers.ctrl

        switch number {
        // Navigation keys
        case 1: return KeyEvent(key: .home, ctrl: ctrl, alt: alt, shift: shift)
        case 2: return nil  // Insert - not commonly used in TUI apps
        case 3: return KeyEvent(key: .delete, ctrl: ctrl, alt: alt, shift: shift)
        case 4: return KeyEvent(key: .end, ctrl: ctrl, alt: alt, shift: shift)
        case 5: return KeyEvent(key: .pageUp, ctrl: ctrl, alt: alt, shift: shift)
        case 6: return KeyEvent(key: .pageDown, ctrl: ctrl, alt: alt, shift: shift)

        // Function keys (VT-style)
        case 11: return KeyEvent(key: .f1, ctrl: ctrl, alt: alt, shift: shift)
        case 12: return KeyEvent(key: .f2, ctrl: ctrl, alt: alt, shift: shift)
        case 13: return KeyEvent(key: .f3, ctrl: ctrl, alt: alt, shift: shift)
        case 14: return KeyEvent(key: .f4, ctrl: ctrl, alt: alt, shift: shift)
        case 15: return KeyEvent(key: .f5, ctrl: ctrl, alt: alt, shift: shift)
        case 17: return KeyEvent(key: .f6, ctrl: ctrl, alt: alt, shift: shift)
        case 18: return KeyEvent(key: .f7, ctrl: ctrl, alt: alt, shift: shift)
        case 19: return KeyEvent(key: .f8, ctrl: ctrl, alt: alt, shift: shift)
        case 20: return KeyEvent(key: .f9, ctrl: ctrl, alt: alt, shift: shift)
        case 21: return KeyEvent(key: .f10, ctrl: ctrl, alt: alt, shift: shift)
        case 23: return KeyEvent(key: .f11, ctrl: ctrl, alt: alt, shift: shift)
        case 24: return KeyEvent(key: .f12, ctrl: ctrl, alt: alt, shift: shift)

        // VT220 F13–F20. Modifiers still apply where a terminal sends them:
        // `ESC[32;2~` means Shift+F18, distinct from the bare `ESC[32~` that
        // Apple Terminal uses to mean Shift+F10.
        case 25: return KeyEvent(key: .f13, ctrl: ctrl, alt: alt, shift: shift)
        case 26: return KeyEvent(key: .f14, ctrl: ctrl, alt: alt, shift: shift)
        case 28: return KeyEvent(key: .f15, ctrl: ctrl, alt: alt, shift: shift)
        case 29: return KeyEvent(key: .f16, ctrl: ctrl, alt: alt, shift: shift)
        case 31: return KeyEvent(key: .f17, ctrl: ctrl, alt: alt, shift: shift)
        case 32: return KeyEvent(key: .f18, ctrl: ctrl, alt: alt, shift: shift)
        case 33: return KeyEvent(key: .f19, ctrl: ctrl, alt: alt, shift: shift)
        case 34: return KeyEvent(key: .f20, ctrl: ctrl, alt: alt, shift: shift)

        default: return nil
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
