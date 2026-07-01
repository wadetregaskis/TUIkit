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
/// | ``accessoryLinear`` | A slim line with a marker at the value |
/// | ``accessoryLinearCapacity`` | A slim, sub-cell-precise capacity bar |
/// | ``accessoryCircular`` | A compact pie dial (`○◔◑◕●`) beside the value |
/// | ``accessoryCircularCapacity`` | A compact pie dial with the value leading |
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

    /// A slim horizontal line with a marker at the current value.
    case accessoryLinear

    /// A slim horizontal bar that fills to the current value, with sub-cell
    /// precision.
    case accessoryLinearCapacity

    /// A compact circular dial (a pie glyph) beside the current value.
    case accessoryCircular

    /// A compact circular dial with the current value leading the dial.
    case accessoryCircularCapacity
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
