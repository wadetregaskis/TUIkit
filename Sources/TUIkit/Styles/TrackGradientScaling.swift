//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackGradientScaling.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Scaling

/// What a track's gradient is measured across — the whole bar, or only the
/// region of it that the gradient paints.
///
/// A gradient on a `Slider`, `ProgressView` or `Gauge` can mean two different
/// things, and only the caller knows which:
///
/// - a **scale**, where each colour marks a value ("red past 80%"), which wants
///   the ramp pinned to the bar so a colour always means the same number; or
/// - a **decoration** on the region itself, which wants the ramp to span
///   whatever it paints and so to move as the value does.
///
/// A bar has two regions a gradient can paint — the fill and the background —
/// and each is answered on its own: the fill's ramp may be a scale while the
/// background's is a decoration, or the other way round. See
/// ``TUIkit/View/trackGradientScaling(fill:background:)``.
///
/// TUI-specific: SwiftUI's `Gauge` has no gradient parameter — it is coloured
/// with `tint(_:)` — and SwiftUI has no notion of what a track's ramp spans.
public enum TrackGradientScaling: Sendable, Equatable, CaseIterable {
    /// The gradient spans the **whole bar**; the region it paints reveals its
    /// share of it, and a given colour always sits at the same value. The
    /// default.
    case track

    /// The gradient spans only the **region it paints** — the filled cells for
    /// the fill's ramp, the background cells for the background's — so the ramp
    /// compresses and stretches as the value changes, and the region's last
    /// cell is always the ramp's last colour.
    case region
}

// MARK: - Environment

private struct TrackGradientScalingKey: EnvironmentKey {
    static let defaultValue = TrackGradientScaling.track
}

private struct TrackBackgroundGradientScalingKey: EnvironmentKey {
    static let defaultValue = TrackGradientScaling.track
}

extension EnvironmentValues {
    /// What a track's **fill** gradient is measured across. See
    /// ``TUIkit/View/trackGradientScaling(_:)``.
    public var trackGradientScaling: TrackGradientScaling {
        get { self[TrackGradientScalingKey.self] }
        set { self[TrackGradientScalingKey.self] = newValue }
    }

    /// What a track's **background** gradient is measured across — the ramp a
    /// `TrackConfiguration.backgroundGradient` lays over the cells the fill has
    /// not reached. See ``TUIkit/View/trackGradientScaling(fill:background:)``.
    public var trackBackgroundGradientScaling: TrackGradientScaling {
        get { self[TrackBackgroundGradientScalingKey.self] }
        set { self[TrackBackgroundGradientScalingKey.self] = newValue }
    }
}

extension View {
    /// Sets whether a gradient-filled track's ramp spans the whole bar or only
    /// the region it paints, for every `Slider`, `ProgressView` and `Gauge` in
    /// this view.
    ///
    /// ```swift
    /// ProgressView(value: load)
    ///     .progressViewStyle(.shadeRamp(gradient: [.green, .yellow, .red]))
    ///     .trackGradientScaling(.track)   // red always means "near full"
    /// ```
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    ///
    /// Both of a bar's ramps follow this — the fill's and the background's. To
    /// answer the two separately, use
    /// ``trackGradientScaling(fill:background:)``.
    ///
    /// - Parameter scaling: ``TrackGradientScaling/track`` (the default) to pin
    ///   the ramps to the bar, or ``TrackGradientScaling/region`` to compress
    ///   each into the region it paints.
    public func trackGradientScaling(_ scaling: TrackGradientScaling) -> some View {
        trackGradientScaling(fill: scaling, background: scaling)
    }

    /// Sets what each of a bar's two ramps is measured across — the fill's
    /// and the background's — for every `Slider`, `ProgressView` and `Gauge`
    /// in this view.
    ///
    /// The two are separate questions. A fill ramp that is a scale ("red past
    /// 80%") wants the bar, while the cool ramp behind it may be pure
    /// decoration and want only the cells it paints:
    ///
    /// ```swift
    /// ProgressView(value: load)
    ///     .progressViewStyle(.custom(configuration))  // a fill ramp and a background one
    ///     .trackGradientScaling(fill: .track, background: .region)
    /// ```
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    ///
    /// - Parameters:
    ///   - fill: What the fill's ramp spans.
    ///   - background: What the background's ramp spans.
    public func trackGradientScaling(
        fill: TrackGradientScaling, background: TrackGradientScaling
    ) -> some View {
        // `background` shadows `View.background(_:)` in this body; it is only
        // ever the parameter here.
        environment(\.trackGradientScaling, fill)
            .environment(\.trackBackgroundGradientScaling, background)
    }
}
