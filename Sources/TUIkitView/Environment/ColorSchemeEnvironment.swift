//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorSchemeEnvironment.swift
//
//  Reading the colour scheme from the environment, and pinning one for a subtree.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - The Pin

/// Environment key for a scheme a view PINNED, as opposed to the one the palette
/// in force reads.
///
/// Kept beside the palette rather than in it: the palette a subtree draws with is
/// rewritten from under a pin by every `.palette(_:)`, `.tint(_:)` and theme
/// below it, and the pin has to outlive each of those.
private struct ColorSchemePinKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    /// Whether this subtree is drawn light or dark.
    ///
    /// ```swift
    /// @Environment(\.colorScheme) private var colorScheme
    /// ```
    ///
    /// Reading it asks the ``palette``: the page it paints where that can be
    /// measured, what the terminal reported about its own colours where the
    /// palette leaves the page to the terminal, and ``ColorScheme/light`` where
    /// nothing said anything.
    ///
    /// Writing it pins the scheme for the subtree, as SwiftUI's does:
    ///
    /// ```swift
    /// Preview().environment(\.colorScheme, .light)
    /// ```
    ///
    /// The pin survives a `.palette(_:)` or `.tint(_:)` written *inside* it,
    /// because it is re-applied wherever a palette enters the environment. It does
    /// not reach chrome drawn outside the content — the status bar, the app header
    /// and a modal's backdrop render against the app's root palette — for the same
    /// reason a SwiftUI subview's pin does not reach its window.
    public var colorScheme: ColorScheme {
        get { palette.colorScheme }
        set {
            self[ColorSchemePinKey.self] = newValue
            // Writing the palette back through its OWN setter is what puts the new
            // pin in force. NOT the no-op assignment it reads as: the getter hands
            // back what is stored and the setter re-wraps it (see `palette`). It
            // also keeps one answer rather than two that could disagree — every
            // reader asks the palette, pinned or not.
            let current = palette
            palette = current
        }
    }

    /// `palette` stating the pinned scheme, where a view pinned one and it differs
    /// from what `palette` reads on its own.
    ///
    /// Internal rather than private because ``palette``'s setter is what applies
    /// it, and that lives beside the grounding it follows; the KEY stays private
    /// to this file.
    func schemed(_ palette: any Palette) -> any Palette {
        guard let pin = self[ColorSchemePinKey.self] else { return palette }
        return SchemedPalette.palette(palette, stating: pin)
    }
}

// MARK: - The Wrapper

/// A palette that states a colour scheme its base does not, and changes nothing
/// else.
///
/// Every role is forwarded, and every one has to be: `Palette`'s protocol defaults
/// are *collapsing*, so a role left without a witness here does not fall through
/// to `base` — it is recomputed from this palette's other roles. That is the trap
/// `TintedPalette` documents from experience, and for ``Palette/colorScheme`` it
/// is the whole point of the type: an unstated scheme would be read back off the
/// page, which is exactly what the pin is overriding.
package struct SchemedPalette: DerivedPalette {
    package let base: any Palette

    package let colorScheme: ColorScheme

    /// `palette` stating `scheme`, wrapped only where it does not already.
    ///
    /// Idempotent, and it has to be: `.tint(_:)` and a theme write the palette on
    /// every visit of every subtree they cover, on the measure walk and the render
    /// walk alike, so a wrapper added per write would add a forwarding hop per
    /// write to every colour read below. A palette that already reads as `scheme`
    /// — including a `TintedPalette` over a wrapper, which forwards it — is handed
    /// straight back, and a pin over an earlier pin REPLACES it rather than
    /// stacking on it.
    package static func palette(
        _ palette: any Palette, stating scheme: ColorScheme
    ) -> any Palette {
        let unpinned = (palette as? Self)?.base ?? palette
        guard unpinned.colorScheme != scheme else { return unpinned }
        return Self(base: unpinned, scheme: scheme)
    }

    package init(base: any Palette, scheme: ColorScheme) {
        self.base = base
        colorScheme = scheme
    }

    /// The scheme is the only field this adds; the bases are compared by the
    /// caller. So one palette under two pins is two palettes, and what was drawn
    /// under one is not kept for the other.
    package func hasSameDerivation(as other: Self) -> Bool { colorScheme == other.colorScheme }

    package var id: String { base.id }
    package var name: String { base.name }

    package var background: Color { base.background }
    package var statusBarBackground: Color { base.statusBarBackground }
    package var appHeaderBackground: Color { base.appHeaderBackground }
    package var overlayBackground: Color { base.overlayBackground }

    package var foreground: Color { base.foreground }
    package var foregroundSecondary: Color { base.foregroundSecondary }
    package var foregroundTertiary: Color { base.foregroundTertiary }
    package var foregroundQuaternary: Color { base.foregroundQuaternary }

    package var accent: Color { base.accent }

    package var success: Color { base.success }
    package var warning: Color { base.warning }
    package var error: Color { base.error }
    package var info: Color { base.info }

    package var border: Color { base.border }
    package var focusBackground: Color { base.focusBackground }
    package var cursorColor: Color { base.cursorColor }
    package var fieldBackground: Color { base.fieldBackground }
}
