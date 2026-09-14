//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RefreshIndicatorEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Refresh indicator

/// The spinner a ``TUIkit/View/refreshable(action:)`` draws while its action runs.
///
/// TUI-specific: SwiftUI's pull-to-refresh spinner is not configurable, but its
/// look there is a platform given, whereas here a "spinner" is a handful of
/// glyphs whose legibility depends entirely on the terminal's font. `.dots`
/// (Braille) is the default because it animates in one cell and reads well
/// nearly everywhere — but a font without Braille coverage renders it as boxes,
/// and then an app wants `.line`, which is pure ASCII.
///
/// Carried in the environment rather than as a `refreshable` parameter for the
/// reason the modifier-first principle exists: this is an appearance choice that
/// should be settable once for a whole screen, and `refreshable`'s signature has
/// to stay SwiftUI's.
public struct RefreshIndicator: Sendable, Equatable {
    /// The animation style to draw.
    public var style: SpinnerStyle

    /// The colour to draw it in, or `nil` for the palette's accent.
    public var color: Color?

    /// Creates a refresh indicator description.
    ///
    /// - Parameters:
    ///   - style: The spinner animation style.
    ///   - color: The colour, or `nil` for the palette accent.
    public init(style: SpinnerStyle = .dots, color: Color? = nil) {
        self.style = style
        self.color = color
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // `SpinnerStyle` carries a custom-frames case, so compare what is drawn
        // rather than requiring the enum itself to be Equatable. The interval as
        // well as the frames: `.custom` with `.dots`' frames still steps at 120 ms,
        // not 110.
        lhs.style.frames == rhs.style.frames && lhs.style.interval == rhs.style.interval
            && lhs.color == rhs.color
    }
}

private struct RefreshIndicatorKey: EnvironmentKey {
    static let defaultValue = RefreshIndicator()
}

extension EnvironmentValues {
    /// The spinner drawn while a `.refreshable` action runs.
    public var refreshIndicator: RefreshIndicator {
        get { self[RefreshIndicatorKey.self] }
        set { self[RefreshIndicatorKey.self] = newValue }
    }
}

extension View {
    /// Chooses the spinner drawn while a ``TUIkit/View/refreshable(action:)``
    /// action runs, for every refreshable in this subtree.
    ///
    /// The indicator is drawn with one blank cell either side, so it reads as a
    /// badge over the content rather than colliding with the character next to
    /// it — bear that in mind when picking a wide style. It OVERLAYS the top row
    /// rather than insetting it, and `.overlay` sizes to the larger of the two,
    /// so a multi-cell style (`.bouncing`) can widen content narrower
    /// than the indicator for as long as a refresh is in flight. One-cell styles
    /// (`.dots`, `.line`, `.pie`, …) never can.
    ///
    /// ```swift
    /// List(items) { … }
    ///     .refreshable { await reload() }
    ///     .refreshIndicator(style: .line)   // ASCII, for fonts without Braille
    /// ```
    ///
    /// - Parameters:
    ///   - style: The spinner animation style (default: `.dots`).
    ///   - color: The colour to draw it in, or `nil` for the palette accent.
    /// - Returns: A view whose refreshables use that indicator.
    public func refreshIndicator(
        style: SpinnerStyle = .dots,
        color: Color? = nil
    ) -> some View {
        environment(\.refreshIndicator, RefreshIndicator(style: style, color: color))
    }
}
