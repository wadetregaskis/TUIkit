//  🖥️ TUIkit — Terminal UI Kit for Swift
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
//  state, no ring side effects) and throwaway key channels (no input side
//  effects either) until one registers.
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
    /// scratch `FocusManager` over `isolated`, whose key channels are already
    /// throwaways and whose mouse dispatcher is gone — built once for both
    /// directions by `focusRingContinuations`, the only caller, which is why
    /// this is private. Row state and lifecycle behave as for any other
    /// rendered-but-off-screen row; neither the real ring nor any live input
    /// service is touched. Returns `nil` when nothing within the cap
    /// registers.
    private func nearestFocusableRow(
        from origin: Int, direction: Int, count: Int,
        child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        isolated: RenderContext
    ) -> Int? {
        var probe = origin + direction
        var steps = 0
        while probe >= 0, probe < count, steps < Self.focusReachProbeCap {
            let scratch = FocusManager()
            // The scratch manager must not FOCUS anything. It is throwaway, but
            // the rows it registers are not: the probe shares the live
            // `StateStorage`, so each one resolves the app's real persisted
            // `Focusable` — and `register` auto-focuses the first focusable
            // element on an empty manager, which called `onFocusReceived()` on
            // a row nobody had focused, every frame, for as many rows as the
            // probe walked. A `TextField` reached that way began editing.
            scratch.suppressesAutoFocus = true
            var probeContext = isolated
            probeContext.environment.focusManager = scratch
            _ = child(probe).render(
                width: width, height: viewportHeight, context: probeContext)
            // Asked directly now, rather than inferred from the side effect of
            // an auto-focus. A disabled control still REGISTERS (with
            // `canBeFocused` false — the ring filters it at move time), so
            // "registered anything" would be the wrong question.
            if scratch.hasFocusableElement { return probe }
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
        // Every channel a key can arrive on goes to a throwaway, not just the
        // focus ring. A probe is a RENDER — `isMeasuring` is false — so each
        // row it asks performs every render-pass registration it has, and the
        // live dispatcher keeps every handler it is handed until the next
        // frame. With only the focus manager swapped, a row the walk merely
        // counted (never drawn, never in the sweep) held a live `onKeyPress`,
        // a `.hidden()` button's `.keyboardShortcut` — hidden registers no
        // focusable, so the walk goes straight past it — and `.statusBarItems`
        // that stood on the bar whenever no drawn row declared its own, all
        // for the whole frame. And the focused row's neighbours, which the
        // probe always asks first and the sweep draws anyway, registered
        // twice: a declining handler beside the focus ran twice per keypress.
        // Built once per frame, not per probed row: what these collect is
        // never read.
        var isolated = context.withThrowawayKeyChannels()
        isolated.environment.mouseEventDispatcher = nil
        var stops: [Int] = []
        for direction in [-1, 1] {
            if let stop = nearestFocusableRow(
                from: focused, direction: direction, count: count,
                child: child, width: width, viewportHeight: viewportHeight,
                isolated: isolated)
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
