//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackFocusReach.swift
//
//  Ring continuation past non-focusable rows for the windowed stack paths.
//  The focus ring holds exactly what REGISTERED this pass, in render order,
//  and a windowed stack renders only the band plus the focused row's
//  immediate neighbours — so when a neighbour renders without registering
//  (a disabled control, a plain-text row), the ring simply ends at the
//  focused row and Tab wraps back into the band instead of advancing: every
//  row beyond the non-focusable run is unreachable by keyboard.
//
//  Whether a row registers is only observable by rendering it (disabled-ness
//  lives in the row's own content and environment), and the ring's order is
//  registration order — so the next focusable row must be found BEFORE the
//  main render sweep and injected into it at its ascending position. The
//  probe below renders candidate rows against a scratch FocusManager (real
//  state, no ring side effects) until one registers.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension _VStackCore {
    /// How far past the focused row the continuation probe reaches, per
    /// direction. A run of more than this many consecutive non-focusable
    /// rows stops the Tab walk at the run (focus then wraps) — pathological,
    /// and the cap keeps the per-frame probe bounded.
    static var focusReachProbeCap: Int { 64 }

    /// The nearest row beyond `origin` in `direction` (+1 down, −1 up) that
    /// registers a focusable when rendered, within the probe cap — the
    /// focus ring's required next stop. Probing renders rows against a
    /// scratch `FocusManager` (and no mouse dispatcher): row state and
    /// lifecycle behave as for any other rendered-but-off-screen row, and
    /// the real ring is untouched. Returns `nil` when nothing within the
    /// cap registers (or there is no focused row to continue from).
    func nearestFocusableRow(
        from origin: Int, direction: Int, count: Int,
        child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        context: RenderContext
    ) -> Int? {
        var probe = origin + direction
        var steps = 0
        while probe >= 0, probe < count, steps < Self.focusReachProbeCap {
            let scratch = FocusManager()
            var probeContext = context
            probeContext.environment.focusManager = scratch
            probeContext.environment.mouseEventDispatcher = nil
            _ = child(probe).render(
                width: width, height: viewportHeight, context: probeContext)
            // A disabled control still REGISTERS (with canBeFocused false —
            // the ring filters it at move time), so "registered anything" is
            // not the discriminator. `register` auto-focuses the first
            // canBeFocused element on a fresh manager, so a non-nil focus
            // here means exactly "this row contributed a focusABLE stop".
            if scratch.currentFocusedID != nil { return probe }
            probe += direction
            steps += 1
        }
        return nil
    }

    /// The focused row's continuation stops in both directions — the rows
    /// the render sweep must include (at their ascending positions) so the
    /// ring continues past any non-focusable run adjacent to focus.
    func focusRingContinuations(
        focusedOrdinal: Int?, count: Int,
        child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        context: RenderContext
    ) -> [Int] {
        guard let focused = focusedOrdinal else { return [] }
        var stops: [Int] = []
        for direction in [-1, 1] {
            if let stop = nearestFocusableRow(
                from: focused, direction: direction, count: count,
                child: child, width: width, viewportHeight: viewportHeight,
                context: context)
            {
                stops.append(stop)
            }
        }
        return stops
    }

    /// The ordinal of the row a focus ID addresses below this stack: memo
    /// hit, else one key scan (never builds a row view). Shared by the
    /// uniform and anchored paths (targets, seeks, and ring continuation).
    func targetOrdinal(
        for focusID: String?, children: ChildViewCollection,
        state: StackWindowState, context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        guard let key = Self.rowKey(inFocusID: focusID, belowStackPath: context.identity.path)
        else { return nil }
        return resolveOrdinal(forKey: key, children: children, state: state)
    }
}
