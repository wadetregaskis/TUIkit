//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButtonGroupEdgeBehavior.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - RadioButtonGroupEdgeBehavior

/// What pressing an on-axis arrow key *past* a ``RadioButtonGroup``'s first or
/// last item does.
///
/// The movement axis is the group's own orientation (Up/Down for a vertical
/// group, Left/Right for a horizontal one). A *cross-axis* arrow — Up/Down on a
/// horizontal group, say — always relinquishes focus regardless of this policy,
/// because a single-axis group has nowhere to move that way; that is the only
/// way to leave a horizontal group by arrow. This policy governs only the
/// on-axis edges.
///
/// TUI-specific: SwiftUI has no direct equivalent (its radio groups are
/// `Picker`s, navigated as a unit).
public enum RadioButtonGroupEdgeBehavior: Sendable, Hashable {
    /// Stay on the edge item — the arrow is consumed and focus does not leave
    /// the group. Tab / Shift-Tab still move focus out. **The default**, and
    /// consistent with how ``List`` and ``Table`` contain their arrow keys:
    /// keyboard travel through a group is deliberate, and you never fall out of
    /// it by overshooting — which matters most inside a `ScrollView`, where the
    /// end of the group may be scrolled out of view.
    case contain

    /// Relinquish focus to the next focusable control in that direction, like
    /// Tab — so arrowing flows straight out of the group and on through a form.
    /// (This was the pre-2026-07 default.)
    case escape

    /// Wrap around to the opposite end of the *same* group (Up on the first
    /// item → the last item), the classic single-group cycling behaviour.
    case wrap
}

private struct RadioButtonGroupEdgeBehaviorKey: EnvironmentKey {
    static let defaultValue = RadioButtonGroupEdgeBehavior.contain
}

extension EnvironmentValues {
    /// How arrowing past a ``RadioButtonGroup``'s first/last item behaves — see
    /// ``RadioButtonGroupEdgeBehavior``. Defaults to
    /// ``RadioButtonGroupEdgeBehavior/contain``.
    ///
    /// Set with ``View/radioButtonGroupEdgeBehavior(_:)``.
    public var radioButtonGroupEdgeBehavior: RadioButtonGroupEdgeBehavior {
        get { self[RadioButtonGroupEdgeBehaviorKey.self] }
        set { self[RadioButtonGroupEdgeBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Controls what pressing an on-axis arrow key *past* a
    /// ``RadioButtonGroup``'s first or last item does — see
    /// ``RadioButtonGroupEdgeBehavior``.
    ///
    /// ```swift
    /// RadioButtonGroup(selection: $choice) { … }
    ///     .radioButtonGroupEdgeBehavior(.escape)  // arrow out of the group
    /// ```
    ///
    /// By default (``RadioButtonGroupEdgeBehavior/contain``) focus stays inside
    /// the group at its edges, like ``List`` / ``Table``; use Tab to leave.
    ///
    /// TUI-specific — SwiftUI has no direct equivalent.
    public func radioButtonGroupEdgeBehavior(
        _ behavior: RadioButtonGroupEdgeBehavior
    ) -> some View {
        environment(\.radioButtonGroupEdgeBehavior, behavior)
    }
}
