//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackGradientScaling.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Scaling

/// What a track's fill gradient is measured across — the whole bar, or the part
/// of it that is filled.
///
/// A gradient on a `Slider`, `ProgressView` or `Gauge` can mean two different
/// things, and only the caller knows which:
///
/// - a **scale**, where each colour marks a value ("red past 80%"), which wants
///   the ramp pinned to the bar so a colour always means the same number; or
/// - a **decoration** on the fill itself, which wants the ramp to span whatever
///   is lit and so to move as the value does.
///
/// TUI-specific: SwiftUI's `Gauge` takes a `gradient:` and always spans the
/// whole scale, having no notion of the second reading.
public enum TrackGradientScaling: Sendable, Equatable, CaseIterable {
    /// The gradient spans the **whole bar**; filling reveals more of it, and a
    /// given colour always sits at the same value. The default.
    case track

    /// The gradient spans the **filled part**, so the ramp compresses and
    /// stretches as the value changes — the last lit cell is always the last
    /// colour.
    case fill
}

// MARK: - Environment

private struct TrackGradientScalingKey: EnvironmentKey {
    static let defaultValue = TrackGradientScaling.track
}

extension EnvironmentValues {
    /// What a track's fill gradient is measured across. See
    /// ``TUIkit/View/trackGradientScaling(_:)``.
    public var trackGradientScaling: TrackGradientScaling {
        get { self[TrackGradientScalingKey.self] }
        set { self[TrackGradientScalingKey.self] = newValue }
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
    /// - Parameter scaling: ``TrackGradientScaling/track`` (the default) to pin
    ///   the ramp to the bar, or ``TrackGradientScaling/fill`` to compress it
    ///   into the filled part.
    public func trackGradientScaling(_ scaling: TrackGradientScaling) -> some View {
        environment(\.trackGradientScaling, scaling)
    }
}
