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

import Foundation  // Thread.isMainThread, for the debug-only seeding assertion

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
/// *same* thread, so a single cached ``floor`` is only correct if every access
/// happens on one thread. That's guaranteed structurally: the measure/render
/// recursion is `@MainActor` by architecture (`View`/`Renderable` are
/// `@MainActor`), and ``floor``/``hasHeadroom()`` are `@MainActor`-isolated to
/// match. A `@MainActor` lazy static initializes on first access — which, being
/// `@MainActor`, is forced onto the main thread — so the compiler *proves* the
/// bound is computed, and every comparison made, on that one thread. An
/// off-thread first touch (which a nonisolated version would silently allow,
/// caching a foreign thread's bounds process-wide) is thus a compile error.
///
/// A per-thread design (thread-local ``floor``) would lift the main-thread
/// requirement, but measured ~2–5% slower per frame on measure-heavy trees (a
/// `pthread_getspecific` on the hot `hasHeadroom()` path, called hundreds of
/// thousands of times per frame) — not worth it while rendering is main-only.
///
/// - Note: `@MainActor` guarantees the main *actor*; the default executor drains
///   it on the main *thread*. A debug-only `assert` in ``computeFloor()`` catches
///   the exotic case of a replaced main-actor executor running elsewhere.
public enum StackGuard {
    /// Stack to keep in reserve below the guard point (bytes). Must comfortably
    /// exceed the deepest non-recursive work that still has to complete once the
    /// guard trips — rendering a leaf, encoding a line, building the placeholder
    /// — plus several levels of slack (the guard is polled every few frames of
    /// descent, not every byte). 256 KB on an 8 MB stack costs ~3% of depth and
    /// leaves a wide margin.
    public static let reserveBytes: UInt = 256 * 1024

    /// The lowest stack address the recursion may reach before it must stop:
    /// the thread's stack limit plus ``reserveBytes``. `0` when the platform
    /// can't report stack bounds, which disables the guard (``hasHeadroom()``
    /// then always returns `true` — same behaviour as before this existed).
    ///
    /// Computed once, lazily, on the first call. `@MainActor`-isolated so the
    /// compiler forces that first access — and thus ``computeFloor()``'s read of
    /// the current thread's stack bounds — onto the main thread, the one thread
    /// the `@MainActor` measure/render recursion ever runs on.
    @MainActor
    static let floor: UInt = computeFloor()

    /// Whether there is enough stack left to safely recurse another level.
    ///
    /// Cheap enough for the hot measure/render funnels: a stack-pointer read and
    /// one comparison against the cached ``floor``. `@MainActor`-isolated (it
    /// reads ``floor``, and its callers already are), so it stays a direct,
    /// inlined call with no actor hop.
    @inline(__always)
    @MainActor
    public static func hasHeadroom() -> Bool {
        guard floor != 0 else { return true }  // bounds unknown → guard disabled
        var probe: UInt = 0
        let stackPointer = withUnsafeMutablePointer(to: &probe) { UInt(bitPattern: $0) }
        // The stack grows DOWN: more recursion → lower addresses. Headroom
        // remains while the current pointer is still above the reserved floor.
        return stackPointer > floor
    }

    @MainActor
    private static func computeFloor() -> UInt {
        // The bound is captured from the CURRENT thread; the guard is only
        // correct if that's the same thread every `hasHeadroom()` later probes.
        // `@MainActor` proves this is the main actor, whose default executor
        // runs on the main thread — but a replaced executor could drain it
        // elsewhere, silently caching the wrong stack's bounds. This debug-only
        // check trips loudly if that ever happens; it compiles out in release.
        assert(Thread.isMainThread, "StackGuard.floor must be seeded on the main thread")
        #if canImport(Darwin)
            let thread = pthread_self()
            // `pthread_get_stackaddr_np` returns the stack BASE (highest address);
            // the stack grows down from there for `stacksize` bytes.
            let base = UInt(bitPattern: pthread_get_stackaddr_np(thread))
            let size = UInt(pthread_get_stacksize_np(thread))
            guard base > size else { return 0 }
            return (base - size) + reserveBytes
        #elseif canImport(Glibc) || canImport(Musl)
            var attr = pthread_attr_t()
            guard pthread_getattr_np(pthread_self(), &attr) == 0 else { return 0 }
            defer { pthread_attr_destroy(&attr) }
            var low: UnsafeMutableRawPointer?
            var size = 0
            // On Linux `pthread_attr_getstack` returns the LOW address directly.
            guard pthread_attr_getstack(&attr, &low, &size) == 0, let low else { return 0 }
            return UInt(bitPattern: low) + reserveBytes
        #else
            return 0  // unknown platform → guard disabled
        #endif
    }
}
