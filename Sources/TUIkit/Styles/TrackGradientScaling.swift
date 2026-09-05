//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackGradientScaling.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Scaling

/// What a track's gradient is measured across — the whole bar, or only the
/// part of it that the gradient paints.
///
/// A gradient on a `Slider`, `ProgressView` or `Gauge` can mean two different
/// things, and only the caller knows which:
///
/// - a **scale**, where each colour marks a value ("red past 80%"), which wants
///   the ramp pinned to the bar so a colour always means the same number; or
/// - a **decoration** on the part itself, which wants the ramp to span whatever
///   it paints and so to move as the value does.
///
/// A bar has two parts a gradient can paint — the fill and the unfilled
/// remainder — and each is answered on its own: the fill's ramp may be a
/// scale while the remainder's is a decoration, or the other way round. See
/// ``TUIkit/View/trackGradientScaling(fill:empty:)``.
///
/// TUI-specific: SwiftUI's `Gauge` takes a `gradient:` and always spans the
/// whole scale, having no notion of the second reading.
public enum TrackGradientScaling: Sendable, Equatable, CaseIterable {
    /// The gradient spans the **whole bar**; the part it paints reveals its
    /// share of it, and a given colour always sits at the same value. The
    /// default.
    case track

    /// The gradient spans the **part it paints** — the filled cells for the
    /// fill's ramp, the unfilled ones for the remainder's — so the ramp
    /// compresses and stretches as the value changes, and the part's last
    /// cell is always the ramp's last colour.
    case fill
}

// MARK: - Environment

private struct TrackGradientScalingKey: EnvironmentKey {
    static let defaultValue = TrackGradientScaling.track
}

private struct TrackEmptyGradientScalingKey: EnvironmentKey {
    static let defaultValue = TrackGradientScaling.track
}

extension EnvironmentValues {
    /// What a track's **fill** gradient is measured across. See
    /// ``TUIkit/View/trackGradientScaling(_:)``.
    public var trackGradientScaling: TrackGradientScaling {
        get { self[TrackGradientScalingKey.self] }
        set { self[TrackGradientScalingKey.self] = newValue }
    }

    /// What a track's **unfilled** gradient is measured across — the ramp a
    /// `TrackConfiguration.emptyGradient` lays over the cells the fill has
    /// not reached. See ``TUIkit/View/trackGradientScaling(fill:empty:)``.
    public var trackEmptyGradientScaling: TrackGradientScaling {
        get { self[TrackEmptyGradientScalingKey.self] }
        set { self[TrackEmptyGradientScalingKey.self] = newValue }
    }
}

extension View {
    /// Sets whether a gradient-filled track's ramp spans the whole bar or only
    /// the filled part, for every `Slider`, `ProgressView` and `Gauge` in this
    /// view.
    ///
    /// ```swift
    /// ProgressView(value: load)
    ///     .trackStyle(.shadeRamp(gradient: [.green, .yellow, .red]))
    ///     .trackGradientScaling(.track)   // red always means "near full"
    /// ```
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    ///
    /// Both of a bar's ramps follow this — the fill's and the unfilled
    /// remainder's. To answer the two separately, use
    /// ``trackGradientScaling(fill:empty:)``.
    ///
    /// - Parameter scaling: ``TrackGradientScaling/track`` (the default) to pin
    ///   the ramps to the bar, or ``TrackGradientScaling/fill`` to compress
    ///   each into the part it paints.
    public func trackGradientScaling(_ scaling: TrackGradientScaling) -> some View {
        trackGradientScaling(fill: scaling, empty: scaling)
    }

    /// Sets what each of a bar's two ramps is measured across — the fill's
    /// and the unfilled remainder's — for every `Slider`, `ProgressView` and
    /// `Gauge` in this view.
    ///
    /// The two are separate questions. A fill ramp that is a scale ("red past
    /// 80%") wants the bar, while the cool ramp behind it may be pure
    /// decoration and want only the cells it paints:
    ///
    /// ```swift
    /// ProgressView(value: load)
    ///     .trackStyle(.custom(configuration))   // a fill gradient and an empty one
    ///     .trackGradientScaling(fill: .track, empty: .fill)
    /// ```
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    ///
    /// - Parameters:
    ///   - fill: What the fill's ramp spans.
    ///   - empty: What the unfilled remainder's ramp spans.
    public func trackGradientScaling(
        fill: TrackGradientScaling, empty: TrackGradientScaling
    ) -> some View {
        environment(\.trackGradientScaling, fill)
            .environment(\.trackEmptyGradientScaling, empty)
    }
}
