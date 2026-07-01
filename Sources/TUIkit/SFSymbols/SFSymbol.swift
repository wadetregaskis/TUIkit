//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SFSymbol.swift
//
//  Created by LAYERED.work
//  License: MIT

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
        // Binary-search the name-sorted table.
        var low = 0
        var high = table.count
        while low < high {
            let mid = low + (high - low) / 2
            if table[mid].name < name {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low < table.count, table[low].name == name {
            return String(table[low].glyph)
        }
        return nil
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
    /// The name → glyph table, parsed once on first use from the generated
    /// `bakedTable` (one `name<space>HEXCODEPOINT` line per symbol). Sorted
    /// ascending by name — as the generator emits it — so ``glyph(named:)`` can
    /// binary-search it directly, no dictionary to build.
    private static let table: [(name: String, glyph: Character)] = {
        var result: [(name: String, glyph: Character)] = []
        result.reserveCapacity(bakedCount)
        for line in bakedTable.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let space = line.firstIndex(of: " ") else { continue }
            let name = String(line[..<space])
            guard
                let value = UInt32(line[line.index(after: space)...], radix: 16),
                let scalar = Unicode.Scalar(value)
            else { continue }
            result.append((name, Character(scalar)))
        }
        return result
    }()

    /// Public-facing entries (name + glyph string), sorted by name.
    private static let entries: [Entry] = table.map {
        Entry(name: $0.name, glyph: String($0.glyph))
    }
    #endif
}
