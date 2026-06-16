//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SliderValueLabelEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Environment Key

/// Environment key for whether a ``Slider`` draws its trailing value read-out.
private struct SliderShowsValueKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether ``Slider`` draws its trailing `NN%` value read-out (default
    /// `true`). Set with `.sliderShowsValue(_:)` — useful when a surrounding
    /// control already shows (or lets you edit) the value, so the slider is just
    /// the track.
    public var sliderShowsValue: Bool {
        get { self[SliderShowsValueKey.self] }
        set { self[SliderShowsValueKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Shows or hides the trailing value read-out on sliders within this view.
    ///
    /// ```swift
    /// Slider(value: $v, in: 0...255)
    ///     .sliderShowsValue(false)   // just the track — the value is shown elsewhere
    /// ```
    ///
    /// - Parameter shows: Whether the slider draws its `NN%` read-out.
    /// - Returns: A view with the preference applied to its sliders.
    public func sliderShowsValue(_ shows: Bool) -> some View {
        environment(\.sliderShowsValue, shows)
    }
}
