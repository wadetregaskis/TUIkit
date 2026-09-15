//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A color for use in TUIkit views.
///
/// `Color` represents standard ANSI colors as well as
/// extended 256-color palette and True Color (24-bit RGB).
///
/// # Standard Colors
///
/// ```swift
/// Text("Red").foregroundStyle(.red)
/// Text("Green").foregroundStyle(.green)
/// Text("Blue").foregroundStyle(.blue)
/// ```
///
/// # RGB Colors
///
/// ```swift
/// Text("Custom").foregroundStyle(.rgb(255, 128, 0))
/// ```
import Foundation  // `String(format:)` / `trimmingCharacters` — stated, not borrowed from a sibling file (SE-0444)

public struct Color: Sendable, Hashable {
    /// The internal color value.
    public let value: ColorValue

    /// How opaque this colour is, 0 (invisible) through 255 (fully opaque).
    ///
    /// ## Why a byte and not a `Double`
    ///
    /// `ColorValue`'s widest payloads are three `UInt8`s (`.rgb` and the two
    /// terminal colours), so `Color` is four bytes at alignment 1. A `UInt8`
    /// makes it five, still with no
    /// padding; a `Double` makes it sixteen, aligned to eight, WITH padding
    /// bytes — and `viewValueHash` hashes the raw bytes of every view struct,
    /// where padding is undefined. A `Double` alpha would make the render memo's
    /// key non-deterministic for two identical views. 1/255 steps are also finer
    /// than the 256-colour cube can show. The public API is `Double`, quantised
    /// on the way in.
    ///
    /// ## What honours it
    ///
    /// Nothing yet, and that is deliberate rather than unfinished: the paths that
    /// resolve a colour to SGR bytes assert on it (see `Color+ANSICodes.swift`),
    /// so a translucent colour reaching one is a debug failure rather than a
    /// silently opaque cell. The public spellings — `Color.clear`, a real
    /// `opacity(_:)`, the `opacity:` initialisers — land only once the paths a
    /// reader will actually use honour it. See `Documentation/Opacity as
    /// composition.md`.
    public var alpha: UInt8 = 255

    /// Whether this colour is fully opaque — the common case, and the one every
    /// emitter asserts.
    public var isOpaque: Bool { alpha == .max }

    /// This colour at full strength — what goes into the SGR bytes when the
    /// alpha travels separately, as an `OpacityRegion`.
    ///
    /// Named rather than spelled `var c = self; c.alpha = .max` at each site so
    /// the intent is legible: the bytes and the region are two halves of one
    /// claim, and a reader has to be able to see that the byte half was
    /// deliberately opaque.
    public var opaqueSpelling: Self {
        var copy = self
        copy.alpha = .max
        return copy
    }

    /// This colour with `alpha` carried over from `source`.
    ///
    /// Every `Color` → `Color` derivation ends in this, so "did it carry the
    /// alpha" is one call to look for rather than a field to remember at each
    /// `return`. `ColourAlphaStorageTests.derivationsCarryAlpha` is the table
    /// that fails when a new derivation forgets.
    ///
    /// `package` rather than internal because not every derivation lives in this
    /// module: the scrollbar's lift is TUIkit's (§44), and spelling
    /// `copy.alpha = source.alpha` out there would be the one site this exists to
    /// make unnecessary. Not public: an app has `opacity(_:)` for stating an
    /// alpha, and has no derivations of the framework's to keep honest.
    package func carryingAlpha(of source: Self) -> Self {
        var copy = self
        copy.alpha = source.alpha
        return copy
    }

    /// This colour with `factor`'s alpha COMPOSED into its own, rather than
    /// substituted for it.
    ///
    /// The distinction matters at exactly one place, and it is not a style
    /// preference. ``carryingAlpha(of:)`` is for a re-SPELLING — a downsample, a
    /// contrast floor — where the result is the same colour written differently and
    /// there is only ever one alpha in play, so replacing it is right and composing
    /// it would fade a colour twice for having been quantised.
    ///
    /// Resolving a SEMANTIC colour is not a re-spelling: `.palette.accent` and the
    /// theme's `accent` slot are two different colours, each entitled to its own
    /// alpha, and the paint is subject to both. `.palette.accent.opacity(0.5)` on a
    /// theme whose accent is already half-faded means a quarter — the same
    /// multiplication ``opacity(_:)`` performs, for the same reason.
    ///
    /// Multiplied on the 0…255 integers with rounding, which is what keeps a chain
    /// of full-strength hops exact: 255 × 255 / 255 is 255 and not 254.
    func composingAlpha(of factor: Self) -> Self {
        guard !factor.isOpaque else { return self }
        var copy = self
        copy.alpha = UInt8(
            ((Double(alpha) * Double(factor.alpha)) / 255).rounded())
        return copy
    }

    /// Internal enum for different color types.
    public enum ColorValue: Sendable, Hashable {
        /// One of the terminal's sixteen colour slots: SGR 30–37 or 90–97 as a
        /// foreground, 40–47 or 100–107 as a background. It measures as xterm's
        /// value for the slot, ``ANSIColor/xtermRGB``.
        case ansi(ANSIColor)
        /// The terminal's default colour in whichever slot it is drawn: SGR 39 as
        /// a foreground and 49 as a background. This is `Color.default`. It
        /// measures as xterm's grey 229.
        case terminalDefault
        case palette256(UInt8)
        case rgb(red: UInt8, green: UInt8, blue: UInt8)
        case semantic(SemanticColor)
        /// The terminal's own default foreground, SGR 39.
        ///
        /// As a foreground it is 39 at every depth that has colour: the terminal
        /// paints its own colour. It measures as the RGB the terminal reported for
        /// that colour (OSC 10), which is what a blend, a contrast check or a
        /// surface walk reads. Until the terminal has reported it, it measures as
        /// nothing: `rgbComponents` is nil, and no colour is guessed. That is the
        /// difference from `Color.default`, which is also 39 but measures as
        /// xterm's grey 229.
        ///
        /// As a BACKGROUND no SGR names the default foreground. Once reported it is
        /// spelled as that RGB, quantised for the depth as a `.rgb` of the same
        /// components is. Until then there is nothing to spell, so it is the
        /// background slot's own default, 49.
        ///
        /// Downsampling returns it unchanged, because `downsampledToPalette256()`
        /// does not know which slot a colour is for; the emitter makes the choice.
        /// So something measuring it as a fill at 256 or 16 colours reads the exact
        /// reported RGB where the terminal is shown the quantised one.
        case terminalForeground
        /// The terminal's own default background, SGR 49: 49 as a background, and
        /// as a foreground the RGB the terminal reported for it (OSC 11),
        /// quantised, or 39 until it has reported one. It measures as that RGB, or
        /// as nothing. The twin of `terminalForeground`.
        case terminalBackground
    }

    /// A colour that is fully transparent — SwiftUI's `Color.clear`.
    ///
    /// Not `Color.default`, and the difference is not a footnote: `.default` is
    /// SGR 39/49, *the terminal's own* colour, which is perfectly visible. The one
    /// thing a reader reaches for `.clear` to do is hide something, and a modifier
    /// that renders the thing legibly instead is worse than one that does not
    /// exist.
    ///
    /// As a background — or as a view — it paints nothing and what is behind shows
    /// through.
    ///
    /// As a foreground it still draws its glyph, in the colour of the field the
    /// glyph sits on, so the text is present and selectable and invisible. That is
    /// deliberate and it is where a terminal differs from a canvas: a cell's
    /// character is the text a reader copies out, so dropping the glyph would hand
    /// them whatever was underneath instead. `.clear` ink is the field's colour
    /// wearing another name, exactly as `.foregroundColor(.black)` on a black
    /// field is — and neither reveals what is behind. To take a view out of the
    /// picture, use `View.hidden()` or `View.opacity(_:)` at zero, which say so.
    ///
    /// > Note: the underlying colour is black, as it is in SwiftUI, so anything
    /// > reading a colour's components and ignoring its alpha sees black. That
    /// > matters for a gradient stop — `Gradient(colors: [.red, .clear])` fades
    /// > toward transparent BLACK — which is also SwiftUI's behaviour.
    public static let clear = Self(value: .rgb(red: 0, green: 0, blue: 0), alpha: 0)

    // MARK: - Standard ANSI Colors

    /// Black (ANSI 30/40)
    public static let black = Self(value: .ansi(.black))

    /// Red (ANSI 31/41)
    public static let red = Self(value: .ansi(.red))

    /// Green (ANSI 32/42)
    public static let green = Self(value: .ansi(.green))

    /// Yellow (ANSI 33/43)
    public static let yellow = Self(value: .ansi(.yellow))

    /// Blue (ANSI 34/44)
    public static let blue = Self(value: .ansi(.blue))

    /// Magenta (ANSI 35/45)
    public static let magenta = Self(value: .ansi(.magenta))

    /// Cyan (ANSI 36/46)
    public static let cyan = Self(value: .ansi(.cyan))

    /// White (ANSI 37/47)
    public static let white = Self(value: .ansi(.white))

    /// Default color (terminal default)
    public static let `default` = Self(value: .terminalDefault)

    // MARK: - Bright ANSI Colors

    /// Bright black (gray)
    public static let brightBlack = Self(value: .ansi(.brightBlack))

    /// Bright red
    public static let brightRed = Self(value: .ansi(.brightRed))

    /// Bright green
    public static let brightGreen = Self(value: .ansi(.brightGreen))

    /// Bright yellow
    public static let brightYellow = Self(value: .ansi(.brightYellow))

    /// Bright blue
    public static let brightBlue = Self(value: .ansi(.brightBlue))

    /// Bright magenta
    public static let brightMagenta = Self(value: .ansi(.brightMagenta))

    /// Bright cyan
    public static let brightCyan = Self(value: .ansi(.brightCyan))

    /// Bright white
    public static let brightWhite = Self(value: .ansi(.brightWhite))

    // MARK: - SwiftUI's Named Colors

    // The eight names SwiftUI has that the ANSI vocabulary above does not.
    //
    // The VALUES are Apple's system palette, sampled from AppKit in the light
    // (aqua) appearance rather than guessed — `NSColor.systemOrange` and friends
    // converted to sRGB. SwiftUI resolves these dynamically per appearance; a
    // terminal has no such notion, so one appearance had to be chosen and light
    // is the one a default terminal theme matches.
    //
    // - Important: These are deliberately NOT the CSS colours of the same name.
    //   `Color.orange` is Apple's `#FF9500`; CSS "orange" is `#FFA500`, and the
    //   colour picker's Named-colours tab (``SwatchPalettes``) lists the CSS
    //   value under that name. Both are correct for what they are: the picker
    //   browses the web vocabulary, this matches the SwiftUI source you are
    //   porting. Do not reconcile them.
    //
    // `.red`, `.green`, `.blue` and `.yellow` are NOT re-pointed at their system
    // values. In a terminal those names mean the ANSI slots, which the user's
    // theme defines — taking that away to gain a nominal match with Apple's
    // `#FF3B30` would break every themed app on screen.

    /// Grey (Apple's system grey, `#8E8E93`).
    public static let gray = Self.hex(0x8E_8E_93)

    /// Orange (Apple's system orange, `#FF9500`).
    public static let orange = Self.hex(0xFF_95_00)

    /// Pink (Apple's system pink, `#FF2D55`).
    public static let pink = Self.hex(0xFF_2D_55)

    /// Purple (Apple's system purple, `#AF52DE`).
    public static let purple = Self.hex(0xAF_52_DE)

    /// Brown (Apple's system brown, `#A2845E`).
    public static let brown = Self.hex(0xA2_84_5E)

    /// Mint (Apple's system mint, `#00C7BE`).
    public static let mint = Self.hex(0x00_C7_BE)

    /// Teal (Apple's system teal, `#59ADC4`).
    public static let teal = Self.hex(0x59_AD_C4)

    /// Indigo (Apple's system indigo, `#5856D6`).
    public static let indigo = Self.hex(0x58_56_D6)

    // MARK: - Semantic Colors

    /// These are the SwiftUI-shaped spellings of the palette roles below, and
    /// they mean exactly those roles — they are not fixed colours that happen
    /// to be named after them.
    ///
    /// They used to be: `primary` was `Color.blue` and `accent` was
    /// `Color.cyan`. That was wrong twice over. It disagreed with SwiftUI,
    /// where `.primary` is the colour a label defaults to rather than a hue;
    /// and, more fundamentally, **a fixed ANSI name is not a colour anyone can
    /// predict** — `SGR 34` selects slot 4 of the user's scheme, which they are
    /// free to make orange. A colour the framework chooses on the user's behalf
    /// has to be either a palette role, which the app's theme defines, or
    /// ``default``, which is explicitly the user's own. See "What an ANSI
    /// colour actually paints" in `Documentation/Terminal-compatibility.md`.
    ///
    /// Being semantic, they resolve at render time and return `nil` from
    /// ``rgbComponents`` until they do — see ``resolve(with:)``.

    /// The colour text defaults to — SwiftUI's `.primary`, and the palette's
    /// ``SemanticColor/foreground``.
    public static let primary = Self.palette.foreground

    /// A lower-emphasis label colour — SwiftUI's `.secondary`, and the
    /// palette's ``SemanticColor/foregroundSecondary``.
    public static let secondary = Self.palette.foregroundSecondary

    /// The app's accent — SwiftUI's `.accentColor`, and the palette's
    /// ``SemanticColor/accent``.
    ///
    /// Spelled as SwiftUI spells it. It was `Color.accent`, which was a second
    /// name for a thing `Color.palette.accent` already said, and named the
    /// FIXED cyan rather than the themed role — so ported SwiftUI code that
    /// wrote `.accentColor` did not compile, and code that wrote `.accent` got
    /// the un-themed one.
    public static let accentColor = Self.palette.accent

    /// Warning color — the palette's ``SemanticColor/warning``.
    public static let warning = Self.palette.warning

    /// Error color — the palette's ``SemanticColor/error``.
    public static let error = Self.palette.error

    /// Success color — the palette's ``SemanticColor/success``.
    public static let success = Self.palette.success

    // MARK: - Palette-Aware Semantic Colors

    /// Namespace for palette-aware semantic colors.
    ///
    /// These colors are resolved at render time against the current ``Palette``
    /// via ``resolve(with:)``. Use them in view `body` properties where no
    /// ``RenderContext`` is available:
    ///
    /// ```swift
    /// Text("Hello").foregroundStyle(.palette.accent)
    /// ```
    public enum Semantic {
        // Background colors
        public static let background = Color(value: .semantic(.background))
        public static let statusBarBackground = Color(value: .semantic(.statusBarBackground))
        public static let appHeaderBackground = Color(value: .semantic(.appHeaderBackground))
        public static let overlayBackground = Color(value: .semantic(.overlayBackground))

        // Foreground colors
        public static let foreground = Color(value: .semantic(.foreground))
        public static let foregroundSecondary = Color(value: .semantic(.foregroundSecondary))
        public static let foregroundTertiary = Color(value: .semantic(.foregroundTertiary))
        public static let foregroundQuaternary = Color(value: .semantic(.foregroundQuaternary))

        // Accent colors
        public static let accent = Color(value: .semantic(.accent))

        // Status colors
        public static let success = Color(value: .semantic(.success))
        public static let warning = Color(value: .semantic(.warning))
        public static let error = Color(value: .semantic(.error))
        public static let info = Color(value: .semantic(.info))

        // UI element colors
        public static let border = Color(value: .semantic(.border))
    }

    /// Access palette-aware semantic colors.
    ///
    /// Colors returned by this namespace are not resolved until render time,
    /// when the current ``Palette`` is available via ``RenderContext``.
    ///
    /// ```swift
    /// Text("Hello").foregroundStyle(.palette.accent)
    /// ```
    public static var palette: Semantic.Type { Semantic.self }

    /// The RGB components of this color.
    ///
    /// Converts any color type to its RGB representation:
    /// - `.rgb` — returned directly
    /// - `.ansi` — xterm's conventional value for the slot, ``ANSIColor/xtermRGB``
    /// - `.terminalDefault` — xterm's default foreground, grey 229
    /// - `.palette256` — mapped to xterm 256-color palette RGB values
    /// - `.terminalForeground` / `.terminalBackground` — the RGB the terminal
    ///   reported for its default foreground or background, or nil until it has
    /// - `.semantic` — returns nil (must be resolved first via ``resolve(with:)``)
    public var rgbComponents: (red: UInt8, green: UInt8, blue: UInt8)? {
        switch value {
        case .rgb(let red, let green, let blue):
            return (red, green, blue)
        case .terminalForeground:
            return TerminalColors.current.foreground.map { (red: $0.red, green: $0.green, blue: $0.blue) }
        case .terminalBackground:
            return TerminalColors.current.background.map { (red: $0.red, green: $0.green, blue: $0.blue) }
        case .ansi(let slot):
            return slot.xtermRGB
        case .terminalDefault:
            // xterm's default foreground, the same grey as its value for slot 7.
            return (229, 229, 229)
        case .palette256(let index):
            return Self.palette256ToRGB(index)
        case .semantic:
            return nil
        }
    }

    /// Whether the TERMINAL decides what this colour paints, rather than its
    /// components: the sixteen slots, `.default`, 256-colour indices 0-15 (the
    /// same sixteen slots, spelled by index), and the two carried cases, SGR 39
    /// and 49.
    ///
    /// Indices 16-255, the cube and the grey ramp, count as ordinary RGB, being
    /// conventionally fixed; see "What an ANSI colour actually paints" in
    /// `Documentation/Terminal-compatibility.md`. A semantic colour is not one
    /// until it is resolved.
    package var isTerminalDefined: Bool {
        switch value {
        case .ansi, .terminalDefault, .terminalForeground, .terminalBackground: return true
        case .palette256(let index): return index < 16
        case .rgb, .semantic: return false
        }
    }
}

// MARK: - Public API

extension Color {
    /// Resolves this color against a palette.
    ///
    /// Non-semantic colors are returned unchanged. Semantic colors are mapped to
    /// the corresponding palette property — *transitively*, because a palette
    /// slot may itself hold a semantic reference (a palette editor can set
    /// `accent` to `.semantic(.success)`, so resolving `.accent` yields another
    /// semantic colour that must be resolved in turn).
    ///
    /// The result is **always concrete**. A reference cycle (e.g. a slot set to
    /// its own role, `accent` → `.semantic(.accent)`) is broken after a bounded
    /// number of hops and falls back to a neutral RGB, so resolution can neither
    /// loop forever nor return a `.semantic` colour to the renderer — which
    /// `ANSIRenderer` traps on. (Without this, clicking a role in a colour
    /// picker's semantic tab while editing that same role crashed the app.)
    ///
    /// - Parameter palette: The palette to resolve against.
    /// - Returns: A concrete (non-semantic) color.
    public func resolve(with palette: any Palette) -> Color {
        var resolved = self
        // 16 > the number of palette roles, so any acyclic reference chain
        // resolves fully within the cap; only a cycle reaches it.
        for _ in 0..<16 {
            // `resolved` carries the accumulated alpha of every hop so far — it
            // starts as `self`, so the reference's own alpha is in it from the
            // outset and the exits need no further arithmetic.
            guard case .semantic(let token) = resolved.value else { return resolved }
            // The hop's alpha COMPOSES with what it points at rather than replacing
            // it — see ``composingAlpha(of:)``. A slot's translucency is the theme's
            // statement and the reference's is the call site's, and the paint is
            // subject to both. `carryingAlpha` here silently discarded whatever the
            // theme had said, so a faded palette role rendered solid.
            resolved = token.resolve(with: palette).composingAlpha(of: resolved)
        }
        if case .semantic = resolved.value {
            return Color.rgb(128, 128, 128).carryingAlpha(of: resolved)
        }
        return resolved
    }

    /// Creates a color from the 256-color palette.
    ///
    /// - Parameter index: The palette index (0-255).
    /// - Returns: The corresponding color.
    public static func palette(_ index: UInt8) -> Self {
        Self(value: .palette256(index))
    }

    /// Creates a True Color RGB color.
    ///
    /// - Parameters:
    ///   - red: The red component (0-255).
    ///   - green: The green component (0-255).
    ///   - blue: The blue component (0-255).
    /// - Returns: The RGB color.
    public static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Self {
        Self(value: .rgb(red: red, green: green, blue: blue))
    }

    /// Creates a color from a hex value.
    ///
    /// - Parameter hex: The hex value (e.g., 0xFF5500).
    /// - Returns: The corresponding RGB color.
    public static func hex(_ hex: UInt32) -> Self {
        let red = UInt8((hex >> 16) & 0xFF)
        let green = UInt8((hex >> 8) & 0xFF)
        let blue = UInt8(hex & 0xFF)
        return .rgb(red, green, blue)
    }

    /// Creates a color from a hex string.
    ///
    /// Supports formats: "#RGB", "#RRGGBB", "RGB", "RRGGBB"
    ///
    /// - Parameter hex: The hex string (e.g., "#FF5500", "F50", "#abc").
    /// - Returns: The corresponding RGB color, or nil if invalid.
    public static func hex(_ hex: String) -> Self? {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove # prefix if present
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        // Handle shorthand format (RGB -> RRGGBB)
        if hexString.count == 3 {
            let chars = Array(hexString)
            hexString = String([chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]])
        }

        // Must be 6 characters now
        guard hexString.count == 6 else { return nil }

        // Parse hex value
        guard let hexValue = UInt32(hexString, radix: 16) else { return nil }

        return .hex(hexValue)
    }

    /// Returns a lighter version of this color.
    ///
    /// The percentage is relative to the remaining lightness headroom.
    /// For example, a color with HSL lightness 60 lightened by 0.5 (50%)
    /// moves halfway toward 100: `60 + (100 − 60) × 0.5 = 80`.
    ///
    /// - Parameter percentage: The fraction to lighten (0–1, default 0.2 = 20%).
    /// - Returns: A lighter color with preserved hue and saturation.
    public func lighter(by percentage: Double = 0.2) -> Self {
        adjusted(by: percentage)
    }

    /// Returns a darker version of this color.
    ///
    /// The percentage is relative to the current lightness.
    /// For example, a color with HSL lightness 60 darkened by 0.5 (50%)
    /// moves halfway toward 0: `60 × (1 − 0.5) = 30`.
    ///
    /// - Parameter percentage: The fraction to darken (0–1, default 0.2 = 20%).
    /// - Returns: A darker color with preserved hue and saturation.
    public func darker(by percentage: Double = 0.2) -> Self {
        adjusted(by: -percentage)
    }

    /// This colour at `opacity` — SwiftUI's `Color.opacity(_:)`, and real alpha.
    ///
    /// The result carries the opacity rather than approximating it. What it is
    /// finally drawn over is decided at the composite, where what is behind the
    /// cell is known: `Color.blue.opacity(0.4)` over a red pane is 40% of the way
    /// from RED, and over a green one 40% of the way from green.
    ///
    /// This used to mix toward BLACK, which was right only on a black terminal
    /// and turned every "dim" into a near-black smudge on a light palette. It
    /// also returned `self` untouched for any `.semantic` colour — so
    /// `Color.primary.opacity(0.5)`, `Color.accentColor.opacity(0.5)` and
    /// everything under `Color.palette` compiled and did nothing at all. Both are
    /// gone: the alpha is stored, and it survives ``resolve(with:)``.
    ///
    /// ``opacity(_:over:)`` is the other thing, and still useful: it composites
    /// against a surface the CALLER names and answers with a concrete colour, for
    /// the many places in this framework that derive a style from a palette and
    /// know exactly what it sits on.
    ///
    /// **Multiplies** the alpha already there rather than replacing it, which is
    /// SwiftUI's documented behaviour and is measured: `Color.red.opacity(0.5)`
    /// `.opacity(0.5)` resolves to alpha 0.25 there, and `.opacity(0.25)`
    /// `.opacity(0.5)` to 0.125.
    ///
    /// The case that makes it matter rather than merely differ is
    /// `Color.clear.opacity(1)`. SwiftUI answers 0 — nothing times anything is
    /// nothing. Replacing the alpha answers 255, which turns `.clear` into the
    /// solid black its underlying value happens to be, in code that reads like a
    /// no-op.
    ///
    /// - Parameter opacity: The factor (0–1; clamped, and a NaN reads as 0).
    /// - Returns: This colour, at that fraction of the opacity it had.
    public func opacity(_ opacity: Double) -> Self {
        var copy = self
        // Clamped, because a caller is allowed to hand this a number out of
        // range and `UInt8(_: Double)` traps on one. `min`/`max` in this order
        // also fold a NaN to 0, which is the only answer available.
        let factor = min(1, max(0, opacity))
        copy.alpha = UInt8(min(255, max(0, (Double(alpha) * factor).rounded())))
        return copy
    }

    /// Returns the color composited at `opacity` over `surface` — true alpha
    /// blending, unlike ``opacity(_:)`` which can only mix toward black.
    ///
    /// Over a black surface the two coincide exactly, which is how the
    /// mix-toward-black shorthand survived on dark palettes; over light
    /// surfaces it turns every "dim" into a near-black smudge (the
    /// dark-on-dark controls seen under light palettes), so palette-aware
    /// rendering should pass the surface the colour actually draws on.
    ///
    /// **The mix is in ENCODED sRGB**, which is the whole difference from
    /// ``compositing(_:over:)`` and is deliberate: encoded space is near enough
    /// perceptually uniform that equal steps of `opacity` look like equal steps,
    /// where a linear-light mix puts 22× more visible change at the transparent
    /// end than at the opaque one. This is what every style derivation, every
    /// fade and every transition dissolve uses, and what SwiftUI is measured to
    /// composite with.
    ///
    /// - Parameters:
    ///   - opacity: The opacity (0–1).
    ///   - surface: The colour beneath, typically the palette background the
    ///     view draws over.
    /// - Returns: The blended color, or `self` if either side is semantic.
    public func opacity(_ opacity: Double, over surface: Color) -> Self {
        // This colour's OWN alpha is part of the coverage, not something separate
        // from it. `.tint(.red.opacity(0.5))` reaches here through
        // `restingControlFace` as `accent.opacity(focusBorderDim, over: background)`,
        // and reading only the parameter discarded the tint's own translucency
        // outright — silently, because the result is stamped opaque and so never
        // trips the emitter's assertion. Folded in, a half-faded tint gives a
        // subtler face, which is what asking for it means.
        //
        // Exact for the overwhelming case: an opaque source multiplies by 1.
        let coverage = Double(alpha) / 255 * min(1, max(0, opacity))
        // CONSUMES the alpha rather than carrying it: this composites over a
        // surface that is KNOWN, so its answer is a concrete colour and any
        // further alpha would apply the same fade twice. `lerp` interpolates
        // alpha as a fourth channel, which is right for an animation and wrong
        // here, so the result is stamped opaque.
        var result = Self.lerp(self, surface, phase: 1 - coverage)
        result.alpha = .max
        return result
    }

    /// This colour with a translucent alpha SPENT against `ground` — the bright
    /// end of a focus breath.
    ///
    /// An opaque colour is returned **untouched** rather than composited at 1, and
    /// not as an economy: ``opacity(_:over:)`` lerps, and a lerp re-spells `.red`
    /// (SGR 31, the terminal's OWN red) as `rgb(205, 0, 0)` (SGR 38;2;…). Same
    /// colour by arithmetic, a different colour on any terminal whose palette is
    /// not the default — and this is the bright end of every focus pulse on every
    /// palette that ships.
    ///
    /// - Parameter ground: What the breath is drawn on. The dim end must be
    ///   composited over the same colour, or the two ends will not agree.
    public func spendingAlpha(over ground: Color) -> Self {
        isOpaque ? self : opacity(1, over: ground)
    }

    /// The two ends of a breath between a dimmed version of this colour and this
    /// colour itself, **both** spending a translucent alpha against one ground.
    ///
    /// Both ends, together, because a pulse's ends must agree about alpha and
    /// four separate copies of this pair had already drifted apart in exactly the
    /// same way: a dim end through ``opacity(_:over:)``, which consumes the alpha
    /// and stamps the result opaque, beside a bright end that was the colour
    /// itself and carried it. `.tint(.red.opacity(0.5))` then breathed between an
    /// opaque colour and a translucent one — half the cycle honoured, half of it a
    /// debug trap — and no static claim could describe the run, because its alpha
    /// genuinely differed per phase.
    ///
    /// - Parameters:
    ///   - factor: How far the quiet end recedes toward `ground` (0–1).
    ///   - ground: What the breath is drawn on — the enclosing surface, not the
    ///     page, wherever a container has painted one.
    public func breathEnds(dimmedTo factor: Double, over ground: Color) -> (dim: Self, bright: Self) {
        (dim: opacity(factor, over: ground), bright: spendingAlpha(over: ground))
    }

    /// This colour mixed with another — SwiftUI's spelling of ``lerp(_:_:phase:)``.
    ///
    /// ```swift
    /// let halfway = Color.red.mix(with: .blue, by: 0.5)
    /// ```
    ///
    /// Exactly a two-stop gradient evaluated at `fraction`:
    /// `Gradient(colors: [self, rhs]).color(at: fraction)` is the same colour,
    /// because both are this one interpolation.
    ///
    /// ## The default is `.perceptual`, and a gradient's is not
    ///
    /// That asymmetry is SwiftUI's, kept rather than tidied: a bare
    /// ``Gradient`` interpolates in ``Gradient/ColorSpace/device`` and this
    /// mixes in ``Gradient/ColorSpace/perceptual``. So
    /// `Color.red.mix(with: .blue, by: 0.5)` and
    /// `Gradient(colors: [.red, .blue]).color(at: 0.5)` are NOT the same
    /// colour unless you say so — the first comes out of OKLab, the second out
    /// of encoded sRGB. Pass `in: .device`, or build the gradient with
    /// `colorSpace: .perceptual`, and they agree again.
    ///
    /// - Parameters:
    ///   - rhs: The colour to mix towards.
    ///   - fraction: How far towards `rhs` (0–1; clamped).
    ///   - colorSpace: Which space to mix in.
    /// - Returns: The mixture, or `self` if either side is semantic.
    public func mix(
        with rhs: Color, by fraction: Double,
        in colorSpace: Gradient.ColorSpace = .perceptual
    ) -> Self {
        Self.interpolate(self, rhs, phase: fraction, in: colorSpace)
    }

    /// Two colours blended in a named space — the whole of what
    /// ``Gradient/ColorSpace`` decides.
    ///
    /// `.device` is ``lerp(_:_:phase:)`` exactly, so nothing that does not ask
    /// for a space changes by a byte. `.perceptual` goes through OKLab, where a
    /// straight line between two colours looks like one: the midpoint of red
    /// and blue stops being darker than either end, and blue to yellow stops
    /// passing through grey.
    ///
    /// - Parameters:
    ///   - from: The colour at `0`.
    ///   - to: The colour at `1`.
    ///   - phase: How far between them (0–1; clamped).
    ///   - space: Which space to blend in.
    /// - Returns: The blend, or `from` if either side is semantic.
    package static func interpolate(
        _ from: Color, _ to: Color, phase: Double, in space: Gradient.ColorSpace
    ) -> Color {
        guard space.isPerceptual else { return lerp(from, to, phase: phase) }
        guard let fromRGB = from.rgbComponents, let toRGB = to.rgbComponents else { return from }
        let clamped = min(1, max(0, phase))
        let start = oklab(red: fromRGB.red, green: fromRGB.green, blue: fromRGB.blue)
        let end = oklab(red: toRGB.red, green: toRGB.green, blue: toRGB.blue)
        let blended = fromOKLab(
            l: start.l + (end.l - start.l) * clamped,
            a: start.a + (end.a - start.a) * clamped,
            b: start.b + (end.b - start.b) * clamped)
        var result = Color.rgb(blended.red, blended.green, blended.blue)
        // The fourth channel, interpolated linearly — alpha has no perceptual
        // space of its own, and OKLab has nothing to say about it. Both arms of
        // this function therefore agree about alpha even though they disagree
        // about colour, which is what a caller switching `colorSpace` expects.
        result.alpha = UInt8(
            min(
                255,
                max(
                    0,
                    (Double(from.alpha)
                        + (Double(to.alpha) - Double(from.alpha)) * min(1, max(0, phase)))
                        .rounded())))
        return result
    }

    /// Linearly interpolates between two colors.
    ///
    /// Both colors are converted to RGB before interpolation. If either
    /// color is semantic (unresolved), the `from` color is returned unchanged.
    ///
    /// Used by the breathing focus indicator to smoothly fade between
    /// a dimmed and a full-brightness accent color.
    ///
    /// ## Rounding
    ///
    /// To nearest, because that is the answer with the smallest average error —
    /// truncating biases every channel of every blend down by half a unit, and
    /// a "dim" derived by blending toward the background is therefore always a
    /// shade darker than it was asked to be. It also agreed with nothing else:
    /// `encodedChannel`, which is where the perceptual path and the
    /// linear-light compositing path both come out, has always rounded. Two
    /// answers to the same question was the only reason for the difference.
    ///
    /// - Parameters:
    ///   - from: The start color (returned when `phase` is 0).
    ///   - to: The end color (returned when `phase` is 1).
    ///   - phase: The interpolation factor (0–1, clamped; a `phase` of NaN
    ///     reads as 0).
    /// - Returns: The interpolated RGB color.
    public static func lerp(_ from: Color, _ to: Color, phase: Double) -> Color {
        guard let fromRGB = from.rgbComponents,
            let toRGB = to.rgbComponents
        else {
            return from
        }

        let clamped = min(1, max(0, phase))
        func blend(_ start: UInt8, _ end: UInt8) -> UInt8 {
            let value = Double(start) + (Double(end) - Double(start)) * clamped
            // Clamped as well as rounded: the arithmetic cannot leave 0…255 for
            // a `clamped` in 0…1, but `UInt8(_: Double)` traps if it ever did,
            // and a trap is not an acceptable answer to a rounding question.
            return UInt8(min(255, max(0, value.rounded())))
        }

        var result = Color.rgb(
            blend(fromRGB.red, toRGB.red),
            blend(fromRGB.green, toRGB.green),
            blend(fromRGB.blue, toRGB.blue))
        // Alpha is a fourth channel and interpolates like the others. Both colour
        // animators go through here, so this is what makes a `withAnimation` fade
        // of a colour's own opacity work rather than snap.
        result.alpha = blend(from.alpha, to.alpha)
        return result
    }
}

// MARK: - Internal Helpers

extension Color {
    /// Converts a 256-color palette index to RGB values.
    ///
    /// - Indices 0–15: the sixteen ANSI slots, at xterm's values
    /// - Indices 16–231: 6×6×6 color cube
    /// - Indices 232–255: grayscale ramp
    package static func palette256ToRGB(_ index: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
        switch index {
        case 0...15:
            // A slot's raw value is its index, so every index here is a slot.
            guard let slot = ANSIColor(rawValue: index) else { return (0, 0, 0) }
            return slot.xtermRGB
        case 16...231:
            // 6×6×6 color cube: index = 16 + 36*r + 6*g + b (each 0–5)
            let cubeIndex = index - 16
            let cubeRed = cubeIndex / 36
            let cubeGreen = (cubeIndex % 36) / 6
            let cubeBlue = cubeIndex % 6
            let channelMap: [UInt8] = [0, 95, 135, 175, 215, 255]
            return (channelMap[Int(cubeRed)], channelMap[Int(cubeGreen)], channelMap[Int(cubeBlue)])
        default:
            // Grayscale ramp: 232–255 → 8, 18, 28, ..., 238
            let gray = UInt8(8 + Int(index - 232) * 10)
            return (gray, gray, gray)
        }
    }
}

// MARK: - Private Helpers

extension Color {
    /// Adjusts a color's lightness by a relative percentage in HSL space.
    ///
    /// Positive values lighten (move toward 100), negative values darken
    /// (move toward 0). The adjustment is **relative** to the current position:
    ///
    /// - Lighten: `newLightness = lightness + (100 − lightness) × percentage`
    /// - Darken:  `newLightness = lightness × (1 − |percentage|)`
    ///
    /// This means 0.5 always moves halfway to the target extreme, regardless
    /// of the starting lightness. Hue and saturation are preserved.
    ///
    /// - Parameter percentage: The relative adjustment (−1 to 1).
    /// - Returns: The adjusted color as HSL at this colour's alpha, or self if
    ///   semantic (unresolved).
    fileprivate func adjusted(by percentage: Double) -> Self {
        guard let (red, green, blue) = rgbComponents else {
            return self
        }

        let (hue, saturation, lightness) = Self.rgbToHSL(red: red, green: green, blue: blue)
        let clamped = min(1.0, max(-1.0, percentage))

        let newLightness: Double
        if clamped >= 0 {
            // Lighten: move toward 100
            newLightness = lightness + (100.0 - lightness) * clamped
        } else {
            // Darken: move toward 0
            newLightness = lightness * (1.0 + clamped)
        }

        // Carried, not composed: a lightness step is the same ink re-spelled, so
        // `Color.red.opacity(0.5).lighter()` is as faded as what it started from.
        // `Self.hsl` is a factory that never sees `self` and builds at 255, so
        // without this the alpha was not decided away but unreachable — and an
        // opaque result trips no emitter assertion, so the fade vanished silently.
        // §39 answered this same step for `Palette.scaled(_:by:)`. A semantic
        // colour never gets here: the guard above hands it back whole.
        return Self.hsl(hue, saturation, min(100, max(0, newLightness))).carryingAlpha(of: self)
    }
}
