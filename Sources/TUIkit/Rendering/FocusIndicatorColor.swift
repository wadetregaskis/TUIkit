//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusIndicatorColor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension AnimatedColor {
    /// The breathing ● an ACTIVE focus section shows in its border, or `nil`
    /// when the section is not active — which is also the value that means
    /// "draw no ●".
    ///
    /// A section decides *whether* the indicator is showing; the border that
    /// draws the box is the only thing that knows *where* it lands. Passing a
    /// plain `Color` between them was enough to draw it and not enough to
    /// animate it: the colour had to be resolved from the live clock as the
    /// section rendered, which marks the whole frame as having consulted that
    /// clock, so every tick of the pulse re-rendered the entire page to repaint
    /// one cell.
    ///
    /// The two endpoints are decided here, once, because both producers — a
    /// ``FocusSectionModifier`` and a ``NavigationSplitView`` column — want the
    /// same ●, and a second copy of the arithmetic is a second thing to drift.
    ///
    /// Gated through `EnvironmentValues.indicatesFocus(_:)`, here rather than at
    /// each caller: the ● and a resize grip's breath announce where the keyboard
    /// is, so under `focusEffectDisabled` they go, and every producer asks this
    /// one function for them.
    @MainActor
    static func activeSection(_ isActive: Bool, in environment: EnvironmentValues) -> Self? {
        guard environment.indicatesFocus(isActive) else { return nil }
        // Over the surface the section's border is drawn on, not the page:
        // inside a tab the page blend put the trough at the tab body's own
        // luminance (Homebrew: 1.009:1), the defect the button breath had.
        //
        // Through `Color.breathEnds`, so BOTH ends spend a translucent tint's
        // alpha against that surface. The bright end used to be a bare `accent`
        // and carried it while the dim end consumed it — §29.
        let ends = environment.palette.accent.breathEnds(
            dimmedTo: ViewConstants.focusBorderDim, over: environment.enclosingSurface)
        return environment.selectionEmphasis.animatedColor(
            true, dim: ends.dim, bright: ends.bright)
    }

    /// The ● drawn in this colour — the one description of that glyph, shared
    /// by the border that draws it and the run that replays it.
    func focusIndicatorGlyph(_ colour: Color) -> String {
        String(BorderRenderer.focusIndicator).styled(foreground: colour)
    }

    /// The run that breathes the ● at `(offsetX, offsetY)`, or `nil` when the
    /// indicator style does not animate (a still ● was already drawn, and a run
    /// would rewrite it on every tick to no visible effect).
    @MainActor
    func focusIndicatorRun(offsetX: Int, offsetY: Int) -> AnimatedCellRun? {
        run(offsetX: offsetX, offsetY: offsetY) { focusIndicatorGlyph($0) }
    }
}

// MARK: - Publishing the indicator to the render memo

extension RenderContext {
    /// Hands `sectionContext` the section's breathing ●, and tells the render
    /// memo that the answer changed — which the assignment on its own cannot.
    ///
    /// ``EnvironmentValues/focusIndicator`` is written straight into the child
    /// context, so neither a value memo's key nor `noteAppliedEnvironment` can
    /// see it move. `FocusSectionModifier` covers one direction already, by
    /// declining to STORE while its section is active. The other direction was
    /// open: a subtree stored while its section was INACTIVE compares equal
    /// afterwards, and `activateSection(id:)` clears nothing — it only asks for
    /// a repaint, which serves the same entry again. So a section that had taken
    /// the keyboard went on drawing no ●, and one that had lost it went on
    /// drawing one.
    ///
    /// Noted as the gated `Bool` rather than as the colour: the ● breathes, and
    /// noting a value that moves every tick would clear the subtree on every
    /// frame. Whether a ● shows at all is the whole of what the memo cannot
    /// otherwise see.
    ///
    /// The same shape as `FocusRegistration.publishIsFocused`, for the same
    /// reason and with the same depth handling — the bump is on both walks, so
    /// an `EnvironmentModifier` below finds the same slot either way.
    ///
    /// - Parameters:
    ///   - isActive: Whether this section is the active one.
    ///   - sectionContext: The context the section's content renders with.
    @MainActor
    func publishSectionIndicator(isActive: Bool, into sectionContext: inout RenderContext) {
        sectionContext.environmentApplicationDepth += 1
        // Never during measurement, as both producers spelled it themselves.
        let indicating = !isMeasuring && isActive
        sectionContext.environment.focusIndicator = AnimatedColor.activeSection(
            indicating, in: environment)
        guard !isMeasuring, let cache = renderCache else { return }
        if case .changed = cache.noteAppliedEnvironment(
            environment.indicatesFocus(indicating), identity: identity,
            keyPath: \EnvironmentValues.focusIndicator, depth: environmentApplicationDepth)
        {
            cache.clearAffected(by: identity)
        }
    }
}
