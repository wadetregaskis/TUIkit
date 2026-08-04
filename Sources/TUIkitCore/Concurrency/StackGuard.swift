//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackGuard.swift
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

import Foundation  // FileHandle, to read the procfs files the Linux bounds come from

/// A run-time guard against overflowing the call stack during deep view
/// nesting.
///
/// The measure/render pass recurses once per view-nesting level (each level is
/// several stack frames — a container, its modifiers, the composite descent).
/// A pathologically deep tree therefore grows the C stack without bound and, on
/// a normal 8 MB main-thread stack, hits the guard page and `SIGSEGV`s — an
/// uncatchable crash that also skips terminal restore.
///
/// `StackGuard` replaces that hard crash with graceful truncation: the measure
/// and render funnels ask ``hasHeadroom()`` before recursing another level, and
/// when the remaining stack falls under ``reserveBytes`` they stop descending
/// and return a small placeholder instead. The measurement is against the
/// *actual* remaining stack, not an arbitrary depth cap, so it adapts to the
/// thread's real stack size and the tree's real per-level cost.
///
/// ## Thread correctness
///
/// The bound and the stack pointer it's compared against must come from the
/// *same* thread. `@MainActor` does **not** deliver that on its own: it pins
/// work to the main *actor*, which is only the main *thread* while the main
/// actor's executor happens to be the main queue.
///
/// On Linux that holds only until the first suspension point. Measured on
/// Swift 6.3.3 (aarch64) with a plain `async main` executable — no test
/// harness involved:
///
///     BEFORE-AWAIT: isMainThread=true   stack=0xffffc8eea000-0xffffc8f0b000 [stack]
///     AFTER-AWAIT:  isMainThread=false  stack=0xffff8dfd0000-0xffff8e7d0000 (anon, 8 MB)
///
/// After the first `await` the main actor is drained by a cooperative pool
/// thread with its own, unrelated stack. A single process-wide bound seeded
/// from the main thread is therefore *wrong* for every frame an app renders,
/// because `App.run()` is `async` and awaits inside its loop: the pool
/// thread's stack sits far below the main stack's floor, so a main-seeded
/// guard reports "no headroom" forever and every child measures to zero —
/// a blank screen, not a crash.
///
/// So the bound is established for **whichever thread is actually running**,
/// and re-established whenever the recursion turns up on a different one. The
/// cache holds the running thread's whole usable stack extent, which makes
/// "am I still on the thread this bound describes?" a range check on the
/// stack pointer we already had to read — no thread-local lookup.
///
/// That matters: a `pthread_getspecific` design was measured at +1.14 ns per
/// call (2.25 vs 1.10 ns), landing as +2–5% per frame on measure-heavy trees,
/// because the guard sits atop every `measureChild`/`renderChild`. The range
/// check costs one extra compare against a value in the same cache line.
///
/// - Note: Re-establishing the bound reads `/proc/self/maps` on Linux, which
///   measured 276 µs. That is paid once per thread *change*, not once per
///   thread and not per call — and the main actor does not necessarily settle
///   on one thread: with the cooperative pool kept busy, 3 distinct threads
///   drained it across 40 iterations, alternating frame to frame. In that
///   regime the cost is ~3.4% of an 8 ms frame, which is the same order as the
///   `pthread_getspecific` design this replaced. The Example app's render
///   resumes onto the loop thread and re-derived 0 times across 20 loaded
///   frames, so the alternating case is possible rather than typical. If it
///   ever shows up in a profile, caching two extents instead of one is the
///   cheap answer.
///
/// - Important: Callers must be synchronous. The probe takes the address of a
///   local, which in a function that has been inlined into an `async` frame is
///   in the task allocator — the heap — not the machine stack. The answer
///   would then describe the wrong region entirely. Every caller in this
///   package (`measureChild`, `renderChild`) is synchronous.
public enum StackGuard {
    /// Stack to keep in reserve below the guard point (bytes). Must comfortably
    /// exceed the deepest non-recursive work that still has to complete once the
    /// guard trips — rendering a leaf, encoding a line, building the placeholder
    /// — plus several levels of slack (the guard is polled every few frames of
    /// descent, not every byte). 256 KB on an 8 MB stack costs ~3% of depth and
    /// leaves a wide margin.
    public static let reserveBytes: UInt = 256 * 1024

    /// One thread's usable stack, as the guard needs to see it.
    ///
    /// ``low``..<``high`` is the whole extent the stack may occupy — used to
    /// recognise "still the same thread" — and ``floor`` is ``low`` raised by
    /// ``reserveBytes``, the point descent must stop at.
    struct StackExtent: Equatable, Sendable {
        var low: UInt
        var floor: UInt
        var high: UInt

        /// No thread measured yet. `high == 0` fails the fast path's range
        /// check, so the first ask always goes and establishes real bounds.
        static let unseeded = Self(low: 0, floor: 0, high: 0)

        /// The guard has given up for good. The fast path's
        /// `sp > floor && sp < high` is then true for any real address, so
        /// ``hasHeadroom()`` always says yes, exactly as it did before this
        /// guard existed.
        ///
        /// Only ever reached after ``maxDerivationFailures`` consecutive
        /// failures to establish bounds — never on a single miss. A lone
        /// failure is usually transient (fd exhaustion while opening procfs),
        /// and latching on it would disarm the guard for the whole process,
        /// on every thread, for the rest of its life.
        static let disabled = Self(low: 0, floor: 0, high: .max)
    }

    /// The extent of the thread the recursion was last seen on.
    ///
    /// `@MainActor`-isolated: the measure/render recursion is `@MainActor` by
    /// architecture, so the actor serialises every read and write here. That
    /// is what makes a plain mutable cache safe — the isolation is doing
    /// mutual exclusion, *not* (as it once was) promising a particular thread.
    @MainActor
    static var cachedExtent: StackExtent = .unseeded

    /// How many times the guard has stopped a descent since the process
    /// started.
    ///
    /// Diagnostic, for harnesses that need to know whether the tree they just
    /// rendered is the whole tree — a profile or a benchmark of a truncated
    /// tree is not a measurement of the scenario, and is otherwise very hard to
    /// notice: a truncated child is measured at zero size first, so the `"⋯"`
    /// marker `renderChild` substitutes is immediately clamped away to nothing.
    /// The frame just quietly comes back emptier, and faster.
    ///
    /// Costs the hot path nothing: ``hasHeadroom()`` only ever answers `false`
    /// from its out-of-line slow path, so the counter lives there.
    @MainActor
    public static var truncationCount = 0

    /// Consecutive failures to establish bounds. Reset by any success.
    @MainActor
    static var derivationFailures = 0

    /// How many consecutive failures before the guard latches ``StackExtent/disabled``.
    ///
    /// Not 1: the derivation reads procfs, which can fail transiently (EMFILE
    /// while opening it), and one such moment must not cost the guard for the
    /// rest of the process. Not unbounded either: where procfs is genuinely
    /// unreadable — a `hidepid=2` mount — retrying forever would put a failed
    /// `open` on every one of the hundreds of thousands of guard calls per
    /// frame. A handful of retries distinguishes the two.
    static let maxDerivationFailures = 4

    /// Whether there is enough stack left to safely recurse another level.
    ///
    /// The hot path is a stack-pointer read and two compares against adjacent
    /// fields of the cache: above the floor, and below the top of the stack
    /// that floor belongs to. Both must hold — the second is what stops a
    /// bound from one thread being applied to another's stack pointer.
    @inline(__always)
    @MainActor
    public static func hasHeadroom() -> Bool {
        var probe: UInt = 0
        let stackPointer = withUnsafeMutablePointer(to: &probe) { UInt(bitPattern: $0) }
        let extent = cachedExtent
        // The stack grows DOWN: more recursion → lower addresses. Headroom
        // remains while the pointer is still above the reserved floor AND
        // still inside the stack that floor was computed for.
        if stackPointer > extent.floor && stackPointer < extent.high { return true }
        return headroomSlowPath(stackPointer: stackPointer)
    }

    /// The out-of-line half of ``hasHeadroom()``: either genuinely out of
    /// stack, or on a thread the cache does not describe.
    ///
    /// Deliberately not inlined — it is the cold path, and keeping the
    /// procfs read out of the caller keeps the hot path small enough to inline
    /// into every `measureChild`/`renderChild`.
    @MainActor
    private static func headroomSlowPath(stackPointer: UInt) -> Bool {
        // Checked before the containment test below, not after: `disabled`
        // spans the whole address space, so it would satisfy that test and
        // return `false` — inverting "the guard is off" into "nothing has
        // headroom", a permanently blank screen.
        if cachedExtent == .disabled { return true }
        // Inside the extent we already know about, but at or below its floor:
        // this is the guard doing its job on the expected thread.
        if stackPointer >= cachedExtent.low && stackPointer < cachedExtent.high {
            truncationCount += 1
            return false
        }
        // Outside it — a different thread than last time (or the very first
        // ask). Establish this thread's bounds and answer against those.
        guard let extent = currentThreadExtent(stackPointer: stackPointer) else {
            // Fail OPEN, and — crucially — do not cache that. Caching it would
            // make one bad moment absorbing: `disabled` satisfies the fast
            // path for every address, so the slow path would never run again
            // and bounds would never be re-derived, on any thread, ever.
            derivationFailures += 1
            if derivationFailures >= maxDerivationFailures { cachedExtent = .disabled }
            return true
        }
        derivationFailures = 0
        cachedExtent = extent
        let headroom = stackPointer > extent.floor && stackPointer < extent.high
        if !headroom { truncationCount += 1 }
        return headroom
    }

    /// The stack bounds of the thread `stackPointer` was taken on, or `nil`
    /// when the platform cannot report them (which disables the guard).
    @MainActor
    private static func currentThreadExtent(stackPointer: UInt) -> StackExtent? {
        #if canImport(Darwin)
            // Both calls take a pthread, so they answer for whatever thread is
            // asking — no main-thread assumption needed on this platform.
            // `pthread_get_stackaddr_np` returns the stack BASE (highest
            // address); the stack grows down from there for `stacksize` bytes.
            let thread = pthread_self()
            let base = UInt(bitPattern: pthread_get_stackaddr_np(thread))
            let size = UInt(pthread_get_stacksize_np(thread))
            guard base > size else { return nil }
            return extent(low: base - size, high: base)
        #elseif canImport(Glibc) || canImport(Musl)
            // Asked of the KERNEL, not of pthread. The pthread route needs
            // `pthread_getattr_np`, a GNU extension Swift's Glibc overlay does
            // not surface — the Linux build failed outright on "cannot find
            // 'pthread_getattr_np' in scope" (still true on 6.3.3) — and there
            // is no portable non-GNU equivalent that yields a thread's stack
            // bounds.
            //
            // procfs describes every mapping, is there on every Linux (glibc
            // and musl alike), and needs nothing but Foundation. Which mapping
            // is *this* thread's stack is settled by the stack pointer we were
            // handed: the one containing it.
            guard let maps = readProcFile("/proc/self/maps"),
                let limits = readProcFile("/proc/self/limits")
            else { return nil }
            return linuxStackExtent(maps: maps, limits: limits, stackPointer: stackPointer)
        #else
            return nil  // unknown platform → guard disabled
        #endif
    }

    /// Builds an extent from raw bounds, reserving ``reserveBytes`` above the
    /// low end.
    ///
    /// A stack smaller than the reserve yields a floor at or above `high`, so
    /// the guard trips on the first ask and the recursion truncates
    /// immediately. That is the honest answer — there genuinely is no room to
    /// descend — and it fails CLOSED, where returning `nil` here would fail
    /// open and hand back the `SIGSEGV` this type exists to prevent.
    private static func extent(low: UInt, high: UInt) -> StackExtent? {
        let (floor, overflowed) = low.addingReportingOverflow(reserveBytes)
        guard !overflowed else { return nil }
        return StackExtent(low: low, floor: floor, high: high)
    }

    /// Reads a procfs file whole.
    ///
    /// To EOF rather than by size, and not via `String(contentsOfFile:)`: a
    /// procfs file reports `st_size` 0, so anything that sizes the read first
    /// comes back empty.
    private static func readProcFile(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The stack extent of the thread whose stack pointer is `stackPointer`,
    /// from the two procfs files that describe the process. `nil` when the
    /// mapping cannot be found or the bounds cannot be established, which
    /// disables the guard.
    ///
    /// Takes the file *contents* rather than reading them, so the parsing —
    /// the part with the edge cases — is testable on any platform, including
    /// the macOS where it never runs.
    ///
    /// Which mapping is the running thread's stack is decided by containment:
    /// the one whose address range holds `stackPointer`. The two kinds of
    /// stack a thread can be on then need opposite treatment:
    ///
    /// - The **process main stack** is the mapping tagged `[stack]`. It is
    ///   grow-down, so its LOW address is emphatically *not* the floor — it
    ///   only extends as far as the stack has actually been touched, sitting a
    ///   page or two under the current stack pointer, and taking it as the
    ///   floor would trip the guard immediately and truncate every nested
    ///   view. The real floor is `high - RLIMIT_STACK`, precisely the kernel's
    ///   own rule for how far that stack may grow (`acct_stack_growth` refuses
    ///   a fault once `vm_end - address` exceeds `RLIMIT_STACK`).
    /// - A **pthread stack** — which is where the main actor ends up on Linux
    ///   after the first suspension point — is an ordinary anonymous mapping,
    ///   carrying no tag of any kind. It is allocated at full size up front
    ///   and never grows, so its LOW address *is* the floor and `RLIMIT_STACK`
    ///   is irrelevant to it.
    ///
    /// The limit is the soft `RLIMIT_STACK`, read out of `/proc` rather than
    /// through `getrlimit` because that call's Swift signature differs between
    /// the Glibc and Musl overlays (the resource argument is an imported enum
    /// on one and an `Int32` on the other), and this branch cannot be
    /// compile-checked from macOS.
    static func linuxStackExtent(maps: String, limits: String, stackPointer: UInt) -> StackExtent? {
        // "7ffd0d3f0000-7ffd0d411000 rw-p 00000000 00:00 0    [stack]"
        var low: UInt?
        var high: UInt?
        var isMainStack = false
        // The end of the mapping immediately below the one we settle on. procfs
        // lists mappings in ascending address order, so simply carrying the
        // previous line's high address forward lands on it; `max` keeps that
        // true even if some kernel ever stopped sorting.
        var mappingBelowEnd: UInt = 0
        for line in maps.split(separator: "\n") {
            guard let range = line.split(separator: " ", maxSplits: 1).first,
                let dash = range.firstIndex(of: "-"),
                let lineLow = UInt(range[range.startIndex..<dash], radix: 16),
                let lineHigh = UInt(range[range.index(after: dash)...], radix: 16)
            else { continue }  // a malformed line is skipped, not fatal
            guard stackPointer >= lineLow && stackPointer < lineHigh else {
                if lineHigh <= stackPointer { mappingBelowEnd = max(mappingBelowEnd, lineHigh) }
                continue
            }
            low = lineLow
            high = lineHigh
            isMainStack = line.hasSuffix("[stack]")
            break
        }
        guard let low, let high else { return nil }  // no mapping holds it
        guard isMainStack else { return extent(low: low, high: high) }

        // "Max stack size            8388608              unlimited            bytes"
        // The name column holds spaces, so match the prefix and split the rest;
        // "unlimited" parses as nil — a stack with no limit is bounded only by
        // what it would run into, which is exactly what `growthLimit` is.
        var limit: UInt?
        for line in limits.split(separator: "\n") where line.hasPrefix("Max stack size") {
            limit = line.dropFirst("Max stack size".count)
                .split(separator: " ", omittingEmptySubsequences: true)
                .first
                .flatMap { UInt($0) }
            break
        }

        // Two independent bounds on how far the main stack may grow down; the
        // real floor is whichever binds FIRST, i.e. the higher address.
        //
        // `RLIMIT_STACK` alone is not enough, and trusting it alone is a way to
        // hand back the SIGSEGV this type exists to prevent. The kernel keeps
        // thread stacks clear of the main stack by choosing `mmap_base` from
        // the limit in force at *exec*; a process may raise the soft limit
        // afterwards (the hard limit is commonly `unlimited`), and then
        // `/proc/self/limits` reports the new value while the layout still
        // reflects the old one. The window `[high - limit, high)` then spans
        // address space that other threads' stacks already occupy — and since
        // `hasHeadroom()` reads "inside the extent" as "still the same
        // thread", a pool thread's stack pointer would look like plenty of
        // main-stack headroom at any depth.
        //
        // The mapping immediately below is a hard wall by construction: the
        // stack cannot grow into it, and the kernel refuses to grow within
        // `stack_guard_gap` of it. Bounding by that cannot swallow another
        // mapping, and it is also what makes an unlimited `RLIMIT_STACK`
        // answerable instead of unknowable.
        let growthLimit = mappingBelowEnd > 0 ? mappingBelowEnd + stackGuardGapBytes : nil
        let rlimitLow = limit.flatMap { $0 > 0 && high > $0 ? high - $0 : nil }
        guard let bound = [growthLimit, rlimitLow].compactMap({ $0 }).max() else { return nil }
        return extent(low: bound, high: high)
    }

    /// The gap Linux keeps between the main stack and the mapping below it —
    /// `stack_guard_gap`, 256 pages (`mm/mmap.c`). The stack faults rather
    /// than grows once it comes within this distance, so the usable floor sits
    /// a gap above the neighbour, not flush against it.
    ///
    /// Read from the live page size rather than assuming 4 KB: arm64 kernels
    /// are commonly built with 16 KB or 64 KB pages, where assuming the
    /// smallest would place the floor up to 15 MB below the real fault point.
    static var stackGuardGapBytes: UInt {
        #if canImport(Glibc) || canImport(Musl)
            let pageSize = sysconf(Int32(_SC_PAGESIZE))
            return pageSize > 0 ? UInt(pageSize) * 256 : 256 * 4096
        #else
            return 256 * 4096
        #endif
    }
}
