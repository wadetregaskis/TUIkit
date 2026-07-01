//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GaugeStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Gauge Style

/// The visual style of a ``Gauge``, mirroring SwiftUI's `GaugeStyle`.
///
/// Apply it with ``SwiftUI/View/gaugeStyle(_:)``, exactly as in SwiftUI:
///
/// ```swift
/// Gauge(value: 0.7) { Text("CPU") }
///     .gaugeStyle(.accessoryCircular)
/// ```
///
/// SwiftUI's `GaugeStyle` is a protocol whose linear/circular shapes are drawn
/// with real geometry. A terminal can't draw arbitrary shapes, so here the
/// style is a fixed set of terminal-native renderings that carry the same
/// names and intent:
///
/// | Style | Terminal rendering |
/// |-------|--------------------|
/// | ``automatic`` / ``linearCapacity`` | A full horizontal bar with bound labels — a shaded meter |
/// | ``accessoryLinear`` | A plain line with a marker at the value (`─────●─────`) — position only, no fill |
/// | ``accessoryLinearCapacity`` | A slim, sub-cell-precise bar filled from the minimum to the value |
/// | ``accessoryCircular`` | A ring dial with a marker at the value's position on the ring |
/// | ``accessoryCircularCapacity`` | A ring dial whose arc fills from the minimum to the value |
/// | ``accessoryCircularTiny`` | A single compact pie glyph (`○◔◑◕●`) — where clarity matters less than size |
///
/// The **capacity** styles are cumulative: they fill the range from the
/// minimum up to the current value. The **non-capacity** styles mark only the
/// value's *position* (a point / a marker on the ring). This mirrors SwiftUI's
/// distinction.
///
/// > Note: A terminal cannot host user-defined gauge geometries, so — unlike
/// > SwiftUI's open protocol — this is a closed set. The call site is identical
/// > (`.gaugeStyle(.accessoryCircular)`), which is what portability relies on.
public enum GaugeStyle: Sendable, Equatable {
    /// The platform-default style. On a terminal this is ``linearCapacity``.
    case automatic

    /// A horizontal bar that fills in proportion to the value, flanked by the
    /// bound labels. The default.
    case linearCapacity

    /// A plain horizontal line with a marker at the current value's position —
    /// no fill (position only).
    case accessoryLinear

    /// A slim horizontal bar filled from the minimum to the current value, with
    /// sub-cell precision (cumulative capacity).
    case accessoryLinearCapacity

    /// A ring dial with a marker at the current value's position on the ring.
    case accessoryCircular

    /// A ring dial whose arc fills from the minimum to the current value
    /// (cumulative capacity).
    case accessoryCircularCapacity

    /// A single compact pie glyph (`○◔◑◕●`) beside the value — for when a
    /// gauge must fit a tight space and exact resolution isn't important.
    case accessoryCircularTiny
}

// MARK: - Environment

private struct GaugeStyleKey: EnvironmentKey {
    static let defaultValue: GaugeStyle = .automatic
}

extension EnvironmentValues {
    /// The style ``Gauge`` views render with. Set via
    /// ``SwiftUI/View/gaugeStyle(_:)``. Default: ``GaugeStyle/automatic``.
    public var gaugeStyle: GaugeStyle {
        get { self[GaugeStyleKey.self] }
        set { self[GaugeStyleKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the style for gauges within this view, mirroring SwiftUI's
    /// `gaugeStyle(_:)`.
    ///
    /// Apply it to a single ``Gauge`` or to a container to style every gauge it
    /// contains:
    ///
    /// ```swift
    /// Gauge(value: load) { Text("Load") }
    ///     .gaugeStyle(.accessoryCircular)
    /// ```
    ///
    /// - Parameter style: The gauge style to apply.
    /// - Returns: A view whose gauges use the specified style.
    public func gaugeStyle(_ style: GaugeStyle) -> some View {
        environment(\.gaugeStyle, style)
    }
}
