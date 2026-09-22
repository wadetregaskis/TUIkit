//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GaugeStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - GaugeStyle Protocol

/// The appearance of a ``Gauge``.
///
/// To configure the style for a single `Gauge` or for every gauge in a view
/// hierarchy, use the ``View/gaugeStyle(_:)`` modifier:
///
/// ```swift
/// Gauge(value: 0.7) { Text("CPU") }
///     .gaugeStyle(.accessoryCircular)
/// ```
///
/// ## Built-in Styles
///
/// SwiftUI's built-in gauges are drawn with real geometry. A terminal can't
/// draw arbitrary shapes, so each of these is a terminal-native rendering that
/// carries the same name and the same intent:
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
/// The first six carry SwiftUI's names and types. ``accessoryCircularTiny`` is
/// a TUI-specific addition with no SwiftUI counterpart — a terminal row is
/// often one line tall, and there the three-row ring does not fit.
///
/// ## Custom styles
///
/// Conform to `GaugeStyle` and implement ``makeBody(configuration:)`` to draw a
/// gauge however you like — a `▁▂▃▄▅▆▇` sparkline cell, an "N of M" readout, a
/// house bar. The built-in styles above don't implement `makeBody`; they render
/// procedurally, through `TrackRenderer` and the ring dial. Only custom styles
/// use it, exactly as with ``ButtonStyle``, ``ToggleStyle`` and ``LabelStyle``.
///
/// ```swift
/// struct BlocksGaugeStyle: GaugeStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         let filled = Int((configuration.value * 5).rounded())
///         return HStack {
///             configuration.label
///             Text(String(repeating: "▰", count: filled)
///                 + String(repeating: "▱", count: 5 - filled))
///         }
///     }
/// }
/// ```
///
/// A custom style draws the whole gauge: the built-in label line and bound
/// labels are the built-in renderings' arrangement, not the gauge's, so whatever
/// of ``GaugeStyleConfiguration``'s five labels a custom body does not place is
/// not drawn. The same goes for ``View/labelsHidden()`` — the built-in styles
/// honour it, and a custom style that wants to reads `\.labelsVisibility` from
/// the environment itself.
///
/// ## Styles and the render cache
///
/// ``View/gaugeStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all — not the gauge alone, but everything
/// under the modifier.
///
/// All seven built-in styles are therefore `Equatable`. None of them holds
/// anything, and the only thing the framework ever reads off a style is
/// `builtInShape`, which is a function of the type and of nothing else — so
/// `==` within a type is vacuously true and two instances of one really do draw
/// the same gauge. Between types it is the downcast in the comparison that
/// answers, and that is what a gauge needs: a swap from a bar to a ring changes
/// the drawing's height as well as its glyphs.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's gauge styles declare no such conformance, and this is one
///   of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol GaugeStyle: Sendable {
    /// A view representing the gauge's appearance.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a gauge.
    ///
    /// - Parameter configuration: The properties of the gauge being styled.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a gauge.
    typealias Configuration = GaugeStyleConfiguration
}

extension GaugeStyle {
    /// Default body for the built-in styles, which TUIkit renders procedurally
    /// rather than through `makeBody`. A custom style overrides it.
    @MainActor public func makeBody(configuration: Configuration) -> EmptyView {
        EmptyView()
    }

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any GaugeStyle` existential so ``makeBody(configuration:)`` can
    /// return its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }

    /// Measures this style's body for `configuration`, opening the existential
    /// the same way ``makeBuffer(configuration:context:)`` does.
    ///
    /// A custom body is an ordinary view, so it is measured as one rather than
    /// rendered and counted — the two-pass layout asks for a size far more often
    /// than it asks for bytes, and measuring by rendering is half a frame
    /// (`Documentation/What makes a page slow to open.md`).
    @MainActor
    func makeSize(
        configuration: Configuration, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(makeBody(configuration: configuration), proposal: proposal, context: context)
    }
}

// MARK: - Configuration

/// The properties of a gauge, passed to a ``GaugeStyle`` so it can produce the
/// gauge's appearance.
///
/// You don't create this — TUIkit builds one per ``Gauge`` and hands it to a
/// custom style's ``GaugeStyle/makeBody(configuration:)``. It carries SwiftUI's
/// five properties under SwiftUI's names.
///
/// - Note: SwiftUI gives each label its own nested type-erasing struct
///   (`GaugeStyleConfiguration.Label` and friends). TUIkit type-erases with
///   ``AnyView``, as ``ToggleStyleConfiguration`` and ``LabelStyleConfiguration``
///   already do — the nested types exist in SwiftUI to hide a view graph node
///   that has no equivalent here, and five more public names would document a
///   distinction that isn't one. A style body places them the same way either
///   way.
public struct GaugeStyleConfiguration {
    /// The current value of the gauge, normalized to `0.0...1.0`.
    ///
    /// ``Gauge`` normalizes against the bounds it was given and clamps, so a
    /// style never has to — and never sees the original units. Same range, and
    /// the same documented range, as SwiftUI's.
    public let value: Double

    /// A view that describes the purpose of the gauge, type-erased.
    public let label: AnyView

    /// A view that describes the current value, or `nil` when the gauge has
    /// none.
    public let currentValueLabel: AnyView?

    /// A view that describes the minimum of the range, or `nil` when the gauge
    /// has none.
    public let minimumValueLabel: AnyView?

    /// A view that describes the maximum of the range, or `nil` when the gauge
    /// has none.
    public let maximumValueLabel: AnyView?

    // Configurations are produced by ``Gauge`` during rendering, never by client
    // code — the compiler-synthesized memberwise initializer (internal access
    // level) is exactly what's needed, and matches SwiftUI, whose
    // `GaugeStyleConfiguration` publishes no initializer either.
}

// MARK: - Built-in Gauge Styles

/// The default gauge style. In TUIkit this draws what ``LinearCapacityGaugeStyle``
/// draws: a shaded horizontal meter.
///
/// `Equatable` for the reason given under ``GaugeStyle``: a memo below a value
/// the render cache cannot compare declines to cache. It holds nothing, so every
/// instance draws the same gauge.
public struct DefaultGaugeStyle: GaugeStyle, Equatable {
    /// Creates the default gauge style.
    public init() {}
}

/// A gauge style that draws a horizontal bar filled in proportion to the value,
/// flanked by the bound labels.
///
/// The bar is a *shaded* meter (`▓`/`░`) — deliberately distinct from
/// ``ProgressView``'s solid blocks and ``Slider``'s knob-on-a-rail, so the three
/// read differently at a glance.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``, and the two draw the
/// same meter, so the worst a comparison between them can do is drop a cache
/// entry that would have been good.
public struct LinearCapacityGaugeStyle: GaugeStyle, Equatable {
    /// Creates a linear-capacity gauge style.
    public init() {}
}

/// A gauge style that draws a plain horizontal line with a marker at the current
/// value's position (`─────●─────`) — no fill.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``.
public struct AccessoryLinearGaugeStyle: GaugeStyle, Equatable {
    /// Creates an accessory-linear gauge style.
    public init() {}
}

/// A gauge style that draws a slim horizontal bar filled from the minimum to the
/// current value, with sub-cell precision.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``.
public struct AccessoryLinearCapacityGaugeStyle: GaugeStyle, Equatable {
    /// Creates an accessory-linear-capacity gauge style.
    public init() {}
}

/// A gauge style that draws a ring dial with a marker at the current value's
/// position on the ring.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``, and this is one of the
/// types that earns the cross-type comparison: a ring is three rows where a bar
/// is one, so a swap between them changes the gauge's height and must read as a
/// change.
public struct AccessoryCircularGaugeStyle: GaugeStyle, Equatable {
    /// Creates an accessory-circular gauge style.
    public init() {}
}

/// A gauge style that draws a ring dial whose arc fills from the minimum to the
/// current value.
///
/// `Equatable` on the same terms as ``AccessoryCircularGaugeStyle``.
public struct AccessoryCircularCapacityGaugeStyle: GaugeStyle, Equatable {
    /// Creates an accessory-circular-capacity gauge style.
    public init() {}
}

/// A gauge style that draws a single compact pie glyph (`○◔◑◕●`) beside the
/// value — for when a gauge must fit a tight space and exact resolution isn't
/// important.
///
/// TUI-specific: SwiftUI has no counterpart, because the constraint it answers is
/// a terminal's. The ring dial is three rows tall, and a gauge inside a list row
/// or a status line has one.
///
/// `Equatable` on the same terms as ``DefaultGaugeStyle``.
public struct AccessoryCircularTinyGaugeStyle: GaugeStyle, Equatable {
    /// Creates an accessory-circular-tiny gauge style.
    public init() {}
}

// MARK: - GaugeStyle Static Accessors

extension GaugeStyle where Self == DefaultGaugeStyle {
    /// The default gauge style. On a terminal this draws
    /// ``GaugeStyle/linearCapacity``.
    public static var automatic: DefaultGaugeStyle { DefaultGaugeStyle() }
}

extension GaugeStyle where Self == LinearCapacityGaugeStyle {
    /// A gauge style that draws a bar filled in proportion to the value, flanked
    /// by the bound labels.
    public static var linearCapacity: LinearCapacityGaugeStyle { LinearCapacityGaugeStyle() }
}

extension GaugeStyle where Self == AccessoryLinearGaugeStyle {
    /// A gauge style that marks the value's position on a plain line.
    public static var accessoryLinear: AccessoryLinearGaugeStyle { AccessoryLinearGaugeStyle() }
}

extension GaugeStyle where Self == AccessoryLinearCapacityGaugeStyle {
    /// A gauge style that draws a slim, sub-cell-precise bar filled from the
    /// minimum to the value.
    public static var accessoryLinearCapacity: AccessoryLinearCapacityGaugeStyle {
        AccessoryLinearCapacityGaugeStyle()
    }
}

extension GaugeStyle where Self == AccessoryCircularGaugeStyle {
    /// A gauge style that marks the value's position on a ring dial.
    public static var accessoryCircular: AccessoryCircularGaugeStyle { AccessoryCircularGaugeStyle() }
}

extension GaugeStyle where Self == AccessoryCircularCapacityGaugeStyle {
    /// A gauge style whose ring dial fills from the minimum to the value.
    public static var accessoryCircularCapacity: AccessoryCircularCapacityGaugeStyle {
        AccessoryCircularCapacityGaugeStyle()
    }
}

extension GaugeStyle where Self == AccessoryCircularTinyGaugeStyle {
    /// A gauge style that draws a single compact pie glyph beside the value.
    ///
    /// > Note: TUI-specific — SwiftUI has no `accessoryCircularTiny`.
    public static var accessoryCircularTiny: AccessoryCircularTinyGaugeStyle {
        AccessoryCircularTinyGaugeStyle()
    }
}

// MARK: - GaugeStyle Resolution

/// Which terminal rendering a built-in ``GaugeStyle`` draws.
///
/// One answer rather than a chain of `is` tests at each decision, because a
/// gauge asks four questions of its style — bar or dial, which track glyphs,
/// ring or pie, fill or mark — and each of measure and render asks them. Answered
/// in one place, adding a style is one case here; answered where each is asked,
/// it is four edits that can disagree, and the two passes disagreeing about the
/// shape is exactly the measure/render divergence `_GaugeCore` already keeps one
/// function per rule to prevent.
enum GaugeShape: Equatable {
    /// A horizontal bar, drawn with the given track glyphs.
    case linear(TrackStyle)

    /// The ring dial. `capacity` fills the arc from the minimum to the value;
    /// otherwise a single bright cell marks the value's position.
    case ring(capacity: Bool)

    /// The single pie glyph beside the value.
    case tinyDial
}

extension GaugeStyle {
    /// The terminal rendering this style draws, or `nil` for a custom style —
    /// which draws through ``makeBody(configuration:)`` instead.
    var builtInShape: GaugeShape? {
        switch self {
        case is DefaultGaugeStyle, is LinearCapacityGaugeStyle: .linear(.shade)
        case is AccessoryLinearGaugeStyle: .linear(.marker)  // position only, no fill
        case is AccessoryLinearCapacityGaugeStyle: .linear(.blockFine)  // min→value, sub-cell
        case is AccessoryCircularGaugeStyle: .ring(capacity: false)
        case is AccessoryCircularCapacityGaugeStyle: .ring(capacity: true)
        case is AccessoryCircularTinyGaugeStyle: .tinyDial
        default: nil
        }
    }
}

// MARK: - Environment

/// Environment key for the gauge style.
private struct GaugeStyleKey: EnvironmentKey {
    static let defaultValue: any GaugeStyle = DefaultGaugeStyle()
}

extension EnvironmentValues {
    /// The style ``Gauge`` views render with. Set via ``View/gaugeStyle(_:)``.
    /// Default: ``DefaultGaugeStyle``.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``GaugeStyle``.
    public var gaugeStyle: any GaugeStyle {
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
    public func gaugeStyle<S: GaugeStyle>(_ style: S) -> some View {
        environment(\.gaugeStyle, style)
    }
}
