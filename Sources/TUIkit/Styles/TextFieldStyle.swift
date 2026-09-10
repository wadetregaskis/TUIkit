//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Text Field Style

/// A style that customises the appearance of text-entry fields — SwiftUI's
/// `TextFieldStyle`, applied with ``TUIkit/View/textFieldStyle(_:)``.
///
/// TUIkit ships the two SwiftUI names a terminal can tell apart:
/// - ``DefaultTextFieldStyle`` (`.automatic`): the field draws itself — a
///   coloured surface with half-block caps for its rounded ends, so it reads
///   as a box you can type into even when it is empty.
/// - ``PlainTextFieldStyle`` (`.plain`): no surface and no caps. The text sits
///   on whatever is behind it, which is what an editable value inline in a
///   sentence or a row wants.
///
/// ```swift
/// TextField("Name", text: $name)             // a box
/// TextField("Name", text: $name)
///     .textFieldStyle(.plain)                // just the text
/// ```
///
/// Everything else about the field is unchanged: the caret, the selection, the
/// horizontal scroll, click-to-caret, and the suggestion drop-down all behave
/// the same either way.
///
/// > Note: SwiftUI's `.roundedBorder` and `.squareBorder` are omitted. Both name
/// > a *shape of border* around the same field, and a terminal draws one
/// > rectangle of cells — offering the spellings would compile and then be
/// > indistinguishable, which is worse than not offering them. A field that
/// > wants a real frame composes one: `TextField(…).border()`.
///
/// A protocol rather than an enum, matching SwiftUI and ``ListStyle`` beside it,
/// so a `where Self ==` extension gives the leading-dot spelling. SwiftUI's own
/// requirement is underscored and effectively closed; this one is a plain
/// readable property, so a caller *can* conform — the styles here are simply
/// the two the framework draws.
public protocol TextFieldStyle: Sendable {
    /// Whether the field paints its own surface: the field-background colour
    /// behind the text, and the half-block caps at either end.
    ///
    /// `false` leaves the text on whatever is behind the field — deliberately
    /// no background at all rather than the palette's, so a plain field inside
    /// a tinted container picks up that container's tint the way ordinary text
    /// does.
    var drawsFieldSurface: Bool { get }
}

// MARK: - Default

/// The ordinary field: a coloured surface with half-block caps.
///
/// Matches SwiftUI's `.automatic`, and is what a `TextField` or `SecureField`
/// draws with no style applied.
public struct DefaultTextFieldStyle: TextFieldStyle {
    /// Creates the default text field style.
    public init() {}

    public var drawsFieldSurface: Bool {
        true
    }
}

// MARK: - Plain

/// A field with no surface and no caps — just its text, in place.
///
/// Matches SwiftUI's `.plain`.
public struct PlainTextFieldStyle: TextFieldStyle {
    /// Creates the plain text field style.
    public init() {}

    public var drawsFieldSurface: Bool {
        false
    }
}

// MARK: - Convenience

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    /// The default field appearance: a surface with capped ends.
    ///
    /// Usable with leading-dot syntax: `.textFieldStyle(.automatic)`.
    public static var automatic: DefaultTextFieldStyle {
        DefaultTextFieldStyle()
    }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    /// A field with no surface and no caps.
    ///
    /// Usable with leading-dot syntax: `.textFieldStyle(.plain)`.
    public static var plain: PlainTextFieldStyle {
        PlainTextFieldStyle()
    }
}

// MARK: - Environment

private struct TextFieldStyleKey: EnvironmentKey {
    static let defaultValue: any TextFieldStyle = DefaultTextFieldStyle()
}

extension EnvironmentValues {
    /// The style text-entry fields in this subtree draw themselves with.
    ///
    /// Internal, like every other style key here: the modifier is the API.
    var textFieldStyle: any TextFieldStyle {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for text fields within this view.
    ///
    /// - Parameter style: The style to apply — ``TextFieldStyle/automatic`` or
    ///   ``TextFieldStyle/plain``.
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        environment(\.textFieldStyle, style)
    }
}

// MARK: - Field chrome

/// The caps a styled field draws around its content, and what they cost.
///
/// One type because `TextField` and `SecureField` draw the same chrome from
/// two `_*Core` views: the arithmetic has to appear in four places (each
/// view's `sizeThatFits` and `renderToBuffer`), and four copies of "the caps
/// are two cells" is exactly how a measure and a render come to disagree.
@MainActor
struct FieldChrome {
    /// The cells the caps occupy in total — 2 with a surface, 0 without.
    let width: Int

    /// The leading cap, or `""` for a plain field.
    let open: String

    /// The trailing cap, or `""`.
    let close: String

    /// The field's surface colour, or `nil` when the style draws none.
    let surface: Color?

    /// The colour the caps are painted in, or `nil` for a style that draws none.
    ///
    /// Kept beside the bytes because the bytes state its OPAQUE spelling and the alpha
    /// has to reach the compositor separately — see ``claims(lineWidth:)``. It is the
    /// field surface, or the surface lerped toward the accent while hovered, so a
    /// palette that fades its page fades these too now that a derived surface carries
    /// the page's alpha (§39).
    let capColor: Color?

    /// Cells before the content starts — the leading cap, or none.
    ///
    /// Everything positioned against the content reads this rather than
    /// assuming 1: the caret's animated cells, the combo-box disclosure's click
    /// range, and the click-to-caret column mapping. A plain field's content
    /// starts at column 0, and each of those was an off-by-one waiting to
    /// happen.
    var leadingCells: Int { width / 2 }

    /// Cells after the content ends — the trailing cap, or none.
    ///
    /// The combo box's click target reaches through it: the cap is a single
    /// cell hard against the `▾`, and a click one cell wide of a two-cell
    /// target is a miss the pointer has no way to see coming.
    var trailingCells: Int { width - leadingCells }

    /// Builds the chrome for a style, tinting the caps toward the accent while
    /// hovered so the affordance reads as "clickable" without mimicking the
    /// focused look.
    /// - Parameter background: what the field is drawn ON — the page, or the
    ///   surface of a container that painted one (a `TabView`'s body). The
    ///   field's own surface is derived from it, so a field inside a tab does
    ///   not come out the same colour as the tab.
    init(
        style: any TextFieldStyle, palette: any Palette, isHovered: Bool,
        on background: Color? = nil
    ) {
        guard style.drawsFieldSurface else {
            self.width = 0
            self.open = ""
            self.close = ""
            self.surface = nil
            self.capColor = nil
            return
        }
        let surface =
            (background.map { palette.fieldBackground(on: $0) } ?? palette.fieldBackground)
            .resolve(with: palette)
        let capColor =
            isHovered
            ? Color.lerp(surface, palette.accent.resolve(with: palette), phase: 0.35)
            : surface
        self.width = 2
        self.open = ANSIRenderer.colorize(
            String(TerminalSymbols.openCap), foreground: capColor.opaqueSpelling)
        self.close = ANSIRenderer.colorize(
            String(TerminalSymbols.closeCap), foreground: capColor.opaqueSpelling)
        self.surface = surface
        self.capColor = capColor
    }

    /// What the caps owe on a field line `lineWidth` cells wide.
    ///
    /// Here rather than at the two call sites, because the trailing cap's column is
    /// `lineWidth - trailingCells` and this is the type that knows what
    /// ``trailingCells`` is — `TextField` and `SecureField` would each have re-derived
    /// it, which is how the two drift.
    ///
    /// The caps are half-block glyphs with no background of their own, so this is an
    /// INK claim. The field's surface is claimed by the content renderer, which is what
    /// paints it (§30).
    func claims(lineWidth: Int) -> [OpacityRegion] {
        guard let capColor, width > 0 else { return [] }
        return [
            OpacityRegion.claim(width: leadingCells, height: 1, ink: capColor),
            OpacityRegion.claim(
                offsetX: lineWidth - trailingCells, width: trailingCells, height: 1,
                ink: capColor),
        ].compactMap { $0 }
    }

    /// The chrome width for a style, without building the glyphs — what
    /// `sizeThatFits` needs, where there is no palette and nothing to draw.
    static func width(for style: any TextFieldStyle) -> Int {
        style.drawsFieldSurface ? 2 : 0
    }
}
