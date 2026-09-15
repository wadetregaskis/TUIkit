//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Indeterminate Style

/// The visual style of an indeterminate progress animation.
///
/// `IndeterminateStyle` only governs the animation that plays when a
/// ``ProgressView`` has *no* known progress fraction. Determinate style —
/// the look of a partially-filled bar — is controlled separately by
/// ``TrackStyle``.
///
/// ## Sweep (default)
///
/// ```
/// ░░▒▓██▓▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
///        ↑ accent fades back into the empty track
/// ```
///
/// ## Barber pole
///
/// ```
/// ◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤
/// ```
///
/// The pattern shifts one cell to the left each step, in stripes one `◢◤`
/// wide that alternate the accent and filled colours, creating the classic
/// two-tone "candy stripe" motion.
///
/// ## Pulse
///
/// The whole bar fades smoothly between dim and bright accent.
///
/// ## Knight Rider
///
/// A single bright block bounces left-right with a fading trail behind it.
///
/// ## Gradient
///
/// A coloured gradient slides continuously to the right — like the
/// `sweep` highlight but spanning the full track, with no empty segment.
public enum IndeterminateStyle: Sendable, Equatable {
    /// A bright segment with a fading trail sweeps continuously across
    /// the track. The default.
    case sweep

    /// `◢◤` triangle pattern in two-tone stripes, shifted left one cell per
    /// step — the classic "barber pole" candy-stripe motion.
    case barberPole

    /// The whole bar fades between dim and bright accent.
    case pulse

    /// A single bright block bounces left-and-right with a short fading
    /// trail behind it.
    case knightRider

    /// A smoothly-coloured gradient slides continuously across the whole
    /// track.
    ///
    /// `colors` supplies custom gradient stops (at least two, cyclically
    /// wrapped so the scroll is seamless); `nil` — and the bare `.gradient`
    /// spelling — uses the palette's error, warning, success, info and accent
    /// colours, so the bar follows the theme. The same stop model as
    /// ``TrackConfiguration/fillGradient`` and
    /// ``SegmentColoring/gradient(_:)``.
    case gradient(_ gradient: Gradient? = nil)

    /// A hand-rolled recipe: any motion, drawn with any glyphs, in any
    /// colours, at any speed.
    ///
    /// The twin of ``TrackStyle/custom(_:)``. Every case above is a preset of
    /// the same type, so this adds no second renderer — see
    /// ``IndeterminateConfiguration``.
    case custom(IndeterminateConfiguration)
}

extension IndeterminateStyle {
    /// The recipe this style names.
    ///
    /// The named cases exist because they are the ones worth naming, not
    /// because they are made of anything else: each is a preset, and this is
    /// where the two spellings meet so that nothing downstream has to know
    /// which one it was given.
    public var configuration: IndeterminateConfiguration {
        switch self {
        case .sweep: .sweep
        case .barberPole: .barberPole
        case .pulse: .pulse
        case .knightRider: .knightRider
        case .gradient(let gradient): .gradient(gradient)
        case .custom(let configuration): configuration
        }
    }
}

// MARK: - Environment Key

/// Environment key for the default indeterminate progress animation.
private struct IndeterminateStyleKey: EnvironmentKey {
    static let defaultValue: IndeterminateStyle = .sweep
}

extension EnvironmentValues {
    /// The default indeterminate-progress animation used by ``ProgressView``.
    ///
    /// Read at draw time by ``ProgressView`` whenever it lacks a known
    /// fraction. Override per-view with ``View/indeterminateStyle(_:)``,
    /// or set at the app/scene level with
    /// `.environment(\.indeterminateStyle, …)`.
    public var indeterminateStyle: IndeterminateStyle {
        get { self[IndeterminateStyleKey.self] }
        set { self[IndeterminateStyleKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Sets the indeterminate-progress animation used by descendant
    /// ``ProgressView``s that have no known fraction.
    ///
    /// Equivalent to `.environment(\.indeterminateStyle, style)`.
    ///
    /// - Parameter style: The animation to use.
    /// - Returns: A view that publishes the chosen style to its
    ///   descendants.
    public func indeterminateStyle(_ style: IndeterminateStyle) -> some View {
        environment(\.indeterminateStyle, style)
    }
}
