//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Font.swift
//
//  Semantic font styles — `.font(.headline)`, `.font(.caption)` — on a medium
//  with exactly one typeface at exactly one size.
//
//  A terminal cannot make text bigger, so nothing here changes a glyph or a
//  width; what a semantic style selects is INTENSITY. Eleven SwiftUI styles
//  collapse onto the three tiers a cell grid can actually distinguish — bold,
//  plain, faint — so several styles share a rendering. That is the point: the
//  value of `.font(.headline)` in portable source is that it says *this is a
//  heading*, and TUIkit can honour the intent even where it cannot honour the
//  metrics.
//
//  The mapping is a DEFAULT, not a rule. It forms the baseline that the style
//  cascade resolves over, and each style is addressable as a scope, so a theme
//  or an app can redefine any of them:
//
//      .style(.font(.headline)) { $0.underline = true }
//
//  ⚠️ `Font.TextStyle` is not TUIkit's ``TextStyle`` — that one is the concrete
//  bundle of resolved attributes `ANSIRenderer` draws with. Nested here, the
//  short spelling inside `Font` always means the semantic style.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Font

/// A semantic text style — mirrors SwiftUI's `Font`.
///
/// A terminal draws every cell in one typeface at one size, so the axes SwiftUI
/// varies (family, point size, design, width) have nowhere to go. What survives
/// is the *role*: `.headline` means emphatic, `.caption` means subordinate. Both
/// are expressible, and both are what the surrounding source usually meant.
///
/// ```swift
/// VStack(alignment: .leading) {
///     Text("Deployment failed").font(.headline)
///     Text("3 of 12 replicas unhealthy").font(.body)
///     Text("2 minutes ago").font(.caption)
/// }
/// ```
///
/// Because nothing here changes a glyph or a cell count, applying a font cannot
/// reflow the layout around it.
public struct Font: Sendable, Hashable {

    /// A semantic role for text — mirrors SwiftUI's `Font.TextStyle`.
    ///
    /// The eleven cases are carried in full so portable source compiles
    /// unchanged, even though a terminal can only draw three of them apart.
    public enum TextStyle: Sendable, Hashable, CaseIterable, Codable {
        case largeTitle
        case title
        case title2
        case title3
        case headline
        case subheadline
        case body
        case callout
        case footnote
        case caption
        case caption2
    }

    /// A font weight — mirrors SwiftUI's `Font.Weight`.
    ///
    /// The same type as the top-level ``FontWeight``, under SwiftUI's spelling.
    public typealias Weight = FontWeight

    /// The semantic role, which is what a terminal can act on.
    let textStyle: TextStyle

    /// An explicit weight override, or `nil` to use the style's own.
    let weight: Weight?

    /// An explicit italic setting, or `nil` to inherit.
    let isItalic: Bool?

    private init(_ textStyle: TextStyle, weight: Weight? = nil, isItalic: Bool? = nil) {
        self.textStyle = textStyle
        self.weight = weight
        self.isItalic = isItalic
    }

    // MARK: Built-in styles

    /// The largest title style. Renders bold.
    public static let largeTitle = Self(.largeTitle)
    /// A title style. Renders bold.
    public static let title = Self(.title)
    /// A secondary title style. Renders bold.
    public static let title2 = Self(.title2)
    /// A tertiary title style. Renders bold.
    public static let title3 = Self(.title3)
    /// A heading. Renders bold.
    public static let headline = Self(.headline)
    /// A subheading. Renders at normal intensity.
    public static let subheadline = Self(.subheadline)
    /// Body text. Renders at normal intensity — the default appearance.
    public static let body = Self(.body)
    /// A callout. Renders at normal intensity.
    public static let callout = Self(.callout)
    /// A footnote. Renders faint.
    public static let footnote = Self(.footnote)
    /// A caption. Renders faint.
    public static let caption = Self(.caption)
    /// A secondary caption. Renders faint.
    public static let caption2 = Self(.caption2)

    // MARK: Weight

    /// Returns this font with the given weight — mirrors SwiftUI's
    /// `Font/weight(_:)`.
    ///
    /// The weight overrides the style's default intensity: heavier than regular
    /// renders bold, lighter renders faint (see ``FontWeight``). So
    /// `.font(.caption.weight(.bold))` is a bold caption, not a faint one.
    ///
    /// - Parameter weight: The weight to apply.
    /// - Returns: A copy of this font carrying `weight`.
    public func weight(_ weight: Weight) -> Self {
        Self(textStyle, weight: weight, isItalic: isItalic)
    }

    /// Returns this font at bold weight — mirrors SwiftUI's `Font/bold()`.
    ///
    /// Shorthand for ``weight(_:)`` with ``FontWeight/bold``.
    ///
    /// - Returns: A copy of this font rendered bold.
    public func bold() -> Self {
        weight(.bold)
    }

    /// Returns this font bold or explicitly not bold — mirrors SwiftUI's
    /// `Font/bold(_:)`.
    ///
    /// `false` is `.regular`, which actively clears the tier's own bold: a
    /// `.headline.bold(false)` is a headline at normal intensity.
    ///
    /// - Parameter isActive: Whether to render bold.
    /// - Returns: A copy of this font at the corresponding weight.
    public func bold(_ isActive: Bool) -> Self {
        weight(isActive ? .bold : .regular)
    }

    // MARK: Italic

    /// Returns this font italicised — mirrors SwiftUI's `Font/italic()`.
    ///
    /// Real on any terminal that implements SGR 3; those that do not typically
    /// substitute reverse video or ignore it, which is the emulator's choice
    /// rather than TUIkit's.
    ///
    /// - Returns: A copy of this font rendered italic.
    public func italic() -> Self {
        italic(true)
    }

    /// Returns this font italic or explicitly upright — mirrors SwiftUI's
    /// `Font/italic(_:)`.
    ///
    /// - Parameter isActive: Whether to render italic.
    /// - Returns: A copy of this font with the italic setting applied.
    public func italic(_ isActive: Bool) -> Self {
        Self(textStyle, weight: weight, isItalic: isActive)
    }

    // MARK: Guaranteed by the medium

    /// Returns this font monospaced — mirrors SwiftUI's `Font/monospaced()`.
    ///
    /// Already true of every cell in the grid; see
    /// `Sources/TUIkit/Modifiers/MediumGuaranteedModifiers.swift` for the
    /// guarantee and the tests that pin it. Returns the font unchanged.
    public func monospaced() -> Self {
        self
    }

    /// Returns this font monospaced — mirrors SwiftUI's `Font/monospaced(_:)`.
    ///
    /// - Parameter isActive: Ignored — a terminal cannot render
    ///   proportionally, so `false` cannot mean what it means in SwiftUI.
    public func monospaced(_ isActive: Bool) -> Self {
        self
    }

    /// Returns this font with tabular digits — mirrors SwiftUI's
    /// `Font/monospacedDigit()`.
    ///
    /// Already true: every digit is one cell. Returns the font unchanged.
    public func monospacedDigit() -> Self {
        self
    }

    // MARK: Resolution

    /// The baseline attributes this font contributes, before the style cascade
    /// resolves over it.
    ///
    /// Every field the tier decides is set *explicitly* rather than left `nil`,
    /// so asking for `.body` inside a faint subtree really does get you body
    /// text — the same reason ``FontWeight/styleAttributes`` sets both flags.
    var defaultAttributes: StyleAttributes {
        var attributes = textStyle.defaultAttributes
        if let weight {
            attributes = weight.styleAttributes.merged(over: attributes)
        }
        attributes.italic = isItalic
        return attributes
    }
}

// MARK: - The tiers

extension Font.TextStyle {
    /// The intensity tier this style renders at by default.
    ///
    /// Three tiers, because three is what a reader can tell apart in a grid of
    /// identical cells: **bold** for anything titular, plain for body-weight
    /// prose, **faint** for the small print. Deliberately no underline in the
    /// default mapping — in a terminal an underline reads as a link, which
    /// TUIkit's ``Link`` already spends it on. A theme can still add one.
    var defaultAttributes: StyleAttributes {
        switch self {
        case .largeTitle, .title, .title2, .title3, .headline:
            return StyleAttributes(bold: true, dim: false)
        case .subheadline, .body, .callout:
            return StyleAttributes(bold: false, dim: false)
        case .footnote, .caption, .caption2:
            return StyleAttributes(bold: false, dim: true)
        }
    }
}

// MARK: - Environment

/// Environment key carrying the semantic font for a subtree. `Text` reads it to
/// pick up the style's baseline attributes and to match `.font(style)` entries
/// in the style cascade.
private struct FontKey: EnvironmentKey {
    static let defaultValue: Font? = nil
}

extension EnvironmentValues {
    /// The semantic font applied to this subtree, or `nil` for the default
    /// appearance.
    public var font: Font? {
        get { self[FontKey.self] }
        set { self[FontKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the semantic font for text in this view — mirrors SwiftUI's
    /// `font(_:)`.
    ///
    /// ```swift
    /// Text("Deployment failed").font(.headline)
    /// Text("2 minutes ago").font(.caption)
    /// ```
    ///
    /// A terminal has one typeface at one size, so this selects **intensity**,
    /// not metrics: titular styles render bold, body styles plain, footnote and
    /// caption styles faint. It changes no glyph and no cell count, so applying
    /// a font cannot reflow the layout around it.
    ///
    /// The mapping is the *baseline*: an explicit attribute set anywhere in the
    /// cascade still wins, and each style is addressable as a
    /// ``StyleScope/font(_:)`` scope, so a theme can redefine one wholesale:
    ///
    /// ```swift
    /// ContentView()
    ///     .style(.font(.headline)) { $0.underline = true }
    /// ```
    ///
    /// - Parameter font: The font to apply, or `nil` to clear an inherited one.
    public func font(_ font: Font?) -> some View {
        environment(\.font, font)
    }
}
