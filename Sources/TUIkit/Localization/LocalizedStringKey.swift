//  🖥️ TUIKit — Terminal UI Kit for Swift
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
/// from anything magic: ``SwiftUICore/Text`` has one initializer taking a
/// `LocalizedStringKey` and another generic over `StringProtocol`, and Swift
/// prefers the concrete one for a literal. So a literal is a key; a `String`
/// you computed is content. ``SwiftUICore/Text/init(verbatim:)`` opts a literal
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
/// same way ``SwiftUICore/Text/init(_:format:)`` formats eagerly — so
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
            var digits = ""
            while cursor < template.endIndex, template[cursor].isNumber {
                digits.append(template[cursor])
                cursor = template.index(after: cursor)
            }
            if !digits.isEmpty, cursor < template.endIndex, template[cursor] == "$" {
                position = Int(digits)
                cursor = template.index(after: cursor)
            } else if !digits.isEmpty {
                // Digits that were not a position are a width — `%3d`. Rewind
                // and let the conversion scan see them.
                cursor = template.index(index, offsetBy: 1)
            }
            // Length modifiers a translator may carry over from a C format.
            while cursor < template.endIndex, "hlLqzjt".contains(template[cursor]) {
                cursor = template.index(after: cursor)
            }
            guard cursor < template.endIndex, "@diufgGeExXos".contains(template[cursor]) else {
                // Not a conversion at all: emit the `%` and carry on from the
                // character after it, so nothing is swallowed.
                result.append("%")
                index = template.index(after: index)
                continue
            }
            let argumentIndex = position.map { $0 - 1 } ?? next
            if argumentIndex >= 0, argumentIndex < arguments.count {
                result += arguments[argumentIndex]
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
            key += literal
        }

        /// Interpolates any value, as `String(describing:)` would render it.
        public mutating func appendInterpolation(_ value: some Any) {
            key += "%@"
            arguments.append(String(describing: value))
        }

        /// Interpolates a value through a format style — the same eager
        /// formatting ``SwiftUICore/Text/init(_:format:)`` does.
        public mutating func appendInterpolation<F: FormatStyle>(
            _ value: F.FormatInput, format: F
        ) where F.FormatInput: Equatable, F.FormatOutput == String {
            key += "%@"
            arguments.append(format.format(value))
        }
    }
}
