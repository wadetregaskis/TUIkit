//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SFSymbol.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(CoreText)
    import CoreText
    import CoreGraphics
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
/// enhancement: ``Label/init(_:systemImage:)`` falls back to showing just its title
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
        guard let scalar = scalar(forName: name) else { return nil }
        return String(scalar)
        #else
        return nil
        #endif
    }

    /// Every known symbol, sorted by name. Empty on non-Apple platforms.
    ///
    /// The names are materialised into `String`s lazily on first access — the
    /// only place this type builds a `String` (``glyph(named:)`` never does).
    /// Intended for tooling and browsers (such as the example app's symbol
    /// explorer), not per-frame use.
    public static var all: [Entry] {
        #if canImport(AppKit)
        return entries
        #else
        return []
        #endif
    }

    /// Whether the running system actually carries a font that can draw SF Symbol
    /// glyphs — in practice, whether the **SF Symbols font is installed** (it is
    /// *not* by default; users download it from Apple's developer site).
    ///
    /// ``glyph(named:)`` maps a name to its Private-Use codepoint on every Apple
    /// build whether or not that font is present, so a resolved codepoint alone
    /// doesn't mean anything will render — without the font the terminal draws a
    /// missing-glyph box. This probes CoreText's font-substitution cascade with a
    /// known anchor symbol (`star.fill`): if some installed font supplies a real
    /// glyph for its codepoint, symbols are renderable here; otherwise they are
    /// not, and callers should fall back (``Label/init(_:systemImage:)`` shows just its
    /// title, the example's browser shows a "not available" placeholder).
    ///
    /// Evaluated once and cached. `false` on any platform without CoreText (Linux)
    /// and when the anchor symbol can't be resolved.
    public static let isFontAvailable: Bool = {
        #if canImport(CoreText)
        guard let glyph = glyph(named: "star.fill") else { return false }
        let utf16 = Array(glyph.utf16)  // a Plane-16 scalar → one UTF-16 surrogate pair
        guard !utf16.isEmpty else { return false }
        // A base font whose CoreText cascade the system extends: the SF Symbols
        // font, once installed, joins that cascade, so substitution finds the
        // Private-Use glyph. Menlo is Terminal.app's default and always present.
        let base = CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let substitute = CTFontCreateForString(
            base, glyph as CFString, CFRange(location: 0, length: utf16.count))
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        _ = utf16.withUnsafeBufferPointer { buffer in
            CTFontGetGlyphsForCharacters(substitute, buffer.baseAddress!, &glyphs, utf16.count)
        }
        // For a surrogate pair CTFontGetGlyphsForCharacters puts the composed
        // glyph in [0] and 0 in [1], and reports `false` for that trailing unit —
        // so the mapped glyph in [0], not the bool return, is the real signal.
        return glyphs[0] != 0
        #else
        return false
        #endif
    }()

    #if canImport(AppKit)
    /// The Plane-16 Private Use Area base every codepoint offset is measured from.
    private static let puaBase: UInt32 = 0x10_0000

    /// The glyph scalar for `name`, or `nil`. Binary-searches the baked
    /// `nameBlob` comparing raw UTF-8 bytes — for the ASCII symbol names that is
    /// identical to Swift `String` ordering, so the search touches no `String`
    /// and, on the common path, allocates nothing.
    static func scalar(forName name: String) -> Unicode.Scalar? {
        // Fast path: a native Swift string exposes contiguous UTF-8 storage.
        let found: Unicode.Scalar?? = name.utf8.withContiguousStorageIfAvailable { searchBlob($0) }
        if let found { return found }
        // Rare fallback (e.g. a bridged NSString): copy the query bytes once.
        return Array(name.utf8).withUnsafeBufferPointer { searchBlob($0) }
    }

    /// Lower-bound binary search of `nameBlob` for `query`'s bytes.
    private static func searchBlob(_ query: UnsafeBufferPointer<UInt8>) -> Unicode.Scalar? {
        nameBlob.withUTF8Buffer { blob in
            var low = 0
            var high = bakedCount
            while low < high {
                let mid = low + (high - low) / 2
                if compare(blob, name: mid, to: query) < 0 {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            guard low < bakedCount, compare(blob, name: low, to: query) == 0 else { return nil }
            return Unicode.Scalar(puaBase + UInt32(codepointOffsets[low]))
        }
    }

    /// Unsigned byte-lexicographic comparison of baked name `index` against
    /// `query`: negative if the name sorts before the query, `0` if equal. This
    /// equals Swift `String` ordering because every name is ASCII.
    private static func compare(
        _ blob: UnsafeBufferPointer<UInt8>, name index: Int, to query: UnsafeBufferPointer<UInt8>
    ) -> Int {
        let start = Int(nameStarts[index])
        let end = Int(nameStarts[index + 1]) - 1  // drop the separating newline
        let nameLength = end - start
        let common = min(nameLength, query.count)
        var offset = 0
        while offset < common {
            let lhs = blob[start + offset]
            let rhs = query[offset]
            if lhs != rhs { return lhs < rhs ? -1 : 1 }
            offset += 1
        }
        if nameLength == query.count { return 0 }
        return nameLength < query.count ? -1 : 1
    }

    /// Public-facing entries (name + glyph). Built once, on first access to
    /// ``all`` — the only place a name becomes a `String`.
    private static let entries: [Entry] = {
        var result: [Entry] = []
        result.reserveCapacity(bakedCount)
        nameBlob.withUTF8Buffer { blob in
            for index in 0..<bakedCount {
                let start = Int(nameStarts[index])
                let length = Int(nameStarts[index + 1]) - 1 - start
                let name = String(unsafeUninitializedCapacity: length) { buffer in
                    for offset in 0..<length { buffer[offset] = blob[start + offset] }
                    return length
                }
                let scalar = Unicode.Scalar(puaBase + UInt32(codepointOffsets[index]))!
                result.append(Entry(name: name, glyph: String(scalar)))
            }
        }
        return result
    }()
    #endif
}
