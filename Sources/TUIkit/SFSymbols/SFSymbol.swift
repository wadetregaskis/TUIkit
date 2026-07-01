//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SFSymbol.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(AppKit)
import Foundation
#endif

/// Resolves an SF Symbol name (`"star.fill"`, `"gearshape"`) to the terminal
/// glyph that renders it, and enumerates every known symbol.
///
/// ## Very limited circumstances
///
/// SF Symbols are not normal text — they live in a private region of Unicode
/// (the Plane-16 Private Use Area) and only render where a font supplies their
/// glyphs. In a terminal that means **all** of the following must hold:
///
/// - **An Apple platform** (macOS). On Linux every lookup here returns `nil`
///   and ``all`` is empty — the baked table isn't even compiled in.
/// - **A terminal whose font carries the glyphs.** In practice that is
///   **Terminal.app with SF Mono**, with the **SF Symbols font installed**
///   (it is *not* installed by default — download it from Apple's developer
///   site). Elsewhere the codepoints render as missing-glyph boxes.
///
/// Because most users won't have that setup, treat symbols as a progressive
/// enhancement: ``Label(_:systemImage:)`` falls back to showing just its title
/// when a symbol can't be resolved, so code that uses it stays correct
/// everywhere — the glyph simply appears only where it can.
///
/// The name → codepoint mapping is Apple's own, extracted from the SF Symbols
/// app (see `Tools/GenerateSFSymbols`). It is a plain functional mapping; no
/// glyph artwork is reproduced.
///
/// ```swift
/// Label("Favourite", systemImage: "star.fill")   // ★ glyph + title on Apple
/// SFSymbol.glyph(named: "gearshape")              // "􀍟" on Apple, nil elsewhere
/// ```
public enum SFSymbol {

    /// One symbol: its name and the terminal glyph (a single Private-Use
    /// grapheme) that renders it.
    public struct Entry: Sendable, Equatable {
        /// The SF Symbol name, e.g. `"square.and.arrow.up"`.
        public let name: String
        /// The glyph string — one Plane-16 Private-Use scalar.
        public let glyph: String
    }

    /// The glyph that renders the named symbol, or `nil` when it can't be
    /// resolved (an unknown name, or any non-Apple platform).
    ///
    /// The glyph is a single Private-Use grapheme; emit it in a ``Text`` and it
    /// is laid out as a 2-cell wide character (with Terminal.app cursor-advance
    /// compensation applied automatically — see
    /// `Character.terminalAppCursorAdvance`).
    ///
    /// - Parameter name: The SF Symbol name, e.g. `"star.fill"`.
    public static func glyph(named name: String) -> String? {
        #if canImport(AppKit)
        guard let scalar = lookup[name] else { return nil }
        return String(scalar)
        #else
        return nil
        #endif
    }

    /// Every known symbol, sorted by name. Empty on non-Apple platforms.
    ///
    /// The table is large (several thousand entries) and decoded lazily on
    /// first access; this is intended for tooling and browsers (such as the
    /// example app's symbol explorer), not per-frame use.
    public static var all: [Entry] {
        #if canImport(AppKit)
        return entries
        #else
        return []
        #endif
    }

    #if canImport(AppKit)
    /// The Plane-16 Private Use Area base every SF Symbol codepoint offsets from.
    private static let puaBase: UInt32 = 0x10_0000

    /// Decoded `(name, scalar)` pairs, sorted by name. Built once, lazily.
    private static let decoded: [(name: String, scalar: Unicode.Scalar)] = decodeTable()

    /// Name → glyph-scalar map for `O(1)` resolution.
    private static let lookup: [String: Unicode.Scalar] = {
        var map = [String: Unicode.Scalar](minimumCapacity: decoded.count)
        for pair in decoded { map[pair.name] = pair.scalar }
        return map
    }()

    /// Public-facing entries (name + glyph string), sorted by name.
    private static let entries: [Entry] = decoded.map {
        Entry(name: $0.name, glyph: String($0.scalar))
    }

    /// Decodes the baked blob (see `Tools/GenerateSFSymbols` for the format):
    /// a little-endian `UInt32` name-section length, a front-coded name
    /// section, then one little-endian `UInt16` codepoint offset per name.
    private static func decodeTable() -> [(name: String, scalar: Unicode.Scalar)] {
        // The literal is wrapped across lines for readability; ignore the
        // newlines when decoding.
        guard
            let blob = Data(base64Encoded: bakedTableBase64, options: .ignoreUnknownCharacters),
            blob.count >= 4
        else { return [] }
        let bytes = [UInt8](blob)

        let nameLength =
            Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        let nameStart = 4
        let nameEnd = nameStart + nameLength
        guard nameEnd <= bytes.count else { return [] }

        // Front-coded names: each entry is a shared-prefix length, the differing
        // suffix bytes, then a NUL. The shared prefix comes from the previous
        // name, so names rebuild in a single forward pass.
        var names: [String] = []
        names.reserveCapacity(bakedCount)
        var previous: [UInt8] = []
        var index = nameStart
        while index < nameEnd {
            let shared = Int(bytes[index])
            index += 1
            var nameBytes = Array(previous.prefix(shared))
            while index < nameEnd, bytes[index] != 0 {
                nameBytes.append(bytes[index])
                index += 1
            }
            index += 1  // skip the NUL terminator
            // Names are ASCII, so decoding never fails; `?? ""` keeps the
            // name/codepoint positional pairing intact in the impossible case.
            names.append(String(bytes: nameBytes, encoding: .utf8) ?? "")
            previous = nameBytes
        }

        // One UInt16 codepoint offset per name, in the same order.
        var result: [(name: String, scalar: Unicode.Scalar)] = []
        result.reserveCapacity(names.count)
        var cursor = nameEnd
        for name in names {
            guard cursor + 1 < bytes.count else { break }
            let offset = UInt32(bytes[cursor]) | UInt32(bytes[cursor + 1]) << 8
            cursor += 2
            guard let scalar = Unicode.Scalar(puaBase + offset) else { continue }
            result.append((name, scalar))
        }
        return result
    }
    #endif
}
