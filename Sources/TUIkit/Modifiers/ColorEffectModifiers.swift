//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorEffectModifiers.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore
import TUIkitStyling
import TUIkitView

extension View {
    /// Brightens or darkens everything this view draws.
    ///
    /// Added to each colour channel, as in SwiftUI: `0` changes nothing, `1`
    /// drives everything to white, `-1` to black.
    ///
    /// - Parameter amount: `-1` through `1`.
    /// - Returns: A view whose colours are brightened.
    public func brightness(_ amount: Double) -> some View {
        _ColorEffectView(content: self, effect: .brightness, amount: amount)
    }

    /// Pushes this view's colours away from mid-grey, or toward it.
    ///
    /// `1` changes nothing, `0` flattens everything to mid-grey, and above `1`
    /// exaggerates — which on a character grid is the difference between text
    /// that recedes and text that shouts. Negative values invert as they
    /// stretch, as in SwiftUI.
    ///
    /// - Parameter amount: `0` (flat) upward; `1` is unchanged.
    /// - Returns: A view with adjusted contrast.
    public func contrast(_ amount: Double) -> some View {
        _ColorEffectView(content: self, effect: .contrast, amount: amount)
    }

    /// Adjusts the colourfulness of everything this view draws.
    ///
    /// `1` changes nothing, `0` is grey, and above `1` intensifies.
    ///
    /// - Parameter amount: `0` (grey) upward; `1` is unchanged.
    /// - Returns: A view with adjusted saturation.
    public func saturation(_ amount: Double) -> some View {
        _ColorEffectView(content: self, effect: .saturation, amount: amount)
    }

    /// Drains the colour out of everything this view draws.
    ///
    /// The inverse of ``saturation(_:)``: `0` changes nothing, `1` is entirely
    /// grey. Useful for showing that a region is unavailable without dimming
    /// it — a terminal has no other way to say "present but inert" that does
    /// not also say "faint".
    ///
    /// - Parameter amount: `0` (unchanged) through `1` (grey).
    /// - Returns: A view drained of colour.
    public func grayscale(_ amount: Double) -> some View {
        _ColorEffectView(content: self, effect: .grayscale, amount: amount)
    }

    /// Rotates every colour around the hue wheel.
    ///
    /// The one geometric-sounding effect that a character grid can perform
    /// exactly: a hue IS an angle, and nothing about the cells moves.
    ///
    /// - Parameter angle: How far around the wheel.
    /// - Returns: A view with rotated hues.
    public func hueRotation(_ angle: Angle) -> some View {
        _ColorEffectView(content: self, effect: .hueRotation, amount: angle.degrees)
    }

    /// Inverts every colour this view draws.
    ///
    /// - Returns: A view with inverted colours.
    public func colorInvert() -> some View {
        _ColorEffectView(content: self, effect: .invert, amount: 1)
    }

    /// Multiplies every colour this view draws by `color`.
    ///
    /// A tint: white leaves everything alone, and a colour with a zero channel
    /// removes that channel entirely.
    ///
    /// `color`'s own opacity multiplies too, as SwiftUI's does — the multiply is of
    /// RGBA, not RGB — so `.colorMultiply(.white.opacity(0.5))` leaves every hue
    /// alone and fades the subtree by half, and `.colorMultiply(.clear)` hides it.
    /// The alpha becomes a fade of the whole layer rather than of its colours: see
    /// `Documentation/Opacity as composition.md` §25.
    ///
    /// - Parameter color: The colour to multiply by.
    /// - Returns: A tinted view.
    public func colorMultiply(_ color: Color) -> some View {
        _ColorEffectView(content: self, effect: .multiply(color), amount: 1)
    }
}

/// Rewrites the colours of everything its content drew. See ``View/brightness(_:)``
/// and friends.
///
/// One type for all of them because they are one operation with different
/// arithmetic: walk the rendered lines, and replace each colour the escapes
/// name with a function of it (``SGRColorRewrite``). Nothing is re-rendered,
/// nothing is re-measured, and the cells are exactly the ones the content drew
/// — which is what makes these affordable enough to animate.
struct _ColorEffectView<Content: View>: View {
    /// Which arithmetic.
    enum Effect: Equatable {
        case brightness
        case contrast
        case saturation
        case grayscale
        case hueRotation
        case invert
        case multiply(Color)

        /// Whether `amount` leaves every colour alone, so the line rewrite can be
        /// skipped.
        ///
        /// About the COLOURS only — a translucent multiply tint also fades the layer,
        /// and that is not a rewrite of anything (see `renderToBuffer`). Hence
        /// `opaqueSpelling`: `.white.opacity(0.5)` leaves every hue exactly where it
        /// was and is answered `true` here, with its alpha handled apart.
        ///
        /// `.white` is the multiply identity by SPELLING and not by arithmetic, which
        /// is worth knowing before touching this. `Color.white` is ANSI white — 229,
        /// not 255 — so multiplying by its components darkens by 229/255. The
        /// shortcut is what makes `.colorMultiply(.white)` mean what it says, and
        /// before `opaqueSpelling` was here a faded white slipped past it and
        /// darkened the subtree as a side effect of fading it.
        func isIdentity(at amount: Double) -> Bool {
            switch self {
            case .brightness, .grayscale, .hueRotation: amount == 0
            case .contrast, .saturation: amount == 1
            case .invert: false
            case .multiply(let color): color.opaqueSpelling == .white
            }
        }
    }

    let content: Content
    let effect: Effect
    var amount: Double

    var body: Never {
        fatalError("_ColorEffectView renders via Renderable")
    }
}

extension _ColorEffectView: Animatable {
    /// The amount is the one continuous thing, so `withAnimation` ramps the
    /// effect rather than switching it.
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
}

extension _ColorEffectView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIkit.renderToBuffer(content, context: context)
        guard !buffer.isEmpty else { return buffer }

        // A translucent multiply tint fades the LAYER, and that is not a stylistic
        // reading: `colorMultiply` multiplies RGBA, so an alpha of 0.5 in the tint
        // halves the alpha of everything under it. The RGB half is the arithmetic in
        // `applied(to:amount:)`; the alpha half cannot be, because a colour's alpha
        // is not in the SGR bytes that rewrites.
        //
        // The LAYER channel rather than ink and field, for the same reason
        // `.opacity(_:)` uses it: this says how PRESENT the subtree is, not how faint
        // its colours are, so a cell at 0.4 hands its glyph to whatever is behind it
        // by the ½ rule. On ink and field instead, a fully transparent
        // `colorMultiply` would still draw its glyphs — and `.opacity(_:)` would mean
        // something different from `.colorMultiply(.white.opacity(_:))`, which in
        // SwiftUI it does not.
        let layerFade: Double? =
            if case .multiply(let tint) = effect, !tint.isOpaque {
                Double(tint.alpha) / 255
            } else {
                nil
            }
        let rewrites = !effect.isIdentity(at: amount)
        guard rewrites || layerFade != nil else { return buffer }

        // Resolve first: a semantic colour is a silent no-op through the
        // arithmetic and makes `ANSIRenderer` trap outright.
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let foreground = palette.foreground.resolve(with: palette)
        let effect = self.effect
        let amount = self.amount

        var result =
            rewrites
            ? buffer.replacingLines(
                buffer.lines.map { line in
                    SGRColorRewrite.rewriting(
                        line, defaultForeground: foreground, defaultBackground: surface
                    ) { effect.applied(to: $0, amount: amount) }
                })
            : buffer
        if let layerFade {
            result.opacityRegions.append(
                OpacityRegion(
                    offsetX: 0, offsetY: 0, width: result.width,
                    height: result.height, opacity: layerFade))
        }
        return result
    }
}

extension _ColorEffectView: Layoutable {
    /// A colour effect rewrites colours in place: same characters, same cells,
    /// same size.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - The arithmetic

extension _ColorEffectView.Effect {
    /// `color` with this effect applied.
    func applied(to color: Color, amount: Double) -> Color {
        guard let rgb = color.rgbComponents else { return color }
        switch self {
        case .brightness:
            return Self.mapped(rgb) { $0 + amount * 255 }
        case .contrast:
            return Self.mapped(rgb) { ($0 - 127.5) * amount + 127.5 }
        case .saturation:
            return Self.blendedTowardGrey(rgb, keeping: amount)
        case .grayscale:
            return Self.blendedTowardGrey(rgb, keeping: 1 - amount)
        case .hueRotation:
            let hsl = Color.rgbToHSL(red: rgb.red, green: rgb.green, blue: rgb.blue)
            return Color.hsl(
                (hsl.hue + amount).truncatingRemainder(dividingBy: 360),
                hsl.saturation, hsl.lightness)
        case .invert:
            return Self.mapped(rgb) { 255 - $0 }
        case .multiply(let tint):
            guard let other = tint.rgbComponents else { return color }
            return Color.rgb(
                Self.byte(Double(rgb.red) * Double(other.red) / 255),
                Self.byte(Double(rgb.green) * Double(other.green) / 255),
                Self.byte(Double(rgb.blue) * Double(other.blue) / 255))
        }
    }

    /// Rec. 709 luminance — the grey a colour reads as. Blending toward it is
    /// what both saturation and grayscale do, from opposite ends.
    private static func blendedTowardGrey(
        _ rgb: (red: UInt8, green: UInt8, blue: UInt8), keeping amount: Double
    ) -> Color {
        let grey =
            0.2126 * Double(rgb.red) + 0.7152 * Double(rgb.green) + 0.0722 * Double(rgb.blue)
        return Color.rgb(
            byte(grey + (Double(rgb.red) - grey) * amount),
            byte(grey + (Double(rgb.green) - grey) * amount),
            byte(grey + (Double(rgb.blue) - grey) * amount))
    }

    private static func mapped(
        _ rgb: (red: UInt8, green: UInt8, blue: UInt8), _ transform: (Double) -> Double
    ) -> Color {
        Color.rgb(
            byte(transform(Double(rgb.red))),
            byte(transform(Double(rgb.green))),
            byte(transform(Double(rgb.blue))))
    }

    /// A channel back into a byte. Clamped, because every one of these can
    /// leave the range and a terminal has no colour outside it.
    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }
}
