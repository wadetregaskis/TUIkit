//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CPUClock.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Thread CPU Clock

/// CPU time consumed by the calling thread so far, in nanoseconds — or `nil`
/// where the platform has no per-thread CPU clock.
///
/// ## Why the bench needs this
///
/// A wall clock counts every microsecond, including the ones the scheduler
/// spent running something else. On a machine that is not idle — the ordinary
/// case — that turns an A/B of two binaries into an A/B of two *moments*: the
/// binary that happened to run while a browser repainted looks slower. Two
/// changes were reverted on 2026-08-12/13 because their effect could not be
/// separated from exactly that drift.
///
/// Thread CPU time excludes preemption. The same frame costs the same whatever
/// else the box is doing, so the measurement stops being a measurement of the
/// box.
///
/// It does **not** remove every source of variance — cache and
/// memory-bandwidth contention still slow the work itself, and those show up
/// as real CPU time — but it removes the largest one.
///
/// ## Cost
///
/// Read twice per frame. On Darwin this is `clock_gettime_nsec_np`, which is
/// more expensive than the `mach_absolute_time` behind `DispatchTime` — so it
/// brackets the wall-clock reads rather than sitting inside them, keeping the
/// existing wall number measuring exactly what it always did.
@inline(__always)
func threadCPUNanoseconds() -> UInt64? {
    #if canImport(Darwin)
    return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    #elseif canImport(Glibc) || canImport(Musl)
    var time = timespec()
    guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0 else { return nil }
    return UInt64(time.tv_sec) &* 1_000_000_000 &+ UInt64(time.tv_nsec)
    #else
    return nil
    #endif
}
