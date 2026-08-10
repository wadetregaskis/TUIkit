//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Text+Concatenation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Runs

extension Text {
    /// One differently-styled fragment of a concatenated ``Text``.
    ///
    /// A run carries only the attributes that fragment set for **itself**. The
    /// enclosing `Text`'s own style is the base beneath it, and the environment
    /// cascade beneath that — so `(Text("a").bold() + Text("b")).italic()`
    /// makes both italic and only the first bold, which is what the same
    /// expression does in SwiftUI.
    struct Run: Equatable, Sendable {
        /// The fragment's text.
        let text: String

        /// Only what this fragment set explicitly.
        let style: TextStyle
    }
}

// MARK: - Concatenation

extension Text {
    /// Joins two texts into one, each keeping its own styling. Matches
    /// SwiftUI's `+`.
    ///
    /// ```swift
    /// Text("Name: ").bold() + Text(person.name) + Text(" (edited)").italic()
    /// ```
    ///
    /// The result is a single ``Text``, so it wraps, truncates, aligns and
    /// measures as one piece of text — the fragments are styling, not layout.
    /// A modifier applied to the result becomes the base beneath every
    /// fragment's own attributes:
    ///
    /// ```swift
    /// (Text("a").bold() + Text("b")).foregroundStyle(.red)   // both red, "a" bold
    /// ```
    ///
    /// - Parameters:
    ///   - lhs: The text on the left.
    ///   - rhs: The text to append.
    /// - Returns: One text carrying both fragments.
    public static func + (lhs: Text, rhs: Text) -> Text {
        // Flatten: a run list already holds fragment-level attributes, so a
        // side that has one contributes its runs rather than nesting. Its own
        // `style` is the base for those runs and is folded in here, because
        // the joined text's base belongs to whatever is applied AFTER the join.
        let leftRuns = lhs.runs?.map { $0.rebased(on: lhs.style) } ?? [
            Run(text: lhs.content, style: lhs.style)
        ]
        let rightRuns = rhs.runs?.map { $0.rebased(on: rhs.style) } ?? [
            Run(text: rhs.content, style: rhs.style)
        ]
        var joined = Text(verbatim: lhs.content + rhs.content)
        joined.runs = leftRuns + rightRuns
        return joined
    }
}

extension Text.Run {
    /// This run with `base` beneath it: the run's own attributes win, the
    /// base fills anything it left unset.
    func rebased(on base: TextStyle) -> Self {
        Self(text: text, style: style.merged(over: base))
    }
}

// MARK: - Style merging

extension TextStyle {
    /// This style with `base` beneath it — every attribute set here wins, and
    /// anything unset falls through.
    ///
    /// "Unset" means `nil` for the Optionals and `false` for the flags. A flag
    /// can therefore only ever be turned ON by a layer, never off, which is
    /// the same one-way rule the environment cascade already follows: `.bold()`
    /// on a container cannot be un-bolded by a child that simply didn't ask.
    func merged(over base: TextStyle) -> TextStyle {
        var result = self
        result.foregroundColor = foregroundColor ?? base.foregroundColor
        result.backgroundColor = backgroundColor ?? base.backgroundColor
        result.isBold = isBold || base.isBold
        result.isItalic = isItalic || base.isItalic
        result.isUnderlined = isUnderlined || base.isUnderlined
        result.isStrikethrough = isStrikethrough || base.isStrikethrough
        result.isDim = isDim || base.isDim
        result.isBlink = isBlink || base.isBlink
        result.isInverted = isInverted || base.isInverted
        result.truncationMode = truncationMode ?? base.truncationMode
        result.truncatesAtWordBoundary = truncatesAtWordBoundary || base.truncatesAtWordBoundary
        result.lineLimit = lineLimit ?? base.lineLimit
        return result
    }
}

// MARK: - Re-attributing wrapped lines

/// Maps the lines a wrap produced back onto the runs they came from.
///
/// Wrapping happens on the plain concatenation — it has to, or a break would be
/// chosen without seeing the words either side of a fragment boundary — so the
/// styling has to be put back afterwards. That is only possible because the
/// wrap **preserves every non-whitespace character, in order**: it chooses
/// break points and drops whitespace at them, and never reorders, substitutes
/// or invents. `TextConcatenationTests` pins that property over a few thousand
/// random strings and widths, so if the wrap ever stops holding to it, the
/// failure is a test rather than mis-coloured text.
enum TextRunAttribution {
    /// Splits `line` into `(text, runIndex)` fragments by walking a cursor
    /// through the source the runs describe.
    ///
    /// - Parameters:
    ///   - line: One wrapped (and possibly case-transformed) output line.
    ///   - runTexts: The runs' texts, in order, after the same transform.
    ///   - cursor: Where in the concatenated source this line starts; advanced
    ///     past what the line consumed.
    /// - Returns: The line in fragments, each tagged with its run.
    static func fragments(
        of line: String, runTexts: [String], cursor: inout (run: Int, offset: Int)
    ) -> [(text: String, run: Int)] {
        var result: [(text: String, run: Int)] = []
        var current = ""
        var currentRun = min(cursor.run, max(0, runTexts.count - 1))

        func flush() {
            if !current.isEmpty {
                result.append((current, currentRun))
                current = ""
            }
        }

        for character in line {
            // Skip source the wrap dropped: whitespace at a break point, and
            // whole runs that were entirely whitespace.
            while cursor.run < runTexts.count {
                let text = runTexts[cursor.run]
                let index = text.index(text.startIndex, offsetBy: cursor.offset)
                if index == text.endIndex {
                    cursor.run += 1
                    cursor.offset = 0
                    continue
                }
                if text[index] == character { break }
                guard text[index].isWhitespace else { break }
                cursor.offset += 1
            }
            guard cursor.run < runTexts.count else {
                // Past the end of the source: anything left is chrome the wrap
                // added (a truncation ellipsis), which belongs to the run that
                // was being cut.
                current.append(character)
                continue
            }
            let text = runTexts[cursor.run]
            let index = text.index(text.startIndex, offsetBy: cursor.offset)
            if index < text.endIndex, text[index] == character {
                if cursor.run != currentRun {
                    flush()
                    currentRun = cursor.run
                }
                current.append(character)
                cursor.offset += 1
                if cursor.offset == text.count {
                    cursor.run += 1
                    cursor.offset = 0
                }
            } else {
                // Not in the source at this position either: an inserted
                // ellipsis, or alignment padding. Keep it with the run in hand
                // rather than dropping it.
                current.append(character)
            }
        }
        flush()
        return result
    }
}
