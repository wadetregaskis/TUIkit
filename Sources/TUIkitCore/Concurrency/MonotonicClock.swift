//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MonotonicClock.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The clock the run loop runs on

/// Nanoseconds on a clock that only ever goes forward, from an arbitrary point
/// fixed at process start.
///
/// Every part of the framework that measures an *interval* reads this: the run
/// loop's frame pacing, the animation clocks, auto-repeat's awake-time gate,
/// the mouse dispatcher's double-click window, the scroll animator, and the
/// hyperlink activation gate. None of them care what time it is — only how much
/// has passed — which is the whole reason a monotonic reading is the right one:
/// a wall clock can be set backwards, and an interval measured across that
/// moves backwards with it.
///
/// ## Why not `DispatchTime`
///
/// This used to be `DispatchTime.now().uptimeNanoseconds`, spelled out at a
/// dozen call sites. It reads the same clock, and it means importing `Dispatch`
/// into a dozen files to do arithmetic on an integer — which is what made those
/// files unbuildable on a platform with no libdispatch. WebAssembly is one
/// (wasip1 has no threads to dispatch *to*), and Windows very nearly is
/// (libdispatch is there, but the pieces of it this framework leaned on are the
/// ones that refuse console handles).
///
/// `SuspendingClock` is the standard library's name for the same clock —
/// monotonic, and *not* advancing while the machine is asleep, exactly as
/// `uptimeNanoseconds` did not. `ContinuousClock` is the other one, and would
/// have been a quiet behaviour change: a laptop closed mid-animation would
/// reopen having "elapsed" the whole nap.
///
/// ## Cost
///
/// Read a handful of times per frame, never per cell. On Darwin it is the same
/// `clock_gettime_nsec_np` the old spelling reached, plus the `Duration`
/// arithmetic below; measured against the previous spelling on the stress
/// bench, the difference is inside the noise on every scenario.
package enum MonotonicClock {

    /// Where this process started counting. Any fixed point does: every reader
    /// subtracts two readings, so the origin cancels. Fixing it at first use
    /// also keeps the numbers small enough that the multiply below cannot
    /// overflow within any plausible process lifetime (585 years).
    private static let epoch = SuspendingClock.now

    /// The reading now.
    package static var nowNanoseconds: UInt64 {
        // The origin is read FIRST, deliberately. Written as
        // `SuspendingClock.now - epoch`, Swift evaluates the left operand
        // before the right — so the very first call takes its reading, *then*
        // initialises `epoch` from a later one, and subtracts a bigger number
        // from a smaller. The result is a negative `Duration` whose `seconds`
        // is 0 and whose `attoseconds` is not, which walks straight past a
        // `seconds >= 0` check and traps in the conversion below. It cost a
        // WebAssembly launch to find and would have been a rare, unreproducible
        // crash on the first frame anywhere.
        let origin = epoch
        let (seconds, attoseconds) = (SuspendingClock.now - origin).components
        // Both halves are signed, and a clamp on both is the only form that
        // cannot trap — a negative reading is answered with zero, which is the
        // truth for a clock that has not moved.
        guard seconds >= 0, attoseconds >= 0 else { return 0 }
        return UInt64(seconds) &* 1_000_000_000 &+ UInt64(attoseconds / 1_000_000_000)
    }
}
