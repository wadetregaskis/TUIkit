//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// A capitalisation transform — mirrors SwiftUI's `Text.Case`.
    ///
    /// The same type as the top-level ``TextCase``, under SwiftUI's spelling,
    /// so `.textCase(Text.Case.uppercase)` compiles as written. Same shape and
    /// same reason as ``Font/Weight``.
    public typealias Case = TextCase

    /// Where text is elided when it does not fit — mirrors SwiftUI's
    /// `Text.TruncationMode`.
    ///
    /// The same type as the top-level ``TruncationMode``, under SwiftUI's
    /// spelling.
    public typealias TruncationMode = TUIkit.TruncationMode

    // Declared so there is no padding between them for the per-pass memos'
    // value hash to skip (see the note on `TextStyle`'s properties): the two
    // 8-byte-aligned fields first, then `style`, whose 31 bytes end on a byte
    // boundary. Style between them left 7 undefined bytes before `runs`.

    /// The text to display.
    let content: String

    /// The runs this text is made of, or `nil` when it is a single fragment.
    ///
    /// `nil` is not an empty list: it is the overwhelmingly common case, and it
    /// takes the original render path untouched — no re-attribution, no extra
    /// allocation, byte-identical output. See ``Text/+(_:_:)``.
    var runs: [Run]?

    /// The style of the text (color, formatting, etc.).
    ///
    /// For a concatenated text this is the *base* beneath every run's own
    /// attributes — see ``Text/+(_:_:)``.
    var style: TextStyle

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
        self.content = key.localized
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

    // Each of these takes SwiftUI's `isActive`, and `false` is a STATEMENT
    // rather than a shrug: it beats a `.bold()` cascaded from an ancestor,
    // because the nearest answer wins. That is what ``TextStyle``'s tri-state
    // flags exist for — before them a `false` here was indistinguishable from
    // silence and the cascade won by default.
    //
    // `bold()` / `italic()` keep their no-argument spellings because SwiftUI
    // declares both, not merely a defaulted parameter.

    /// Makes the text bold.
    ///
    /// - Returns: A new text with bold formatting.
    public func bold() -> Text {
        bold(true)
    }

    /// Applies or removes bold — mirrors SwiftUI's `bold(_:)`.
    ///
    /// - Parameter isActive: Whether the text is bold. `false` states that it
    ///   is not, overriding a ``View/bold(_:)`` cascaded from an ancestor.
    /// - Returns: A new text with the bold setting applied.
    public func bold(_ isActive: Bool) -> Text {
        var copy = self
        copy.style.isBold = isActive
        return copy
    }

    /// Makes the text italic.
    ///
    /// - Returns: A new text with italic formatting.
    public func italic() -> Text {
        italic(true)
    }

    /// Applies or removes italics — mirrors SwiftUI's `italic(_:)`.
    ///
    /// - Parameter isActive: Whether the text is italic. `false` overrides an
    ///   ancestor's ``View/italic(_:)``.
    /// - Returns: A new text with the italic setting applied.
    public func italic(_ isActive: Bool) -> Text {
        var copy = self
        copy.style.isItalic = isActive
        return copy
    }

    /// Applies or removes an underline — mirrors SwiftUI's `underline(_:…)`.
    ///
    /// SwiftUI's `color:` and `pattern:` arguments are absent: a terminal draws
    /// one underline, in the text's own colour, and has no dashed or dotted
    /// variants to choose between. Omitting them makes
    /// `underline(true, color: .red)` fail to compile rather than compile and
    /// quietly ignore half of what it asked for.
    ///
    /// - Parameter isActive: Whether the text is underlined. `false` overrides
    ///   an ancestor's ``View/underline(_:)``.
    /// - Returns: A new text with the underline setting applied.
    public func underline(_ isActive: Bool = true) -> Text {
        var copy = self
        copy.style.isUnderlined = isActive
        return copy
    }

    /// Applies or removes a strikethrough — mirrors SwiftUI's
    /// `strikethrough(_:…)`, without the `color:`/`pattern:` arguments for the
    /// reason given on ``underline(_:)``.
    ///
    /// - Parameter isActive: Whether the text is struck through. `false`
    ///   overrides an ancestor's ``View/strikethrough(_:)``.
    /// - Returns: A new text with the strikethrough setting applied.
    public func strikethrough(_ isActive: Bool = true) -> Text {
        var copy = self
        copy.style.isStrikethrough = isActive
        return copy
    }

    /// Dims the text (reduced intensity).
    ///
    /// TUIkit-only — SwiftUI has no faint attribute — but it takes the
    /// parameter its four neighbours do, because being the one emphasis a
    /// `Text` could not turn off would read as an oversight rather than a
    /// decision. `.dim(false)` declines a dim arriving through the style
    /// cascade (`.style(.text) { $0.dim = true }`).
    ///
    /// - Important: It cannot decline ``View/dimmed()``. That modifier is a
    ///   buffer post-processor — it rewrites the rendered lines rather than
    ///   contributing to the cascade — so by the time it acts, this `Text` has
    ///   already had its say. The asymmetry is `dimmed()`'s, not this
    ///   parameter's.
    ///
    /// - Parameter isActive: Whether the text is dimmed.
    /// - Returns: A new text with the dim setting applied.
    public func dim(_ isActive: Bool = true) -> Text {
        var copy = self
        copy.style.isDim = isActive
        return copy
    }

    /// Sets the semantic font for this text — mirrors SwiftUI's `font(_:)`.
    ///
    /// The `Text`-level spelling of ``View/font(_:)``, meaning the same thing: a
    /// terminal has one typeface at one size, so a font selects **intensity**
    /// rather than metrics (see ``Font``). What it adds is *survival through
    /// concatenation* — a fragment carries its font into the joined text, so
    /// both halves of
    ///
    /// ```swift
    /// Text(name) + Text(" edited just now").font(.caption)
    /// ```
    ///
    /// render as what they are. A container's `.font(_:)` cannot do that: it
    /// reaches the whole subtree, and a concatenation is one view.
    ///
    /// - Parameter font: The font to use, or `nil` for the default appearance —
    ///   which, inside a `.font(...)` subtree, is how this one text opts out.
    /// - Returns: A new text with the font applied.
    public func font(_ font: Font?) -> Text {
        var copy = self
        copy.style.font = .some(font)
        return copy
    }

    /// Sets this text's weight — mirrors SwiftUI's `fontWeight(_:)`.
    ///
    /// A terminal has three weights rather than nine, so they map the way
    /// ``FontWeight`` describes: heavier than regular renders bold, lighter
    /// renders faint, and `.regular` renders neither — *actively*, so it clears
    /// a bold arriving from anywhere else, a font's own tier included.
    ///
    /// Because a font contributes a baseline and this states an attribute, the
    /// two compose in either order: `.font(.caption).fontWeight(.bold)` and
    /// `.fontWeight(.bold).font(.caption)` are both a bold caption.
    ///
    /// - Parameter weight: The weight to apply, or `nil` to leave the inherited
    ///   weight alone — SwiftUI's meaning for `nil` here, and
    ///   ``View/fontWeight(_:)``'s.
    /// - Returns: A new text at the corresponding intensity.
    public func fontWeight(_ weight: FontWeight?) -> Text {
        guard let attributes = weight?.styleAttributes else { return self }
        var copy = self
        copy.style.isBold = attributes.bold
        copy.style.isDim = attributes.dim
        return copy
    }

    /// Renders with a monospaced font — mirrors SwiftUI's `monospaced(_:)`.
    ///
    /// Already true of every glyph in a character grid; see
    /// `MediumGuaranteedModifiers.swift` for the guarantee and the tests that
    /// pin it. Returns the text unchanged.
    ///
    /// Safe to add alongside ``View/monospaced(_:)``: both spellings are the
    /// identity, so which one a call binds to cannot change what it does. (The
    /// emphasis toggles above needed more than that — see ``bold(_:)`` — but
    /// they have it now.)
    ///
    /// - Parameter isActive: Ignored — a terminal cannot render
    ///   proportionally, so `false` cannot mean what it means in SwiftUI.
    public func monospaced(_ isActive: Bool = true) -> Text {
        self
    }

    /// Renders digits at uniform width — mirrors SwiftUI's
    /// `monospacedDigit()`.
    ///
    /// Already true: every digit is one cell, which is why a percentage
    /// read-out has never jittered. Returns the text unchanged.
    public func monospacedDigit() -> Text {
        self
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

/// The concrete, fully-resolved set of attributes a run of text draws with —
/// what `ANSIRenderer` turns into escape sequences.
///
/// **Internal on purpose.** This is the framework's own end-of-pipeline value,
/// not a knob: every flag here is a plain `Bool`, so it can say "bold" but not
/// "explicitly NOT bold". The type an app styles with is ``StyleAttributes``,
/// the *partial overlay* the style cascade carries, whose tri-state `Bool?`
/// lets a subtree turn an attribute on and a descendant turn it back off. It
/// was `public` by drift — nothing public ever accepted or returned one, so a
/// caller could construct a `TextStyle` and then had nowhere to put it.
///
/// Do not widen this back to `public` to expose an attribute; add the attribute
/// to ``StyleAttributes`` and let it cascade.
struct TextStyle: Sendable, Equatable {
    /// This style with both colours at full strength — what goes into the SGR
    /// bytes when a colour's alpha travels separately as an `OpacityRegion`.
    ///
    /// See `Color.opaqueSpelling`. The two halves are one claim, and the byte half
    /// is deliberately opaque so the compositor has a real colour to blend from.
    var opaqueColours: Self {
        var copy = self
        copy.foregroundColor = foregroundColor?.opaqueSpelling
        copy.backgroundColor = backgroundColor?.opaqueSpelling
        return copy
    }

    // The stored properties are declared widest alignment first, so the
    // struct has no padding between them: the per-pass memos key a view by its
    // bytes (`viewValueHash`), and a padding byte is whatever the memory held
    // before — two equal styles can differ there. Linux did, and a button's
    // caps missed the memo on every probe. `statedLineLimit` (8-byte aligned)
    // comes first; everything after it is byte-aligned.
    // `TextLayoutPaddingTests` pins it.
    //
    // And the optionals whose payload is several fields — the line limit, the
    // two colours, the font — are stored as enums of this module's own
    // (`TextStyleStatements.swift`), so every byte of a `Text` is always
    // written and the value hash reads it whole. As `Optional`s, a `nil` stored
    // by generic code writes only the field whose spare values spell it, and
    // the hash has to read each one's case first: four typed steps on every
    // measured `Text`.

    /// How many lines the text may occupy, or `nil` to inherit `\.lineLimit`
    /// from the environment.
    ///
    /// Optional for the same reason ``truncationMode`` is, and with one extra
    /// twist: the limit's own "no limit" answer is a *value*
    /// (``LineLimit/unlimited``), not the absence of one — otherwise
    /// `Text(x).lineLimit(nil)` inside a `.lineLimit(2)` subtree could not say
    /// "not me" and the inherited cap would be unresettable.
    var lineLimit: LineLimit? {
        get { statedLineLimit.value }
        set { statedLineLimit = StatedLineLimit(newValue) }
    }
    private var statedLineLimit = StatedLineLimit.unstated

    /// The foreground color of the text.
    var foregroundColor: Color? {
        get { statedForegroundColor.value }
        set { statedForegroundColor = StatedColor(newValue) }
    }
    private var statedForegroundColor = StatedColor.unstated

    /// The background color of the text.
    var backgroundColor: Color? {
        get { statedBackgroundColor.value }
        set { statedBackgroundColor = StatedColor(newValue) }
    }
    private var statedBackgroundColor = StatedColor.unstated

    // The five flags a STYLE CASCADE can also state are tri-state, and for the
    // reason ``StyleAttributes`` is: `nil` is "this `Text` never said", which a
    // plain `Bool` cannot tell apart from "this `Text` said no". Without the
    // distinction the merge below can only ever turn an attribute ON — so a
    // `Text` inside a `.bold()` subtree has no way to opt out, and
    // `Text.bold(false)` cannot be written at all.
    //
    // ``isBlink`` and ``isInverted`` stay plain: nothing cascades them (they
    // have no ``StyleAttributes`` counterpart — they are terminal attributes
    // SwiftUI has no concept of), so there is no second opinion for a stated
    // value to beat.

    /// Whether the text is bold, or `nil` if this `Text` never said.
    var isBold: Bool?

    /// Whether the text is italic, or `nil` if this `Text` never said.
    var isItalic: Bool?

    /// Whether the text is underlined, or `nil` if this `Text` never said.
    var isUnderlined: Bool?

    /// Whether the text is strikethrough, or `nil` if this `Text` never said.
    var isStrikethrough: Bool?

    /// Whether the text is dimmed, or `nil` if this `Text` never said.
    var isDim: Bool?

    /// The semantic font this text stated for itself: the outer `nil` means it
    /// never stated one, the inner `nil` that it stated *none*.
    ///
    /// Doubly optional because `\.font` is itself `Font?` — "no font" is a value
    /// that key can hold, so a `Text`'s statement is *a value for the key, if it
    /// made one*. Collapsing the two would make `Text(x).font(nil)`
    /// indistinguishable from silence, and an inherited `.font(.headline)` could
    /// not be escaped from: the hole the tri-state flags above close for
    /// emphasis, reopened in the one place a font can open it.
    var font: Font?? {
        get { statedFont.value }
        set { statedFont = StatedFont(newValue) }
    }
    private var statedFont = StatedFont.unstated

    /// Whether the text blinks.
    var isBlink: Bool = false

    /// Whether foreground and background colors are inverted.
    var isInverted: Bool = false

    /// How the text is shortened when it cannot fit its available space, or
    /// `nil` to inherit `\.truncationMode` from the environment.
    ///
    /// Optional so "this `Text` was told" and "nobody said" stay
    /// distinguishable: `View.truncationMode(_:)` cascades a default to a whole
    /// subtree, and a `Text` that set its own must still win inside it.
    var truncationMode: TruncationMode?

    /// Whether truncation cuts only at word boundaries rather than at any
    /// character position.
    var truncatesAtWordBoundary: Bool = false

    /// Creates a default TextStyle with no formatting.
    init() {}
}

// MARK: - Palette resolution

extension TextStyle {
    /// Resolves any semantic colors in this style against the given palette.
    ///
    /// Non-semantic colors are left unchanged. Call this before passing
    /// the style to `ANSIRenderer`.
    ///
    /// - Parameter palette: The palette to resolve semantic colors against.
    /// - Returns: A copy with all colors resolved to concrete values.
    func resolved(with palette: any Palette) -> TextStyle {
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
    ///
    /// The font is a parameter rather than another environment read because a
    /// fragment of a concatenation can bring its own, and it decides two things
    /// at once: the baseline attributes below, and which `.font(_:)` scope
    /// entries match. Neither can be borrowed from the enclosing text.
    func cascadedAttributes(context: RenderContext, font: Font?) -> StyleAttributes {
        let cascade = context.environment.styleCascade
        let chromeRole = context.environment.chromeRole
        guard !cascade.isEmpty || chromeRole != nil || font != nil else {
            return StyleAttributes()
        }

        var scopes: Set<StyleScope> = [.all, .text]
        if let font {
            scopes.insert(.font(font.textStyle))
        }
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
        var base = chromeRole?.defaultTextAttributes ?? StyleAttributes()
        // `.headerProminence(_:)` adjusts the BASELINE, so an explicit style
        // cascaded over it still wins — the prominence says how loud a header
        // is by default, not what an app may not override.
        if chromeRole == .sectionHeader {
            base = context.environment.headerProminence.headerAttributes(over: base)
        }
        // A semantic font is likewise a BASELINE — `.font(.headline)` says what
        // a heading looks like when nobody said otherwise. It sits above the
        // chrome default (asking for `.caption` on a section header should get
        // you a caption) and below the cascade, so both a theme's
        // `.style(.font(.headline))` and a plain `.bold(false)` still win.
        if let font {
            base = font.defaultAttributes.merged(over: base)
        }
        return cascade.resolve(for: scopes).merged(over: base)
    }

    /// The font in effect for a set of stated attributes: what they state if
    /// they stated anything, otherwise the subtree's `\.font`.
    ///
    /// One accessor for both passes, because a font can reach
    /// ``StyleAttributes/textCase`` through a `.font(_:)`-scoped cascade entry —
    /// and a case that changes width (ß → SS) measured against a different font
    /// than it is drawn with reserves the wrong number of cells.
    private func resolvedFont(stating stated: Font??, context: RenderContext) -> Font? {
        stated ?? context.environment.font
    }

    /// `own` with the cascade's answers filling in every emphasis it did not
    /// state.
    ///
    /// The NEAREST statement wins, which is SwiftUI's rule and what
    /// ``TextStyle``'s tri-state flags exist for. It used to be an `||` — an
    /// attribute any layer could turn on and none could turn off — which is why
    /// nothing could opt out of an inherited `.bold()`.
    ///
    /// Shared with any fragment of a concatenation that brought its own font,
    /// since such a fragment resolves its own cascade and must fold the result
    /// in the same way.
    private func applyingCascadedEmphasis(
        to own: TextStyle, _ cascaded: StyleAttributes, context: RenderContext
    ) -> TextStyle {
        var result = own
        result.isBold = own.isBold ?? cascaded.bold
        result.isItalic = own.isItalic ?? cascaded.italic
        result.isUnderlined = own.isUnderlined ?? cascaded.underline
        result.isStrikethrough = own.isStrikethrough ?? cascaded.strikethrough
        result.isDim = own.isDim ?? cascaded.dim
        // Redaction is the system speaking, not a style: `.invalidated` says the
        // content is STALE, not absent — so it is shown and dimmed rather than
        // replaced with a skeleton, even where the text asked not to be dimmed.
        // An out-of-date figure is still worth reading, which is the whole point
        // of the distinction from `.placeholder`. The one place an OR is still
        // right.
        if context.environment.redactionReasons.contains(.invalidated) {
            result.isDim = true
        }
        return result
    }

    /// This text's line cap in rows, or `nil` for none.
    ///
    /// One resolution for both passes: a limit set on this `Text` wins, a
    /// cascaded ``View/lineLimit(_:)`` fills in otherwise. Measure and render
    /// must agree — a divergence here reserves rows nothing draws into, or
    /// clips text the parent left no room for.
    private func resolvedLineLimit(context: RenderContext) -> Int? {
        resolvedLineLimitPolicy(context: context).rowCount
    }

    /// The whole resolved policy, cap and reservation together.
    ///
    /// Both walks read it through here for the same reason they read the cap
    /// through one accessor: a reservation the measure claimed and the render
    /// did not fill leaves blank rows the parent allocated and nothing draws
    /// into, and one the render padded but the measure did not report spills
    /// past the space it was granted.
    private func resolvedLineLimitPolicy(context: RenderContext) -> LineLimit {
        style.lineLimit ?? context.environment.lineLimit
    }

    /// Blank rows between wrapped lines, from ``View/lineSpacing(_:)``.
    ///
    /// Read through one accessor for the same reason as the line limit: the
    /// measure adds these rows to the height it reports, and the render both
    /// draws them and subtracts them from the lines it is allowed to lay out.
    /// If the two disagreed, spacing would either reserve rows nothing fills or
    /// push the last line past the space the parent granted.
    private func resolvedLineSpacing(context: RenderContext) -> Int {
        context.environment.lineSpacing
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Text has a fixed size based on its content.
        // If a width is proposed, we may word-wrap.
        let maxWidth = proposal.width ?? context.availableWidth
        // Measure the string the render will DRAW, not the one that was
        // written: `.textCase(.uppercase)` can change the width (ß → SS, ﬁ →
        // FI), and a measure of the untransformed text would reserve the wrong
        // number of cells for it.
        let font = resolvedFont(stating: style.font, context: context)
        let textCase = cascadedAttributes(context: context, font: font).effectiveTextCase
        let wrapped = TextWrapping.wrapMeasured(
            Self.displayString(content, textCase: textCase, context: context), width: maxWidth)

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
        let policy = resolvedLineLimitPolicy(context: context)
        var drawnLines = min(wrapped.lines.count, policy.rowCount ?? wrapped.lines.count)
        // …and a reservation is a FLOOR on the same number, so a text shorter
        // than its limit still asks its parent for the rows it will pad out to.
        if let reserved = policy.reservedLines { drawnLines = max(drawnLines, reserved) }
        // …and then the blank rows `.lineSpacing(_:)` interleaves. The limit
        // counts LINES, as in SwiftUI, so it is applied first and the spacing
        // expands what survives it.
        let height = LineSpacingRows.displayRows(
            forLines: drawnLines, spacing: resolvedLineSpacing(context: context))

        // Text is never flexible - it has a fixed size…
        // …and it is a NATURAL size: everything above reads the effective width
        // (`proposal.width ?? context.availableWidth`) and the environment, and
        // nothing reads the vertical budget — a text does not shrink because the
        // space it was offered is short, it overflows and the parent clips it.
        // So the per-pass memo may answer a query under any budget from this.
        return ViewSize.fixed(width, height).declaringNaturalSize()
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Resolve cascading attributes (container-level .bold()/.style(...) etc.)
        // and any chrome-role default (e.g. a Section header's bold+dim) beneath
        // this Text's own explicit attributes. A per-Text attribute always wins;
        // otherwise the cascade's resolved value (closest matching scope) wins
        // over the chrome-role default. The text's semantic colour role lets
        // `.semanticColor` entries match; its chrome role lets `.chrome(...)`
        // entries match.
        let cascade = context.environment.styleCascade
        let font = resolvedFont(stating: style.font, context: context)
        let cascaded = cascadedAttributes(context: context, font: font)
        var effectiveStyle = applyingCascadedEmphasis(to: style, cascaded, context: context)
        let effectiveCase = cascaded.effectiveTextCase

        // Foreground precedence: an explicit *concrete* colour on this Text wins;
        // an explicit *semantic* colour (a palette-role reference) may be remapped
        // by a same-role `.semanticColor(role)` cascade entry; otherwise a scoped
        // cascade colour > the broad `.foregroundStyle` environment value >
        // palette default fills it. Background: explicit > cascade (Text has no
        // environment background — nil means "no background").
        //
        // A gradient can only arrive by the environment route — the two nearer
        // sources name one colour each — and only when nothing nearer has
        // spoken. `effectiveStyle` still takes its representative, so
        // everything downstream that wants one colour (the measure pass, the
        // semantic-role lookup, an attributed run) has one.
        let ramp = Self.resolveForeground(
            into: &effectiveStyle, stated: style.foregroundColor, cascade: cascade,
            cascaded: cascaded, context: context)
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
        let spacing = resolvedLineSpacing(context: context)
        // The height budget is in ROWS, but the wrap counts LINES — and with
        // spacing those differ. Convert first, or a spaced text lays out as many
        // lines as there are rows and then overflows by the gaps between them.
        let linesThatFit = LineSpacingRows.lines(
            fittingRows: context.availableHeight, spacing: spacing)
        let maxHeight = min(linesThatFit, lineLimit ?? linesThatFit)
        let wrapped = TextWrapping.fitMeasured(
            Self.displayString(content, textCase: effectiveCase, context: context),
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
        // One list of alpha claims per LINE, in that line's own columns. Rowed
        // only once the line spacing has been interleaved, below — the two arms
        // that produce claims both work in line indices, and spacing shifts rows.
        var perLineClaims: [[OpacityRegion]] = []
        if let runs {
            let concatenated = concatenatedLines(
                plainLines, runs: runs, blockWidth: lineWidths.max() ?? 0,
                effectiveStyle: effectiveStyle, effectiveCase: effectiveCase,
                font: font, ramp: ramp, context: context)
            styledLines = concatenated.lines
            perLineClaims = concatenated.claims
        } else if let ramp, !context.isMeasuring {
            // The extent is this text's own BLOCK — measured against SwiftUI,
            // where a two-line `Text` under a horizontal gradient ends its
            // short first line partway along the ramp rather than at the far
            // end. A concatenation bands the same way, one fragment at a time
            // (above).
            let painted = PaintRenderer.styled(
                plainLines, blockWidth: lineWidths.max() ?? 0, lineWidths: lineWidths,
                frame: context.gradientFrame, paint: ramp, style: resolvedStyle,
                depth: ColorDepth.current, cellAspect: context.environment.imageCellAspect)
            styledLines = painted.lines
            // A ramped ink used to claim NOTHING — for all four alpha shapes, not just
            // the per-cell one — because `styled` returned only bytes. §34.
            perLineClaims = painted.claims
        } else {
            // The OPAQUE spelling into the bytes; the alpha travels as a region
            // below. A translucent colour has no SGR spelling at all — the
            // terminal has no alpha channel — so the only honest answer is the
            // compositor's, blended against what is actually behind these cells.
            styledLines = plainLines.map {
                ANSIRenderer.render($0, with: resolvedStyle.opaqueColours)
            }
            perLineClaims = Self.uniformAlphaClaims(style: resolvedStyle, lineWidths: lineWidths)
        }

        // A reservation pads the block out to its full height with blank lines
        // — added here, before the spacing is interleaved, so the reserved rows
        // are spaced like the real ones and the height matches what the measure
        // reported. Capped at what the parent actually granted: squeezed into
        // fewer rows than were reserved, the text draws what fits rather than
        // spilling out of its box.
        var paddedLines = styledLines
        var paddedWidths = lineWidths
        if let reserved = resolvedLineLimitPolicy(context: context).reservedLines {
            let target = min(reserved, linesThatFit)
            while paddedLines.count < target {
                paddedLines.append("")
                paddedWidths.append(0)
                // Only when there is something to stay parallel WITH: an empty
                // `perLineClaims` means no claims at all, and padding it would
                // make it a ragged array of nothings instead.
                if !perLineClaims.isEmpty { perLineClaims.append([]) }
            }
        }

        // Interleave the spacing LAST, after styling: a blank row carries no
        // text, so it needs no ANSI run, and inserting it earlier would have the
        // run-attribution walk step over rows that are not part of the content.
        guard spacing > 0, paddedLines.count > 1 else {
            var buffer = FrameBuffer(
                lines: paddedLines, width: knownWidth, lineWidths: paddedWidths)
            buffer.opacityRegions += Self.rowed(perLineClaims, spacing: 0)
            return buffer
        }
        let spacedWidths = LineSpacingRows.interleaved(paddedWidths, spacing: spacing, blank: 0)
        var buffer = FrameBuffer(
            lines: LineSpacingRows.interleaved(paddedLines, spacing: spacing, blank: ""),
            width: knownWidth,
            lineWidths: spacedWidths)
        buffer.opacityRegions += Self.rowed(perLineClaims, spacing: spacing)
        return buffer
    }

    /// Puts `perLine` claims on the rows their lines ended up on.
    ///
    /// Through the same ``LineSpacingRows/interleaved(_:spacing:blank:)`` the
    /// lines and the widths go through, rather than by arithmetic on `spacing`:
    /// three parallel arrays that must agree about which row is which, and the one
    /// derived a different way is the one that drifts.
    private static func rowed(_ perLine: [[OpacityRegion]], spacing: Int) -> [OpacityRegion] {
        // EMPTY means "no claims anywhere", not "one empty list per line". The
        // distinction is the whole cost of this feature on a page with no
        // translucency: spelling the nothing case as `Array(repeating: [], count:)`
        // allocated an array per `Text` per frame and then interleaved and
        // flat-mapped it to arrive back at nothing, which measured as `fanout`
        // +4.3%, `textwall` +2.1% and four more scenarios slower with intervals
        // clear of zero. Every producer below returns `[]` for it.
        guard !perLine.isEmpty else { return [] }
        let spaced = LineSpacingRows.interleaved(perLine, spacing: spacing, blank: [])
        return spaced.enumerated().flatMap { row, claims in
            claims.map { claim in
                var region = claim
                region.offsetY = row
                return region
            }
        }
    }

    /// One claim per drawn line, for a text whose whole block shares one style.
    ///
    /// Per LINE rather than one rectangle over the block, because a wrapped text
    /// is ragged: a single rectangle would claim the blank cells past the end of
    /// every short line and fade whatever a sibling drew there. `Text` already
    /// computes exact per-line widths for the buffer, so the ragged shape costs
    /// nothing to describe.
    private static func uniformAlphaClaims(
        style: TextStyle, lineWidths: [Int]
    ) -> [[OpacityRegion]] {
        let ink = style.foregroundColor
        let field = style.backgroundColor
        // Asked once, of the STYLE, before the per-line walk — and `[]` rather
        // than a list of empties, see `rowed`.
        guard ink?.isOpaque == false || field?.isOpaque == false else { return [] }
        return lineWidths.map { width in
            OpacityRegion.claim(width: width, height: 1, ink: ink, field: field)
                .map { [$0] } ?? []
        }
    }

    /// One claim per FRAGMENT of a concatenation, in that line's own columns.
    ///
    /// A concatenation carries a style per fragment, which reads like the case
    /// that needs a claim finer than a rectangle — and does not. A fragment
    /// occupies a contiguous column range of one line, so a height-1 rectangle
    /// per fragment says exactly what is true. What genuinely cannot be a
    /// rectangle is a RAMP, where the colour and therefore the alpha change per
    /// cell along the row; that arm is still declined, above.
    ///
    /// Adjacent fragments claiming the same alphas are coalesced. A concatenation
    /// is usually a handful of fragments differing in WEIGHT rather than in
    /// translucency, so the common case collapses to the one region per line the
    /// uniform arm would have produced — and the resolver's per-cell lookup walks
    /// every region covering a row.
    ///
    /// Widths in `strippedLength`, not `count`: a fragment holding an emoji or
    /// CJK is wider in cells than in characters, and a start column off by one
    /// puts every later fragment's claim on the wrong cells.
    private static func fragmentAlphaClaims(
        _ fragments: [[(text: String, run: Int)]], styles: [TextStyle]
    ) -> [[OpacityRegion]] {
        // Nothing translucent anywhere: answered from the STYLES, which are a
        // handful, before touching the fragments. The walk below is a
        // `strippedLength` per fragment per line — a grapheme scan in the general
        // case — and every concatenated `Text` in an app would pay it every frame
        // to discover that all its colours are opaque, which is the answer for
        // essentially all of them.
        guard
            styles.contains(where: {
                $0.foregroundColor?.isOpaque == false || $0.backgroundColor?.isOpaque == false
            })
        else { return [] }  // `[]` rather than a list of empties — see `rowed`.
        return fragments.map { line in
            var claims: [OpacityRegion] = []
            var column = 0
            for fragment in line {
                let width = fragment.text.strippedLength
                defer { column += width }
                guard width > 0, styles.indices.contains(fragment.run) else { continue }
                let style = styles[fragment.run]
                claims.appendCoalescing(
                    OpacityRegion.claim(
                        offsetX: column, width: width, height: 1,
                        ink: style.foregroundColor, field: style.backgroundColor))
            }
            return claims
        }
    }

    /// The styled lines of a CONCATENATION: each fragment in its own run's
    /// style, with a spanning ramp banded across them.
    ///
    /// The wrap ran on the plain text (it must, or a break either side of a
    /// fragment boundary would be chosen blind), so this puts the per-fragment
    /// styling back by walking the same source the runs describe — see
    /// ``TextRunAttribution``.
    ///
    /// - Parameters:
    ///   - plainLines: The laid-out lines, unstyled.
    ///   - runs: The fragments this text was concatenated from.
    ///   - blockWidth: The widest line, for a ramp's own rectangle.
    ///   - effectiveStyle: This text's resolved attributes, cascade included.
    ///   - effectiveCase: The case transform, so the runs are matched against
    ///     the same source the wrap saw.
    ///   - font: This text's font, for deciding which fragments re-cascade.
    ///   - ramp: The gradient in force, when there is one.
    ///   - context: The render context.
    /// - Returns: One styled string per line.
    private func concatenatedLines(
        _ plainLines: [String], runs: [Text.Run], blockWidth: Int,
        effectiveStyle: TextStyle, effectiveCase: Text.Case?, font: Font?, ramp: Paint?,
        context: RenderContext
    ) -> (lines: [String], claims: [[OpacityRegion]]) {
        let runTexts = runs.map {
            Self.displayString($0.text, textCase: effectiveCase, context: context)
        }
        var resolvedRunStyles: [TextStyle] = []
        resolvedRunStyles.reserveCapacity(runs.count)
        // Which fragments the ramp is entitled to colour: the ones that stated
        // no colour of their own and so took this text's, which under a ramp is
        // only the ramp's stand-in.
        var runTakesRamp: [Bool] = []
        runTakesRamp.reserveCapacity(runs.count)
        for run in runs {
            var runStyle: TextStyle
            if let stated = run.style.font, stated != font {
                // A fragment that brought its own font resolves its OWN cascade
                // — the font decides both the baseline intensity and which
                // `.font(_:)` scope entries match, neither of which can be
                // borrowed from the enclosing text. It starts from the explicit
                // attributes alone (this text's, with the fragment's over them)
                // so that what the cascade fills in is the fragment's answer and
                // not the text's.
                runStyle = applyingCascadedEmphasis(
                    to: run.style.merged(over: style),
                    cascadedAttributes(context: context, font: stated),
                    context: context)
                // The colours were resolved once, at text level (the
                // semantic-role remapping there reads this text's own
                // foreground); a fragment states its own or takes those.
                runTakesRamp.append(runStyle.foregroundColor == nil)
                runStyle.foregroundColor =
                    runStyle.foregroundColor ?? effectiveStyle.foregroundColor
                runStyle.backgroundColor =
                    runStyle.backgroundColor ?? effectiveStyle.backgroundColor
            } else {
                // The run's own attributes sit above the base this Text resolved
                // (its own style + the cascade); anything the run left unset
                // falls through to that.
                runTakesRamp.append(run.style.foregroundColor == nil)
                runStyle = run.style.merged(over: effectiveStyle)
            }
            resolvedRunStyles.append(runStyle.resolved(with: context.environment.palette))
        }

        var cursor = (run: 0, offset: 0)
        let fragments = plainLines.map { line in
            TextRunAttribution.fragments(of: line, runTexts: runTexts, cursor: &cursor)
        }
        guard let ramp, !context.isMeasuring else {
            // The OPAQUE spelling into the bytes and the alpha into a claim, as
            // the single-style arm does — a translucent colour has no SGR spelling
            // at all, so the compositor is the only place it can be answered.
            let opaque = resolvedRunStyles.map(\.opaqueColours)
            return (
                lines: fragments.map { line in
                    line.map { ANSIRenderer.render($0.text, with: opaque[$0.run]) }.joined()
                },
                claims: Self.fragmentAlphaClaims(fragments, styles: resolvedRunStyles)
            )
        }
        // The ramp bands ACROSS the fragments — the cell decides the colour, the
        // fragment decides everything else about it. A fragment that stated its
        // own colour keeps it.
        //
        // Claims come back beside the bytes now (§36.5). They used to be `[]`, on the
        // grounds that a ramp states an alpha per cell along the row and a rectangle
        // cannot say that — which was true of the arithmetic and not of the ramps: a
        // run of equal alpha is a rectangle, and `RampSampler.alphaClaims` states one
        // per run. The fragments' OWN colours were dropped here too, which was the
        // stranger half: the very same colour on an unramped concatenation was
        // claimed by `fragmentAlphaClaims` two branches up.
        let painted = PaintRenderer.styled(
            pieces: fragments.map { line in
                line.map {
                    StyledPiece(
                        text: $0.text, style: resolvedRunStyles[$0.run],
                        takesRamp: runTakesRamp[$0.run])
                }
            },
            blockWidth: blockWidth, frame: context.gradientFrame, paint: ramp,
            depth: ColorDepth.current, cellAspect: context.environment.imageCellAspect)
        return (lines: painted.lines, claims: painted.claims)
    }

    /// Fills in `style`'s foreground, and reports a gradient if that is what
    /// the environment supplied.
    ///
    /// Precedence: an explicit *concrete* colour on this Text wins; an explicit
    /// *semantic* colour may be remapped by a same-role `.semanticColor(role)`
    /// cascade entry; otherwise a scoped cascade colour > the broad
    /// `.foregroundStyle` environment value > the palette default.
    ///
    /// A ramp comes back separately rather than in the style, because a
    /// `TextStyle` names one colour and the whole point of a ramp is that it
    /// does not. The style still gets the ramp's representative so that
    /// anything asking for one colour has one.
    private static func resolveForeground(
        into style: inout TextStyle,
        stated: Color?,
        cascade: StyleCascade,
        cascaded: StyleAttributes,
        context: RenderContext
    ) -> Paint? {
        if let stated {
            if case .semantic(let role) = stated.value {
                style.foregroundColor =
                    cascade.resolve(for: [.semanticColor(role)]).foreground ?? stated
            }
            return nil
        }
        if let cascadedForeground = cascaded.foreground {
            style.foregroundColor = cascadedForeground
            return nil
        }
        guard let paint = context.environment.foregroundStyle else {
            style.foregroundColor = context.environment.palette.foreground
            return nil
        }
        style.foregroundColor = paint.representative
        return paint.solid == nil ? paint : nil
    }

    /// The palette role this text draws with, used to match `.semanticColor`
    /// style-cascade entries. A `.semantic(...)` foreground (explicit on the
    /// Text, or inherited via `.foregroundStyle`) reports its role; an explicit
    /// concrete colour reports `nil` (no role); no foreground at all reports
    /// `.foreground` (the palette default this text will use).
    private static func semanticRole(
        explicit: Color?, environment: EnvironmentValues
    ) -> SemanticColor? {
        if let explicit {
            if case .semantic(let role) = explicit.value { return role }
            return nil
        }
        guard let paint = environment.foregroundStyle else { return .foreground }
        // A ramp has no palette role: it is not one colour, so it cannot BE the
        // colour a `.semanticColor` cascade entry is talking about.
        guard let colour = paint.solid else { return nil }
        if case .semantic(let role) = colour.value { return role }
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

    /// The string this text will actually DRAW: cased, then redacted.
    ///
    /// Every site that needs the drawn string goes through here — the measure,
    /// the render, and the per-run walk of a concatenation — so a redaction can
    /// never change the width the measure reserved. Measuring the written
    /// string while drawing a transformed one is the measure/render parity bug
    /// class; `.textCase` was already routed this way for exactly that reason
    /// (ß → SS changes the width), and redaction joins it.
    private static func displayString(
        _ string: String, textCase: TextCase?, context: RenderContext
    ) -> String {
        context.environment.redactionReasons.redacting(applyingCase(textCase, to: string))
    }
}
