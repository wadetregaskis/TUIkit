//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ShiftStepMultiplier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Environment key

private struct ShiftStepMultiplierKey: EnvironmentKey {
    // 5× by default: holding Shift while pressing an arrow (or a Stepper's ±)
    // takes five base steps at once. The base step stays one unit, so existing
    // un-Shifted behaviour is unchanged.
    static let defaultValue = 5
}

extension EnvironmentValues {
    /// How many base steps an interaction takes per key press while **Shift** is
    /// held — the shared accelerator for arrow-key scrolling (``ScrollView``),
    /// focus-cursor movement (``List``, ``Table``), and value stepping
    /// (``Stepper``, ``Slider``). A base, un-Shifted step is always one unit;
    /// Shift multiplies it by this. Defaults to `5`, and is clamped to at least 1.
    ///
    /// Set it for a whole subtree with ``View/shiftStepMultiplier(_:)``.
    public var shiftStepMultiplier: Int {
        get { self[ShiftStepMultiplierKey.self] }
        set { self[ShiftStepMultiplierKey.self] = max(1, newValue) }
    }
}

// MARK: - Modifier

extension View {
    /// Sets how many base steps a **Shift**-accelerated key press takes for
    /// scrolling, focus-cursor movement, and value stepping within this subtree.
    ///
    /// Holding Shift while pressing an arrow (or a ``Stepper``'s ±) multiplies the
    /// usual one-unit step by `factor` — so `.shiftStepMultiplier(10)` makes
    /// Shift+Down scroll ten lines, move a list cursor ten rows, or add ten to a
    /// stepper at once. Like any environment value it cascades to every
    /// descendant, so applying it once near the root configures the whole
    /// hierarchy below. `factor` is clamped to at least 1.
    ///
    /// This is a terminal-specific affordance (there is no SwiftUI equivalent),
    /// kept as a modifier so it propagates the way styling and other environment
    /// values do.
    public func shiftStepMultiplier(_ factor: Int) -> some View {
        environment(\.shiftStepMultiplier, factor)
    }
}
