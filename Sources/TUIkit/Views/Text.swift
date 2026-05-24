//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Text.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A view that displays text in the terminal.
///
/// `Text` is one of the most fundamental views in TUIkit. It displays
/// a string in the terminal and supports various formatting options.
///
/// # Example
///
/// ```swift
/// Text("Hello, World!")
///
/// Text("Bold")
///     .bold()
///
/// Text("Colored")
///     .foregroundStyle(.red)
/// ```
public struct Text: View, Equatable {
    /// The text to display.
    let content: String

    /// The style of the text (color, formatting, etc.).
    var style: TextStyle

    /// Creates a text view with the specified string.
    ///
    /// - Parameter content: The text to display.
    public init(_ content: String) {
        self.content = content
        self.style = TextStyle()
    }

    /// Creates a text view with a verbatim string.
    ///
    /// - Parameter verbatim: The text to display verbatim.
    public init(verbatim: String) {
        self.content = verbatim
        self.style = TextStyle()
    }

    public var body: Never {
        fatalError("Text is a primitive view and renders directly")
    }
}

// MARK: - Text Modifiers

extension Text {
    /// Sets the text foreground style.
    ///
    /// - Parameter style: The desired foreground color.
    /// - Returns: A new text with the applied style.
    public func foregroundStyle(_ style: Color) -> Text {
        var copy = self
        copy.style.foregroundColor = style
        return copy
    }

    /// Makes the text bold.
    ///
    /// - Returns: A new text with bold formatting.
    public func bold() -> Text {
        var copy = self
        copy.style.isBold = true
        return copy
    }

    /// Makes the text italic.
    ///
    /// - Returns: A new text with italic formatting.
    public func italic() -> Text {
        var copy = self
        copy.style.isItalic = true
        return copy
    }

    /// Underlines the text.
    ///
    /// - Returns: A new text with underline formatting.
    public func underline() -> Text {
        var copy = self
        copy.style.isUnderlined = true
        return copy
    }

    /// Strikes through the text.
    ///
    /// - Returns: A new text with strikethrough formatting.
    public func strikethrough() -> Text {
        var copy = self
        copy.style.isStrikethrough = true
        return copy
    }

    /// Dims the text (reduced intensity).
    ///
    /// - Returns: A new text with dimmed appearance.
    public func dim() -> Text {
        var copy = self
        copy.style.isDim = true
        return copy
    }

    /// Makes the text blink (if supported by the terminal).
    ///
    /// - Returns: A new text with blink effect.
    public func blink() -> Text {
        var copy = self
        copy.style.isBlink = true
        return copy
    }

    /// Inverts foreground and background colors.
    ///
    /// - Returns: A new text with inverted colors.
    public func inverted() -> Text {
        var copy = self
        copy.style.isInverted = true
        return copy
    }

    /// Sets how the text is shortened when it cannot fit its available space.
    ///
    /// When the text is wider than the space it is given (or a word is
    /// longer than the wrap boundary), it is truncated and the truncation
    /// point is marked with an ellipsis (`…`). The default is `.tail`.
    ///
    /// ```swift
    /// Text("/very/long/path/to/file.txt")
    ///     .truncationMode(.head)   // "…/to/file.txt"
    /// ```
    ///
    /// - Parameter mode: Which part of the text to keep when truncating.
    /// - Returns: A new text with the truncation mode applied.
    public func truncationMode(_ mode: TruncationMode) -> Text {
        var copy = self
        copy.style.truncationMode = mode
        return copy
    }

    /// Sets whether truncation cuts only at word boundaries.
    ///
    /// By default an over-long line is cut at any character position
    /// (`"Hello Wor…"`). Enable this to pull the cut back to the nearest
    /// word boundary so a partial word is never left dangling
    /// (`"Hello…"`). A single word longer than the available width is
    /// still cut mid-word — there is no boundary to honour.
    ///
    /// ```swift
    /// Text("Hello World Foo")
    ///     .truncatesAtWordBoundary()
    /// ```
    ///
    /// - Parameter enabled: Whether to truncate only at word boundaries.
    /// - Returns: A new text with the word-boundary truncation setting.
    public func truncatesAtWordBoundary(_ enabled: Bool = true) -> Text {
        var copy = self
        copy.style.truncatesAtWordBoundary = enabled
        return copy
    }

    /// Sets the maximum number of lines the text may occupy.
    ///
    /// When the wrapped text would exceed the limit, the final visible line
    /// absorbs the remaining content and is truncated with an ellipsis.
    /// Passing `nil` removes the limit.
    ///
    /// ```swift
    /// Text(longParagraph)
    ///     .lineLimit(2)
    /// ```
    ///
    /// - Parameter limit: The maximum number of lines, or `nil` for no limit.
    /// - Returns: A new text with the line limit applied.
    public func lineLimit(_ limit: Int?) -> Text {
        var copy = self
        copy.style.lineLimit = limit
        return copy
    }
}

// MARK: - TextStyle

/// The style of a text view.
///
/// Contains all formatting options like color, bold, etc.
public struct TextStyle: Sendable, Equatable {
    /// The foreground color of the text.
    public var foregroundColor: Color?

    /// The background color of the text.
    public var backgroundColor: Color?

    /// Whether the text is bold.
    public var isBold: Bool = false

    /// Whether the text is italic.
    public var isItalic: Bool = false

    /// Whether the text is underlined.
    public var isUnderlined: Bool = false

    /// Whether the text is strikethrough.
    public var isStrikethrough: Bool = false

    /// Whether the text is dimmed.
    public var isDim: Bool = false

    /// Whether the text blinks.
    public var isBlink: Bool = false

    /// Whether foreground and background colors are inverted.
    public var isInverted: Bool = false

    /// How the text is shortened when it cannot fit its available space.
    public var truncationMode: TruncationMode = .tail

    /// Whether truncation cuts only at word boundaries rather than at any
    /// character position.
    public var truncatesAtWordBoundary: Bool = false

    /// The maximum number of lines the text may occupy, or `nil` for no limit.
    public var lineLimit: Int?

    /// Creates a default TextStyle with no formatting.
    public init() {}
}

// MARK: - Public API

extension TextStyle {
    /// Resolves any semantic colors in this style against the given palette.
    ///
    /// Non-semantic colors are left unchanged. Call this before passing
    /// the style to `ANSIRenderer`.
    ///
    /// - Parameter palette: The palette to resolve semantic colors against.
    /// - Returns: A copy with all colors resolved to concrete values.
    public func resolved(with palette: any Palette) -> TextStyle {
        var copy = self
        copy.foregroundColor = foregroundColor?.resolve(with: palette)
        copy.backgroundColor = backgroundColor?.resolve(with: palette)
        return copy
    }
}

// MARK: - Text Rendering

extension Text: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Text has a fixed size based on its content.
        // If a width is proposed, we may word-wrap.
        let maxWidth = proposal.width ?? context.availableWidth
        let wrappedLines = wordWrap(content, maxWidth: maxWidth)

        let naturalWidth = wrappedLines.map(\.strippedLength).max() ?? 0
        // Never advertise a width wider than the wrap boundary: a word
        // longer than `maxWidth` is truncated at render time, so claiming
        // its full width would make the parent reserve unusable space.
        let width = maxWidth > 0 ? min(maxWidth, naturalWidth) : naturalWidth
        // A line limit caps the reported height so a parent allocates only
        // the rows the text is allowed to occupy.
        let height = min(wrappedLines.count, style.lineLimit.map { max(1, $0) } ?? wrappedLines.count)

        // Text is never flexible - it has a fixed size
        return ViewSize.fixed(width, height)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var effectiveStyle = style

        // If no explicit foreground color is set on the Text itself,
        // inherit from the environment (set by .foregroundStyle() on parent views),
        // or fall back to the palette's default foreground color
        if effectiveStyle.foregroundColor == nil {
            effectiveStyle.foregroundColor =
                context.environment.foregroundStyle
                ?? context.environment.palette.foreground
        }

        let resolvedStyle = effectiveStyle.resolved(with: context.environment.palette)

        // Word-wrap text to fit available width.
        let maxWidth = context.availableWidth
        let mode = style.truncationMode
        let atWordBoundary = style.truncatesAtWordBoundary
        var lines = wordWrap(content, maxWidth: maxWidth)

        // Height constraint: if the wrapped text is taller than the space
        // it was given — or than an explicit line limit — keep the lines
        // that fit in full and let the final visible line absorb all the
        // remaining content, truncated with an ellipsis, so the loss is
        // shown rather than silently clipped.
        let lineLimit = style.lineLimit.map { max(1, $0) }
        let maxHeight = min(context.availableHeight, lineLimit ?? context.availableHeight)
        if maxHeight >= 1 && lines.count > maxHeight {
            let keptCount = max(0, maxHeight - 1)
            var kept = Array(lines.prefix(keptCount))
            let remainder = lines[keptCount...].joined(separator: " ")
            kept.append(
                remainder.truncatedToWidth(
                    maxWidth,
                    mode: mode,
                    atWordBoundary: atWordBoundary,
                    forceEllipsis: true
                )
            )
            lines = kept
        }

        // Width constraint: a word longer than the wrap boundary leaves a
        // line wider than `maxWidth`; truncate it with a visible ellipsis.
        let truncated = lines.map { line in
            line.truncatedToWidth(maxWidth, mode: mode, atWordBoundary: atWordBoundary)
        }

        // Apply styling to each line
        let styledLines = truncated.map { ANSIRenderer.render($0, with: resolvedStyle) }

        return FrameBuffer(lines: styledLines)
    }

    /// Wraps text into lines that fit a maximum terminal cell width.
    ///
    /// Explicit line breaks (`\n`, `\r\n`, `\r`) split the text into
    /// independent paragraphs, each wrapped on its own. This is essential:
    /// a raw newline left inside a buffer line would be interpreted by the
    /// terminal as a real row break, corrupting every row below it.
    ///
    /// Within a paragraph, wrapping happens on word boundaries (spaces).
    /// Words longer than `maxWidth` are placed on their own line without
    /// further splitting. Uses terminal-aware width measurement so wide
    /// characters (CJK, emoji) that occupy 2 cells are counted correctly.
    ///
    /// - Parameters:
    ///   - text: The text to wrap.
    ///   - maxWidth: Maximum terminal cells per line.
    /// - Returns: An array of wrapped lines (never empty).
    private func wordWrap(_ text: String, maxWidth: Int) -> [String] {
        // Split on explicit line breaks first so embedded newlines never
        // survive into a rendered buffer line.
        let paragraphs = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        )

        guard maxWidth > 0 else {
            return paragraphs.isEmpty ? [""] : paragraphs.map(String.init)
        }

        var lines: [String] = []
        for paragraph in paragraphs {
            lines.append(contentsOf: wrapParagraph(String(paragraph), maxWidth: maxWidth))
        }
        return lines.isEmpty ? [""] : lines
    }

    /// Wraps a single paragraph (with no embedded line breaks) on word
    /// boundaries so each returned line fits `maxWidth` terminal cells.
    ///
    /// - Parameters:
    ///   - text: A single paragraph of text.
    ///   - maxWidth: Maximum terminal cells per line.
    /// - Returns: An array of wrapped lines (never empty).
    private func wrapParagraph(_ text: String, maxWidth: Int) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var lines: [String] = []
        var currentLine = ""
        var currentLineWidth = 0

        for word in words {
            let wordStr = String(word)
            let wordWidth = wordStr.strippedLength
            if currentLine.isEmpty {
                currentLine = wordStr
                currentLineWidth = wordWidth
            } else if currentLineWidth + 1 + wordWidth <= maxWidth {
                currentLine += " " + wordStr
                currentLineWidth += 1 + wordWidth
            } else {
                lines.append(currentLine)
                currentLine = wordStr
                currentLineWidth = wordWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }
}
