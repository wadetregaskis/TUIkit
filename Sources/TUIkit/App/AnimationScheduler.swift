//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationScheduler.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// Coalesces the periodic re-render requests of every animating view into the
/// fewest distinct render instants, and tells the run loop when to render next.
///
/// Each animating view *re-declares* its request every frame it is on screen
/// (via ``request(_:_:)``), keyed by a stable token. A token that stops
/// re-declaring (its view scrolled off, or it stopped animating) is dropped at
/// ``endFrame()`` — that is what keeps a static screen rendering nothing.
///
/// A request is a lattice: a render every `frameTicks` ticks of 1/60 s, at the
/// instants those ticks begin, counted from tick zero (see ``AnimationRequest``).
/// It has no phase to choose or to keep, so it is stored as declared, and
/// lattices coincide wherever their multiples meet, with each other and with
/// every run whose frames are whole ticks, by construction.
///
/// The loop's whole question is ``nextFiring(after:)``: the soonest firing across
/// everything live. Because every lattice shares tick zero, that soonest firing
/// is the *union* of their firings, which is smallest exactly when their periods
/// share multiples. One render at that instant serves every view, whether or not
/// its own lattice fired (the tree renders together); a longer period just rides
/// along on the frames it doesn't strictly need.
@MainActor
final class AnimationScheduler {
    private struct Lattice {
        let frameTicks: Int
        var liveThisFrame: Bool
    }

    private struct Wake {
        let instant: Int64
        var liveThisFrame: Bool
    }

    private var lattices: [String: Lattice] = [:]
    private var wakes: [String: Wake] = [:]

    /// Whether any animation is currently live (the loop idles when this is true... none).
    var isIdle: Bool { lattices.isEmpty && wakes.isEmpty }

    /// The number of live lattices (introspection / tests).
    var liveCount: Int { lattices.count }

    /// The number of live one-shot wakes (introspection / tests).
    var liveWakeCount: Int { wakes.count }

    /// Begins a render frame: every lattice and wake is provisionally not-live
    /// until it re-declares this frame.
    func beginFrame() {
        for key in lattices.keys {
            lattices[key]?.liveThisFrame = false
        }
        for key in wakes.keys {
            wakes[key]?.liveThisFrame = false
        }
    }

    /// Declares that the view identified by `token` is animating at `request`
    /// this frame.
    ///
    /// Stored as declared, replacing whatever the token declared before: a
    /// lattice has no anchor, so there is nothing to keep from one frame to the
    /// next.
    func request(_ token: String, _ request: AnimationRequest) {
        lattices[token] = Lattice(frameTicks: request.frameTicks, liveThisFrame: true)
    }

    /// Declares that the view identified by `token` needs a render at one exact
    /// instant, rather than at a repeating rate.
    ///
    /// The counterpart of ``request(_:_:)`` for a schedule that is a *list of
    /// instants* rather than a lattice — a ``TimelineView``'s, above all, whose
    /// entries may be irregular, and whose regular ones (the top of each minute)
    /// have a phase that a lattice counted from tick zero would not keep. Only the
    /// next instant is ever declared; the view declares the one after it on the
    /// frame this one produces.
    ///
    /// Re-declared every frame like a lattice, and dropped at ``endFrame()`` when
    /// it is not — which is what lets the screen go idle again.
    func requestWake(_ token: String, at instant: Int64) {
        wakes[token] = Wake(instant: instant, liveThisFrame: true)
    }

    /// Ends the frame: drops every lattice and wake that did not re-declare.
    func endFrame() {
        lattices = lattices.filter { $0.value.liveThisFrame }
        wakes = wakes.filter { $0.value.liveThisFrame }
    }

    /// The soonest firing strictly after `time` across all live lattices and
    /// one-shot wakes, or `nil` if nothing is animating (the loop then blocks
    /// until woken — zero idle work).
    ///
    /// A wake already at or behind `time` is not a firing: it names an instant
    /// this frame has reached, so returning it would ask the loop to render
    /// again immediately, and again on the frame after that. The view whose
    /// wake it was declares its next one during this frame. A lattice's next
    /// firing is strictly after `time` by definition.
    func nextFiring(after time: Int64) -> Int64? {
        var soonest: Int64?
        for lattice in lattices.values {
            soonest = min(
                soonest ?? .max,
                AnimationClock.nanoseconds(ofNextTickMultiple: lattice.frameTicks, after: time))
        }
        for wake in wakes.values where wake.instant > time {
            soonest = min(soonest ?? .max, wake.instant)
        }
        return soonest
    }
}
