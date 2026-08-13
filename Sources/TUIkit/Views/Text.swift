//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Text.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

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
    ///
    /// For a concatenated text this is the *base* beneath every run's own
    /// attributes — see ``Text/+(_:_:)``.
    var style: TextStyle

    /// The runs this text is made of, or `nil` when it is a single fragment.
    ///
    /// `nil` is not an empty list: it is the overwhelmingly common case, and it
    /// takes the original render path untouched — no re-attribution, no extra
    /// allocation, byte-identical output. See ``Text/+(_:_:)``.
    var runs: [Run]?

    /// Creates a text view displaying a localized string.
    ///
    /// A string **literal** binds here, so it is treated as a lookup key and
    /// resolved through ``LocalizationService`` — falling back to English and
    /// then to the literal itself, which is why adopting this changes nothing
    /// for an app that registers no translations. A `String` you computed
    /// binds to ``init(_:)-(S)`` instead and is displayed as-is. That split is
    /// SwiftUI's, and it is plain overload resolution: Swift prefers the
    /// concrete ``LocalizedStringKey`` over the generic one for a literal.
    ///
    /// ```swift
    /// Text("button.save")           // looked up
    /// Text("Rows: \(count)")        // key "Rows: %@", then substituted
    /// Text(verbatim: "button.save") // opted out — shown as written
    /// ```
    ///
    /// - Parameter key: The key to look up.
    public init(_ key: LocalizedStringKey) {
        self.content = key.resolved(with: LocalizationService.shared)
        self.style = TextStyle()
        self.runs = nil
    }

    /// Creates a text view with the specified string, displayed as-is.
    ///
    /// This is the overload a non-literal `String` binds to, so text you
    /// computed — a name, a file path, a value already localized — is never
    /// used as a lookup key.
    ///
    /// - Parameter content: The text to display.
    ///
    /// - Note: `@_disfavoredOverload` is what makes a *literal* choose
    ///   ``init(_:)-(LocalizedStringKey)`` instead of this one. Without it Swift
    ///   picks `String` — the default type for a string literal — and no literal
    ///   would ever be looked up. SwiftUI marks its own `StringProtocol`
    ///   initializer the same way, for the same reason.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) {
        self.content = String(content)
        self.style = TextStyle()
        self.runs = nil
    }

    /// Creates a text view with a verbatim string.
    ///
    /// - Parameter verbatim: The text to display verbatim.
    public init(verbatim: String) {
        self.content = verbatim
        self.style = TextStyle()
        self.runs = nil
    }

    /// Creates a text view that displays a value formatted with the given
    /// format style.
    ///
    /// ```swift
    /// Text(0.5, format: .percent)     // "50%"
    /// Text(1234, format: .number)     // "1,234"
    /// Text(price, format: .currency(code: "USD"))
    /// ```
    ///
    /// - Parameters:
    ///   - input: The underlying value to format.
    ///   - format: A format style that converts `input` into a `String`.
    ///
    /// - Note: SwiftUI re-resolves the format against the environment's
    ///   `\.locale` when the view renders. TUIkit formats eagerly here using the
    ///   format style's own locale (`.current` unless the style pins one), so
    ///   pin a locale on the style if you need deterministic output.
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F)
    where F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(format.format(input))
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
    /// point is marked with an ellipsis (`…`). The default is `.tail`, or
    /// whatever ``View/truncationMode(_:)`` cascaded from above — this one,
    /// being about this `Text` specifically, wins over that.
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
    /// Passing `nil` removes the limit — including one that
    /// ``View/lineLimit(_:)`` cascaded from above, since a limit stated here
    /// always wins for this one view.
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
        copy.style.lineLimit = LineLimit(limit)
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

    /// How the text is shortened when it cannot fit its available space, or
    /// `nil` to inherit `\.truncationMode` from the environment.
    ///
    /// Optional so "this `Text` was told" and "nobody said" stay
    /// distinguishable: `View.truncationMode(_:)` cascades a default to a whole
    /// subtree, and a `Text` that set its own must still win inside it.
    public var truncationMode: TruncationMode?

    /// Whether truncation cuts only at word boundaries rather than at any
    /// character position.
    public var truncatesAtWordBoundary: Bool = false

    /// How many lines the text may occupy, or `nil` to inherit `\.lineLimit`
    /// from the environment.
    ///
    /// Optional for the same reason ``truncationMode`` is, and with one extra
    /// twist: the limit's own "no limit" answer is a *value*
    /// (``LineLimit/unlimited``), not the absence of one — otherwise
    /// `Text(x).lineLimit(nil)` inside a `.lineLimit(2)` subtree could not say
    /// "not me" and the inherited cap would be unresettable.
    public var lineLimit: LineLimit?

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
    /// The style cascade's attributes for this `Text` — the scopes it matches
    /// (`.all`/`.text`, its semantic colour role, its chrome role, its control
    /// kind and variant) resolved over the chrome role's defaults.
    ///
    /// Used by BOTH passes. The render needs every attribute; the measure needs
    /// only ``StyleAttributes/textCase``, but it must get that from the same
    /// resolution — a case that changes width (ß → SS) measured from the
    /// untransformed string reserves the wrong number of cells.
    ///
    /// Returns empty attributes — every field `nil`, so every caller's `??`
    /// falls through — when nothing cascades and there is no chrome role, which
    /// is the common case and the reason this early-outs rather than resolving.
    func cascadedAttributes(context: RenderContext) -> StyleAttributes {
        let cascade = context.environment.styleCascade
        let chromeRole = context.environment.chromeRole
        guard !cascade.isEmpty || chromeRole != nil else { return StyleAttributes() }

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
        return cascade.resolve(for: scopes).merged(over: base)
    }

    /// This text's line cap in rows, or `nil` for none.
    ///
    /// One resolution for both passes: a limit set on this `Text` wins, a
    /// cascaded ``View/lineLimit(_:)`` fills in otherwise. Measure and render
    /// must agree — a divergence here reserves rows nothing draws into, or
    /// clips text the parent left no room for.
    private func resolvedLineLimit(context: RenderContext) -> Int? {
        (style.lineLimit ?? context.environment.lineLimit).rowCount
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Text has a fixed size based on its content.
        // If a width is proposed, we may word-wrap.
        let maxWidth = proposal.width ?? context.availableWidth
        // Measure the string the render will DRAW, not the one that was
        // written: `.textCase(.uppercase)` can change the width (ß → SS, ﬁ →
        // FI), and a measure of the untransformed text would reserve the wrong
        // number of cells for it.
        let wrapped = TextWrapping.wrapMeasured(
            Self.applyingCase(cascadedAttributes(context: context).textCase, to: content),
            width: maxWidth)

        // Reuse the per-line widths the wrap already computed instead of
        // re-`strippedLength`-ing every line.
        let naturalWidth = wrapped.widths.max() ?? 0
        // Never advertise a width wider than the wrap boundary: a word
        // longer than `maxWidth` is truncated at render time, so claiming
        // its full width would make the parent reserve unusable space. A
        // budget of zero (or less — a container squeezed past its chrome)
        // means the render draws nothing at all, so report nothing: claiming
        // the natural width there had the parent reserve space for text that
        // `truncatedToWidth(0)` then wiped.
        let width = maxWidth > 0 ? min(maxWidth, naturalWidth) : 0
        // A line limit caps the reported height so a parent allocates only
        // the rows the text is allowed to occupy. Resolved against the
        // environment exactly as the render does, or a cascaded
        // `.lineLimit(_:)` would reserve rows the render then refuses to draw.
        let height = min(wrapped.lines.count, resolvedLineLimit(context: context) ?? wrapped.lines.count)

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
        let cascaded = cascadedAttributes(context: context)
        effectiveStyle.isBold = effectiveStyle.isBold || (cascaded.bold ?? false)
        effectiveStyle.isItalic = effectiveStyle.isItalic || (cascaded.italic ?? false)
        effectiveStyle.isUnderlined = effectiveStyle.isUnderlined || (cascaded.underline ?? false)
        effectiveStyle.isStrikethrough =
            effectiveStyle.isStrikethrough || (cascaded.strikethrough ?? false)
        effectiveStyle.isDim = effectiveStyle.isDim || (cascaded.dim ?? false)
        effectiveCase = cascaded.textCase

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
        let mode = style.truncationMode ?? context.environment.truncationMode
        let atWordBoundary = style.truncatesAtWordBoundary
        // Lay the (cased) content into the available width and height: wrap on
        // word boundaries, honour an explicit line limit, and clip an over-long
        // run with an ellipsis. Shared with multi-line Table cells via
        // `TextWrapping` so text lays out the same way wherever it's shown.
        let lineLimit = resolvedLineLimit(context: context)
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
        let styledLines: [String]
        if let runs {
            // A concatenation: the wrap ran on the plain text (it must, or a
            // break either side of a fragment boundary would be chosen blind),
            // so put the per-fragment styling back by walking the same source
            // the runs describe. See `TextRunAttribution`.
            let runTexts = runs.map { Self.applyingCase(effectiveCase, to: $0.text) }
            var resolvedRunStyles: [TextStyle] = []
            resolvedRunStyles.reserveCapacity(runs.count)
            for run in runs {
                var runStyle = effectiveStyle
                // The run's own attributes sit above the base this Text
                // resolved (its own style + the cascade); anything the run
                // left unset falls through to that.
                runStyle = run.style.merged(over: runStyle)
                resolvedRunStyles.append(runStyle.resolved(with: context.environment.palette))
            }
            var cursor = (run: 0, offset: 0)
            styledLines = plainLines.map { line in
                TextRunAttribution.fragments(of: line, runTexts: runTexts, cursor: &cursor)
                    .map { ANSIRenderer.render($0.text, with: resolvedRunStyles[$0.run]) }
                    .joined()
            }
        } else {
            styledLines = plainLines.map { ANSIRenderer.render($0, with: resolvedStyle) }
        }

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
