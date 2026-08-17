//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SymbolVariants.swift
//
//  Choosing the filled / enclosed / struck-through cut of an SF Symbol, for a
//  whole subtree at once.
//
//  Cheap here in a way it is not on a raster platform: SF Symbols ships each
//  variant as its OWN NAME, and TUIkit resolves symbols by name. So a variant is
//  a name transform — "star" + `.circle.fill` is a lookup of "star.circle.fill"
//  — and the 8,466-name baked table already contains 2,454 `.fill` names, 647
//  `.circle.fill`, 271 `.square.fill` and 127 `.slash`.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - SymbolVariants

/// A variant of an SF Symbol — filled, enclosed in a shape, struck through — or
/// a combination.
///
/// Mirrors SwiftUI's `SymbolVariants`. Apply one with
/// ``View/symbolVariant(_:)``; it cascades, so a whole toolbar can switch to
/// filled symbols at once:
///
/// ```swift
/// VStack {
///     Label("Favourite", systemImage: "star")
///     Label("Inbox", systemImage: "tray")
/// }
/// .symbolVariant(.fill)          // star.fill, tray.fill
/// ```
///
/// Variants compose by chaining, and the chain reads the way the symbol is
/// named: `.circle.fill` is `"star.circle.fill"`.
///
/// - Note: When the requested variant does not exist — and many do not;
///   `"person.square.fill"` is absent while `"person.circle.fill"` is present —
///   the base symbol is drawn instead. Falling back beats rendering nothing,
///   and the caller keeps a glyph of the right width either way.
public struct SymbolVariants: Hashable, Sendable {
    /// The enclosing shape, if any. Exclusive: a symbol is in a circle or a
    /// square, never both, and asking for a second one replaces the first.
    private enum Enclosure: Hashable, Sendable {
        case unenclosed
        case circle
        case square
        case rectangle

        /// The name component SF Symbols uses for this shape.
        var nameComponent: String {
            switch self {
            case .unenclosed: ""
            case .circle: ".circle"
            case .square: ".square"
            case .rectangle: ".rectangle"
            }
        }
    }

    private var enclosure: Enclosure
    private var isFilled: Bool
    private var isSlashed: Bool

    private init(enclosure: Enclosure = .unenclosed, filled: Bool = false, slashed: Bool = false) {
        self.enclosure = enclosure
        self.isFilled = filled
        self.isSlashed = slashed
    }

    // MARK: Standard variants

    /// No variant — the symbol as named.
    public static let none = Self()

    /// Enclosed in a circle.
    public static let circle = Self(enclosure: .circle)

    /// Enclosed in a square.
    public static let square = Self(enclosure: .square)

    /// Enclosed in a rectangle.
    public static let rectangle = Self(enclosure: .rectangle)

    /// Filled rather than outlined.
    public static let fill = Self(filled: true)

    /// Struck through with a slash — the conventional "off" or "muted" cut.
    public static let slash = Self(slashed: true)

    // MARK: Chaining

    /// This variant, additionally enclosed in a circle.
    public var circle: Self { adding(enclosure: .circle) }

    /// This variant, additionally enclosed in a square.
    public var square: Self { adding(enclosure: .square) }

    /// This variant, additionally enclosed in a rectangle.
    public var rectangle: Self { adding(enclosure: .rectangle) }

    /// This variant, additionally filled.
    public var fill: Self {
        var copy = self
        copy.isFilled = true
        return copy
    }

    /// This variant, additionally struck through.
    public var slash: Self {
        var copy = self
        copy.isSlashed = true
        return copy
    }

    private func adding(enclosure: Enclosure) -> Self {
        var copy = self
        copy.enclosure = enclosure
        return copy
    }

    // MARK: Queries

    /// Whether this variant includes `other`.
    ///
    /// ``none`` is included by everything: it asks for nothing, so nothing can
    /// fail to provide it.
    ///
    /// - Parameter other: The variant to look for.
    /// - Returns: Whether every component of `other` is present here.
    public func contains(_ other: Self) -> Bool {
        if other.isFilled && !isFilled { return false }
        if other.isSlashed && !isSlashed { return false }
        if other.enclosure != .unenclosed && other.enclosure != enclosure { return false }
        return true
    }

    /// What this variant appends to a symbol's base name.
    ///
    /// The component order is SF Symbols' own, and was read off the shipped name
    /// table rather than assumed: `bell.slash.circle.fill` exists,
    /// `star.fill.circle` and `star.fill.slash` do not. So: slash, then the
    /// enclosing shape, then fill.
    var nameSuffix: String {
        (isSlashed ? ".slash" : "") + enclosure.nameComponent + (isFilled ? ".fill" : "")
    }
}

// MARK: - Environment

private struct SymbolVariantsKey: EnvironmentKey {
    static let defaultValue = SymbolVariants.none
}

extension EnvironmentValues {
    /// The SF Symbol variant applied to symbols in this environment. Set via
    /// ``View/symbolVariant(_:)``. Default: ``SymbolVariants/none``.
    public var symbolVariants: SymbolVariants {
        get { self[SymbolVariantsKey.self] }
        set { self[SymbolVariantsKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Applies a variant to the SF Symbols within this view.
    ///
    /// ```swift
    /// Label("Muted", systemImage: "speaker.wave.2")
    ///     .symbolVariant(.slash)          // speaker.wave.2.slash
    /// ```
    ///
    /// - Parameter variant: The variant to apply.
    /// - Returns: A view whose symbols use the variant.
    public func symbolVariant(_ variant: SymbolVariants) -> some View {
        environment(\.symbolVariants, variant)
    }
}

// MARK: - Icon

/// The icon half of ``Label/init(_:systemImage:)``, resolved at RENDER time.
///
/// Resolution has to be deferred: the variant lives in the environment, and an
/// initializer cannot read it. So the label stores the symbol's NAME and this
/// view turns it into a glyph while rendering, applying whatever variant is in
/// force at that point in the tree.
///
/// - Important: Framework infrastructure, public only because it appears in
///   ``Label``'s generic signature.
public struct _SymbolIcon: View {
    /// The base symbol name, without any variant suffix.
    let name: String

    @Environment(\.symbolVariants) private var variants

    public var body: some View {
        // Nothing at all where the symbol would not really draw. ``Label`` never
        // reaches this — it drops the icon *and* its gap up front — but
        // ``Image/init(systemName:)`` IS this view, with no title to fall back
        // to, so the check has to live where the glyph is emitted. Asked of the
        // base name, as ``Label`` asks it: the variant chooses the cut, not
        // whether there is a symbol.
        Text(verbatim: SFSymbol.canRender(named: name) ? Self.glyph(for: name, variants: variants) : "")
    }

    /// The glyph for `name` under `variants`, falling back to the base symbol.
    ///
    /// Many combinations simply do not exist — `person.circle.fill` ships,
    /// `person.square.fill` does not — so a miss is ordinary rather than
    /// exceptional, and drawing the unvaried symbol is much better than drawing
    /// nothing: the label keeps its icon, its width, and its meaning.
    static func glyph(for name: String, variants: SymbolVariants) -> String {
        let suffix = variants.nameSuffix
        if !suffix.isEmpty, let varied = SFSymbol.glyph(named: name + suffix) {
            return varied
        }
        return SFSymbol.glyph(named: name) ?? ""
    }
}
