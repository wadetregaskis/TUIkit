//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIDecimal.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ASCII decimal, read without trapping

/// Reads an ASCII decimal run out of terminal bytes.
///
/// Deliberately narrower than `Int.init(_: String)`, and the narrowness is the
/// point: this refuses a sign. Terminal input is untrusted — every CSI
/// parameter arrives from whatever can write to the tty, which includes a
/// corrupted ssh stream, `cat` of a crafted file, or another process sharing
/// the terminal — and `Int(_: String)` accepts `-9223372036854775808`, the one
/// value whose `- 1` overflows. A hand-rolled digit loop has the mirror-image
/// hole and traps on the `* 10` instead.
///
/// Either way the app dies while it holds the terminal in raw mode, leaving a
/// shell with no echo and no line discipline. Every parser here is contracted
/// the other way: the answer to a malformed shape is to drop it.
///
/// `MouseEvent` has had this since its own overflow was fixed, as a private
/// copy with the same reasoning in its doc comment; the key parser and the mode
/// query did not, so it is shared rather than written a third time.
package enum ASCIIDecimal {

    /// The value of `bytes` read as unsigned ASCII decimal, or `nil` if it is
    /// empty, holds anything but `0`…`9` — a sign included — or does not fit
    /// an `Int`.
    package static func value(of bytes: some Collection<UInt8>) -> Int? {
        guard !bytes.isEmpty else { return nil }
        var value = 0
        for byte in bytes {
            guard byte >= 0x30, byte <= 0x39 else { return nil }
            let (shifted, mulOverflow) = value.multipliedReportingOverflow(by: 10)
            let (next, addOverflow) = shifted.addingReportingOverflow(Int(byte - 0x30))
            guard !mulOverflow, !addOverflow else { return nil }
            value = next
        }
        return value
    }
}
