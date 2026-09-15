//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyleGradientResolution.swift
//
//  Resolving the colours a control style carries, before anything paints them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Why this exists

//  A `Color` may name a palette ROLE — `.accentColor`, `.primary`, an app's own
//  `Palette` slot — and a role has no channels until there is a palette to look
//  it up in. Ink is emitted from channels, so `Color.foregroundCodes()` traps on
//  an unresolved one rather than guess.
//
//  For a style handed to `.foregroundStyle(_:)` or `.background(_:)` the resolve
//  happens in `ShapeStyle.paint(in:)`, which is the first moment the palette is
//  known. The control styles below never go through it: a `TrackStyle` or an
//  `IndeterminateStyle` is read straight out of the environment by the control
//  that draws it, so the resolve belongs at the renderer's door instead — which
//  is where these are called, once per render, rather than at each of the seven
//  call sites that would otherwise each have to remember.

// MARK: - Tracks

extension TrackConfiguration {
    /// This configuration with every colour and gradient stop resolved.
    func resolvingColours(with palette: any Palette) -> Self {
        var resolved = self
        resolved.fillGradient = fillGradient?.resolvingStops(with: palette)
        resolved.backgroundGradient = backgroundGradient?.resolvingStops(with: palette)
        resolved.backgroundColor = backgroundColor?.resolve(with: palette)
        return resolved
    }
}

extension SegmentColoring {
    /// This colouring with every colour resolved.
    func resolvingColours(with palette: any Palette) -> Self {
        switch self {
        case .automatic: .automatic
        case .solid(let colour): .solid(colour.resolve(with: palette))
        case .perSegment(let leading, let middle, let trailing):
            .perSegment(
                leading: leading.resolve(with: palette),
                middle: middle.resolve(with: palette),
                trailing: trailing.resolve(with: palette))
        case .gradient(let ramp): .gradient(ramp.resolvingStops(with: palette))
        }
    }
}

extension TrackStyle {
    /// This style with every colour and gradient stop resolved.
    ///
    /// The cases with no colour of their own return themselves — they draw in
    /// the filled/empty/accent colours the control passes separately, and those
    /// are resolved by the control.
    func resolvingColours(with palette: any Palette) -> Self {
        switch self {
        case .shadeRamp(let ramp):
            .shadeRamp(gradient: ramp?.resolvingStops(with: palette))
        case .threeSegment(let leading, let middle, let trailing, let backgroundPattern, let coloring):
            .threeSegment(
                leading: leading, middle: middle, trailing: trailing, backgroundPattern: backgroundPattern,
                coloring: coloring.resolvingColours(with: palette))
        case .custom(let configuration):
            .custom(configuration.resolvingColours(with: palette))
        default: self
        }
    }
}

// MARK: - Indeterminate motion

extension IndeterminateConfiguration {
    /// This configuration with its gradient's stops resolved, and for the
    /// ``IndeterminateConfiguration/Motion/gradient`` motion, the palette's default
    /// stops (`IndeterminateRenderer.defaultGradient(in:)`) in place of `nil` or of
    /// a gradient with fewer than two usable stops.
    ///
    /// The default is filled in HERE, the one door the renderer, the opacity check
    /// and `ProgressView`'s kept cycle all come through, rather than where the ramp
    /// is sampled, so every cache in front of the bar sees the stops. A `nil` left
    /// in the configuration looks the same under every palette: the kept cycle was
    /// served, and a picture terminal's pictures reused (their signature holds the
    /// configuration), after the palette's roles had changed.
    func resolvingColours(with palette: any Palette) -> Self {
        var resolved = self
        resolved.gradient = gradient?.resolvingStops(with: palette)
        if motion == .gradient,
            resolved.gradient.map({ IndeterminateRenderer.resolvable(in: $0).count < 2 }) ?? true
        {
            resolved.gradient = IndeterminateRenderer.defaultGradient(in: palette)
        }
        return resolved
    }
}
