//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKey.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - LocalizedStringKey

/// The key for a localized string. Matches SwiftUI's type of the same name.
///
/// ```swift
/// Text("button.save")            // looked up; falls back to "button.save"
/// Text("Hello, \(name)!")        // key "Hello, %@!", then substituted
/// Text(someString)               // NOT looked up — see below
/// ```
///
/// ## Why a string literal is a key and a `String` is not
///
/// This is SwiftUI's rule, and it falls out of overload resolution rather than
/// from anything magic: ``Text`` has one initializer taking a
/// `LocalizedStringKey` and another generic over `StringProtocol`, and Swift
/// prefers the concrete one for a literal. So a literal is a key; a `String`
/// you computed is content. ``Text/init(verbatim:)`` opts a literal
/// out.
///
/// Lookup goes through ``LocalizationService``, which falls back to English and
/// then to the key itself — so an app that never registers a translation sees
/// exactly the literal it wrote, which is what makes adopting this
/// behaviour-preserving. TUIkit's own keys are dot-separated
/// (`button.save`), so ordinary prose cannot collide with one by accident.
///
/// ## Interpolation
///
/// An interpolated literal becomes a key with `%@` where each value went, so
/// one entry in the table serves every value — and a translation can reorder
/// them with the positional form:
///
/// ```swift
/// Text("Moved \(count) rows to \(destination)")
/// // key: "Moved %@ rows to %@"
/// // de:  "%2$@ um %1$@ Zeilen erweitert"
/// ```
///
/// Values are converted to text **eagerly**, at the point of interpolation, the
/// same way ``Text/init(_:format:)`` formats eagerly — so
/// `\(value, format: .percent)` works and the result is a plain, `Sendable`
/// key.
///
/// > Note: A key with **no** interpolations is never scanned for placeholders,
///   so `Text("100% done")` says exactly that. Scanning only happens when there
///   is something to substitute, and an unrecognised `%` sequence is passed
///   through either way.
///
/// > Note: SwiftUI's `tableName:bundle:comment:` parameters are absent —
///   TUIkit's localization is a registered dictionary, with no bundles or
///   string tables for them to name.
public struct LocalizedStringKey: Equatable, Hashable, Sendable {
    /// The lookup key: the literal, with `%@` where each interpolation was.
    let key: String

    /// The interpolated values, already converted to text.
    let arguments: [String]

    /// Creates a key from a string.
    ///
    /// - Parameter value: The key to look up.
    public init(_ value: String) {
        self.key = value
        self.arguments = []
    }

    init(key: String, arguments: [String]) {
        self.key = key
        self.arguments = arguments
    }

    /// The localized text: the key resolved against `service`, with any
    /// interpolated values substituted into it.
    ///
    /// - Parameter service: Where to look the key up.
    /// - Returns: The text to display.
    func resolved(with service: LocalizationService) -> String {
        let template = service.string(for: key)
        guard !arguments.isEmpty else { return template }
        return Self.substituting(arguments, into: template)
    }

    /// The localized text, resolved through the shared service.
    ///
    /// Every control that takes a title resolves **eagerly**, at construction,
    /// exactly as ``Text/init(_:)-(LocalizedStringKey)`` does — which is what
    /// lets a control keep storing a plain `String` and changes nothing about
    /// how it measures or renders. Nothing is lost by resolving early: the view
    /// tree is rebuilt every frame, so a language switched at runtime is picked
    /// up on the next one.
    ///
    /// It is public so your own controls can take a `LocalizedStringKey` and
    /// follow the same rule:
    ///
    /// ```swift
    /// struct FieldRow: View {
    ///     let label: String
    ///
    ///     init(_ labelKey: LocalizedStringKey) { self.init(labelKey.localized) }
    ///
    ///     @_disfavoredOverload
    ///     init<S: StringProtocol>(_ label: S) { self.label = String(label) }
    ///
    ///     var body: some View { Text(label.padded(to: 20)) }
    /// }
    /// ```
    ///
    /// > Important: Write the disfavoured twin **generic over `StringProtocol`**,
    ///   as SwiftUI does, not as a concrete `String`. `@_disfavoredOverload`
    ///   alone is not enough: Swift 6.3 ranks a concrete `String` parameter
    ///   above `LocalizedStringKey` for a literal anyway once the initializer
    ///   takes another required argument, so the literal stops being a key with
    ///   no diagnostic. Swift 6.2 did not, which is how the concrete spelling
    ///   shipped working and later broke — see `SwiftUI-compatibility.md` §4a.
    ///   The generic spelling is correct on both.
    ///
    /// SwiftUI has no equivalent — its `LocalizedStringKey` is opaque, and a
    /// component is expected to hand it straight to a `Text`. A terminal UI
    /// needs the `String`: text is laid out in cells, so padding, truncating
    /// and column alignment all happen on the resolved text.
    public var localized: String {
        resolved(with: LocalizationService.shared)
    }

    /// Whether `character` is a C length modifier (`%ld`, `%zu`, …), which a
    /// translation may carry over and which carries no meaning here.
    ///
    /// - Note: A `switch` rather than `"hlLqzjt".contains(character)`. That
    ///   spelling **scans a `String`** — a fresh one per call, compared
    ///   grapheme by grapheme — and this runs per conversion of every
    ///   interpolated `Text`, on every frame.
    private static func isLengthModifier(_ character: Character) -> Bool {
        switch character {
        case "h", "l", "L", "q", "z", "j", "t": return true
        default: return false
        }
    }

    /// Whether `character` terminates a conversion — `%@` and the numeric
    /// forms a translator might reasonably write. A `switch` for the same
    /// reason as ``isLengthModifier(_:)``.
    private static func isConversion(_ character: Character) -> Bool {
        switch character {
        case "@", "d", "i", "u", "f", "g", "G", "e", "E", "x", "X", "o", "s": return true
        default: return false
        }
    }

    /// printf's `-` flag and the digits after it, read from `cursor` and
    /// leaving it past them. The digits are a position if a `$` follows and a
    /// width otherwise; that is the caller's call, which is why they come
    /// back as text.
    private static func scanFlagAndDigits(
        _ template: String, from cursor: inout String.Index
    ) -> (leftAligned: Bool, digits: String) {
        var leftAligned = false
        if cursor < template.endIndex, template[cursor] == "-" {
            leftAligned = true
            cursor = template.index(after: cursor)
        }
        var digits = ""
        while cursor < template.endIndex, template[cursor].isNumber {
            digits.append(template[cursor])
            cursor = template.index(after: cursor)
        }
        return (leftAligned, digits)
    }

    /// Replaces `%@` / `%N$@` (and the numeric conversions a translator might
    /// reasonably write) in `template` with `arguments`.
    ///
    /// Anything unrecognised is emitted verbatim, so a stray `%` in a
    /// translation degrades to itself rather than eating the character after
    /// it.
    static func substituting(_ arguments: [String], into template: String) -> String {
        var result = ""
        var next = 0
        var index = template.startIndex

        while index < template.endIndex {
            guard template[index] == "%" else {
                result.append(template[index])
                index = template.index(after: index)
                continue
            }
            var cursor = template.index(after: index)
            guard cursor < template.endIndex else {
                result.append("%")
                break
            }
            // `%%` is an escaped percent.
            if template[cursor] == "%" {
                result.append("%")
                index = template.index(after: cursor)
                continue
            }
            // An explicit position: `%2$@` takes the second argument, which is
            // how a translation reorders them.
            var position: Int?
            // A `-` before the digits is printf's left-align flag; with a
            // width it changes which side the padding lands on.
            let scanned = Self.scanFlagAndDigits(template, from: &cursor)
            var leftAligned = scanned.leftAligned
            let digits = scanned.digits
            var width: Int?
            if !digits.isEmpty, cursor < template.endIndex, template[cursor] == "$",
                !leftAligned
            {
                position = Int(digits)
                cursor = template.index(after: cursor)
                // printf permits the flags and width AFTER a position too —
                // `%2$3d`, `%1$-6@` — and a scan that stopped at the `$`
                // rejected the `3` as the conversion, emitted the `%` verbatim
                // and dropped the argument. The same scan, once more; the
                // digits here can only be a width.
                let after = Self.scanFlagAndDigits(template, from: &cursor)
                leftAligned = after.leftAligned
                width = Int(after.digits)
            } else if !digits.isEmpty {
                // Digits that were not a position are a WIDTH — `%3d`. The
                // cursor already sits past them; remember the width rather
                // than rewinding onto digits the conversion scan cannot cross
                // — which emitted `%3d` verbatim AND left the implicit
                // argument cursor unadvanced, shifting every later argument
                // into the wrong placeholder.
                width = Int(digits)
            }
            // A precision (`%.2f`): parsed past so the conversion is still
            // recognised; the argument arrives pre-formatted, so it is not
            // applied.
            if cursor < template.endIndex, template[cursor] == "." {
                cursor = template.index(after: cursor)
                while cursor < template.endIndex, template[cursor].isNumber {
                    cursor = template.index(after: cursor)
                }
            }
            // Length modifiers a translator may carry over from a C format.
            while cursor < template.endIndex, Self.isLengthModifier(template[cursor]) {
                cursor = template.index(after: cursor)
            }
            guard cursor < template.endIndex, Self.isConversion(template[cursor]) else {
                // Not a conversion at all: emit the `%` and carry on from the
                // character after it, so nothing is swallowed.
                result.append("%")
                index = template.index(after: index)
                continue
            }
            let argumentIndex = position.map { $0 - 1 } ?? next
            if argumentIndex >= 0, argumentIndex < arguments.count {
                var value = arguments[argumentIndex]
                // A width is a COLUMN count — every other padding site here
                // measures cells — so a CJK or emoji argument is padded by
                // what it occupies, not by its grapheme count.
                let cells = value.strippedLength
                if let width, cells < width {
                    let pad = String(repeating: " ", count: width - cells)
                    value = leftAligned ? value + pad : pad + value
                }
                result += value
            }
            // A positional reference does not advance the implicit cursor —
            // that is what lets a translation use %1$@ twice.
            if position == nil { next += 1 }
            index = template.index(after: cursor)
        }
        return result
    }
}

// MARK: - Literals and interpolation

extension LocalizedStringKey: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(key: stringInterpolation.key, arguments: stringInterpolation.arguments)
    }

    /// Builds the key and its arguments as the literal is written.
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 2)
            arguments.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            // A literal `%` has to be escaped, because the key it lands in is
            // printf-shaped: the interpolations around it are `%@`, and
            // `substituting(_:into:)` reads `%%` as one percent. Written
            // through unescaped, `"Save \(n)%\(unit)"` built the key
            // `%@%%@` — whose `%%` is an escaped percent and whose trailing
            // `@` is a stray literal — so the SECOND argument was silently
            // dropped and an `@` appeared in its place. The neighbouring
            // `"\(n)% done"` was fine, which is what kept this hidden: only a
            // percent immediately before an interpolation collides.
            key += literal.contains("%") ? literal.replacingOccurrences(of: "%", with: "%%") : literal
        }

        /// Interpolates any value, as `String(describing:)` would render it.
        public mutating func appendInterpolation(_ value: some Any) {
            key += "%@"
            arguments.append(String(describing: value))
        }

        /// Interpolates a value through a format style — the same eager
        /// formatting ``Text/init(_:format:)`` does.
        public mutating func appendInterpolation<F: FormatStyle>(
            _ value: F.FormatInput, format: F
        ) where F.FormatInput: Equatable, F.FormatOutput == String {
            key += "%@"
            arguments.append(format.format(value))
        }
    }
}
