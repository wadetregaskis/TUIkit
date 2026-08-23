//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationScheduler.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Coalesces the periodic re-render requests of every animating view into the
/// fewest distinct render instants, and tells the run loop when to render next.
///
/// Each animating view *re-declares* its desired rate every frame it is on screen
/// (via ``request(_:_:now:)``), keyed by a stable token. The first time a token is
/// seen the request is resolved into an ``AnimationGrid`` — locking onto a live
/// grid when frequency and phase tolerance allow (see ``AnimationGrid/resolve``).
/// After that the grid is frozen: re-declaring keeps it unchanged, so a steady
/// animation never drifts or re-phases. A token that stops re-declaring (its view
/// scrolled off, or it stopped animating) is dropped at ``endFrame()`` — that is
/// what keeps a static screen rendering nothing.
///
/// The loop's whole question is ``nextFiring(after:)``: the soonest firing across
/// all live grids. Because locked grids share a lattice, that soonest firing is
/// the *union* of firings — which is minimised exactly when timers coalesce. One
/// render at that instant serves every view, whether or not its own grid fired
/// (the tree renders together); a sub-harmonic just rides along on the frames it
/// doesn't strictly need.
@MainActor
final class AnimationScheduler {
    private struct Entry {
        let grid: AnimationGrid
        var liveThisFrame: Bool
    }

    private struct Wake {
        let instant: Int64
        var liveThisFrame: Bool
    }

    private var entries: [String: Entry] = [:]
    private var wakes: [String: Wake] = [:]

    /// Whether any animation is currently live (the loop idles when this is true... none).
    var isIdle: Bool { entries.isEmpty && wakes.isEmpty }

    /// The number of live grids (introspection / tests).
    var liveCount: Int { entries.count }

    /// The number of live one-shot wakes (introspection / tests).
    var liveWakeCount: Int { wakes.count }

    /// Begins a render frame: every grid is provisionally not-live until it
    /// re-declares this frame.
    func beginFrame() {
        for key in entries.keys {
            entries[key]?.liveThisFrame = false
        }
        for key in wakes.keys {
            wakes[key]?.liveThisFrame = false
        }
    }

    /// Declares that the view identified by `token` is animating at `request`.
    ///
    /// A new token is resolved (and may lock onto a live grid); a known token
    /// keeps its existing, frozen grid — re-declaring never re-resolves, so a
    /// running animation is never re-phased. Returns the token's grid.
    @discardableResult
    func request(_ token: String, _ request: AnimationRequest, now: Int64) -> AnimationGrid {
        if var entry = entries[token] {
            entry.liveThisFrame = true
            entries[token] = entry
            return entry.grid
        }
        let grid = AnimationGrid.resolve(
            request, lockingOnto: entries.values.map(\.grid), now: now)
        entries[token] = Entry(grid: grid, liveThisFrame: true)
        return grid
    }

    /// Declares that the view identified by `token` needs a render at one exact
    /// instant, rather than at a repeating rate.
    ///
    /// The counterpart of ``request(_:_:now:)`` for a schedule that is a *list
    /// of instants* rather than a lattice — a ``TimelineView``'s, above all,
    /// whose entries may be irregular, and whose regular ones (the top of each
    /// minute) have a phase that a grid free to coalesce would not keep. Only
    /// the next instant is ever declared; the view declares the one after it on
    /// the frame this one produces.
    ///
    /// Re-declared every frame like a grid, and dropped at ``endFrame()`` when
    /// it is not — which is what lets the screen go idle again.
    func requestWake(_ token: String, at instant: Int64) {
        wakes[token] = Wake(instant: instant, liveThisFrame: true)
    }

    /// Ends the frame: drops every grid and wake that did not re-declare.
    func endFrame() {
        entries = entries.filter { $0.value.liveThisFrame }
        wakes = wakes.filter { $0.value.liveThisFrame }
    }

    /// The soonest firing strictly after `time` across all live grids and
    /// one-shot wakes, or `nil` if nothing is animating (the loop then blocks
    /// until woken — zero idle work).
    ///
    /// A wake already at or behind `time` is not a firing: it names an instant
    /// this frame has reached, so returning it would ask the loop to render
    /// again immediately, and again on the frame after that. The view whose
    /// wake it was declares its next one during this frame.
    func nextFiring(after time: Int64) -> Int64? {
        let grids = entries.values.lazy.map { $0.grid.firing(after: time) }.min()
        let wake = wakes.values.lazy.map(\.instant).filter { $0 > time }.min()
        guard let grids else { return wake }
        guard let wake else { return grids }
        return min(grids, wake)
    }

    /// The frozen grid currently registered for `token`, if any.
    func grid(for token: String) -> AnimationGrid? {
        entries[token]?.grid
    }
}
