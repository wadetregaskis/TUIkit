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
        let wrapped = TextWrapping.wrapMeasured(content, width: maxWidth)

        // Reuse the per-line widths the wrap already computed instead of
        // re-`strippedLength`-ing every line.
        let naturalWidth = wrapped.widths.max() ?? 0
        // Never advertise a width wider than the wrap boundary: a word
        // longer than `maxWidth` is truncated at render time, so claiming
        // its full width would make the parent reserve unusable space.
        let width = maxWidth > 0 ? min(maxWidth, naturalWidth) : naturalWidth
        // A line limit caps the reported height so a parent allocates only
        // the rows the text is allowed to occupy.
        let height = min(wrapped.lines.count, style.lineLimit.map { max(1, $0) } ?? wrapped.lines.count)

        // Text is never flexible - it has a fixed size
        return ViewSize.fixed(width, height)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var effectiveStyle = style
        var effectiveCase: TextCase?

        // Resolve cascading attributes (container-level .bold()/.style(...) etc.)
        // and any chrome-role default (e.g. a Section header's bold+dim) beneath
        // this Text's own explicit attributes. A per-Text attribute always wins;
        // otherwise the cascade's resolved value (closest matching scope) wins
        // over the chrome-role default. The text's semantic colour role lets
        // `.semanticColor` entries match; its chrome role lets `.chrome(...)`
        // entries match.
        let cascade = context.environment.styleCascade
        let chromeRole = context.environment.chromeRole
        var cascaded = StyleAttributes()
        if !cascade.isEmpty || chromeRole != nil {
            var scopes: Set<StyleScope> = [.all, .text]
            if let role = Self.semanticRole(
                explicit: style.foregroundColor, environment: context.environment) {
                scopes.insert(.semanticColor(role))
            }
            if let chromeRole {
                scopes.insert(.chrome(chromeRole))
            }
            // A control's label (set by the control around its label subtree)
            // matches `.control(kind)` and, with a variant, `.controlVariant`.
            if let controlKind = context.environment.controlKind {
                scopes.insert(.control(controlKind))
                if let variant = context.environment.controlVariant {
                    scopes.insert(.controlVariant(controlKind, variant))
                }
            }
            let base = chromeRole?.defaultTextAttributes ?? StyleAttributes()
            cascaded = cascade.resolve(for: scopes).merged(over: base)
            effectiveStyle.isBold = effectiveStyle.isBold || (cascaded.bold ?? false)
            effectiveStyle.isItalic = effectiveStyle.isItalic || (cascaded.italic ?? false)
            effectiveStyle.isUnderlined = effectiveStyle.isUnderlined || (cascaded.underline ?? false)
            effectiveStyle.isStrikethrough =
                effectiveStyle.isStrikethrough || (cascaded.strikethrough ?? false)
            effectiveStyle.isDim = effectiveStyle.isDim || (cascaded.dim ?? false)
            effectiveCase = cascaded.textCase
        }

        // Foreground precedence: an explicit *concrete* colour on this Text wins;
        // an explicit *semantic* colour (a palette-role reference) may be remapped
        // by a same-role `.semanticColor(role)` cascade entry; otherwise a scoped
        // cascade colour > the broad `.foregroundStyle` environment value >
        // palette default fills it. Background: explicit > cascade (Text has no
        // environment background — nil means "no background").
        if let explicit = style.foregroundColor {
            if case .semantic(let role) = explicit.value {
                effectiveStyle.foregroundColor =
                    cascade.resolve(for: [.semanticColor(role)]).foreground ?? explicit
            }
        } else {
            effectiveStyle.foregroundColor =
                cascaded.foreground
                ?? context.environment.foregroundStyle
                ?? context.environment.palette.foreground
        }
        if effectiveStyle.backgroundColor == nil {
            effectiveStyle.backgroundColor = cascaded.background
        }

        let resolvedStyle = effectiveStyle.resolved(with: context.environment.palette)

        // Word-wrap text to fit available width.
        let maxWidth = context.availableWidth
        let mode = style.truncationMode
        let atWordBoundary = style.truncatesAtWordBoundary
        // Lay the (cased) content into the available width and height: wrap on
        // word boundaries, honour an explicit line limit, and clip an over-long
        // run with an ellipsis. Shared with multi-line Table cells via
        // `TextWrapping` so text lays out the same way wherever it's shown.
        let lineLimit = style.lineLimit.map { max(1, $0) }
        let maxHeight = min(context.availableHeight, lineLimit ?? context.availableHeight)
        let wrapped = TextWrapping.fitMeasured(
            Self.applyingCase(effectiveCase, to: content),
            width: maxWidth, maxLines: maxHeight, mode: mode, atWordBoundary: atWordBoundary)

        let knownWidth = wrapped.widths.max() ?? 0

        // `multilineTextAlignment`: for `.center` / `.trailing` over more than
        // one line, pad each line into the block's own width (the widest line)
        // so shorter lines shift right or centre relative to it — SwiftUI's
        // line-to-line alignment. `.leading` (the default) and single-line text
        // keep the ragged, unpadded lines exactly as before (no snapshot churn;
        // the padding would be invisible trailing space anyway), and the block
        // width the measure pass reported is unchanged in every case.
        let alignment = context.environment.multilineTextAlignment
        let plainLines: [String]
        let lineWidths: [Int]
        if alignment != .leading, wrapped.lines.count > 1, knownWidth > 0 {
            var aligned: [String] = []
            aligned.reserveCapacity(wrapped.lines.count)
            for (line, lineWidth) in zip(wrapped.lines, wrapped.widths) {
                let leadingPad = alignment.leadingPad(lineWidth: lineWidth, blockWidth: knownWidth)
                let trailingPad = max(0, knownWidth - lineWidth - leadingPad)
                aligned.append(
                    String(repeating: " ", count: leadingPad) + line
                        + String(repeating: " ", count: trailingPad))
            }
            plainLines = aligned
            lineWidths = Array(repeating: knownWidth, count: aligned.count)
        } else {
            plainLines = wrapped.lines
            lineWidths = wrapped.widths
        }

        // Apply styling to each line. ANSI escapes occupy zero visible cells, so
        // the styled lines have exactly the same per-line widths as the plain
        // (possibly alignment-padded) lines — carry those widths (and the known
        // max width) into the buffer so neither this construction nor a parent
        // aligning the column re-`strippedLength`s the (now ANSI-laden) lines.
        let styledLines = plainLines.map { ANSIRenderer.render($0, with: resolvedStyle) }

        return FrameBuffer(lines: styledLines, width: knownWidth, lineWidths: lineWidths)
    }

    /// The palette role this text draws with, used to match `.semanticColor`
    /// style-cascade entries. A `.semantic(...)` foreground (explicit on the
    /// Text, or inherited via `.foregroundStyle`) reports its role; an explicit
    /// concrete colour reports `nil` (no role); no foreground at all reports
    /// `.foreground` (the palette default this text will use).
    private static func semanticRole(
        explicit: Color?, environment: EnvironmentValues
    ) -> SemanticColor? {
        guard let color = explicit ?? environment.foregroundStyle else { return .foreground }
        if case .semantic(let role) = color.value { return role }
        return nil
    }

    /// Applies a `TextCase` transform, or returns the string unchanged for `nil`.
    private static func applyingCase(_ textCase: TextCase?, to string: String) -> String {
        switch textCase {
        case .uppercase: return string.uppercased()
        case .lowercase: return string.lowercased()
        case nil: return string
        }
    }
}
