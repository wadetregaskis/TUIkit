//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackGuardFloorTests.swift
//
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

/// Covers the Linux stack-extent parse, which never runs on the machine these
/// tests are usually run on. `StackGuard.linuxStackExtent(maps:limits:stackPointer:)`
/// takes the procfs *contents* rather than reading them precisely so that this
/// — the part with the edge cases — is exercised everywhere.
@Suite("Stack guard: Linux stack extent")
struct StackGuardLinuxFloorTests {

    /// A `/proc/self/maps` excerpt. The `[stack]` mapping is deliberately
    /// small (0x21000 = 132 KB), which is what it really looks like early in a
    /// process: it is grow-down and reaches only as far as the stack has been
    /// touched. The 8 MB anonymous mapping is a pthread stack — allocated at
    /// full size, and carrying no tag to distinguish it by.
    private let maps = """
        55d3f4a00000-55d3f4a21000 r-xp 00000000 08:01 1234    /usr/bin/swift
        7f2c1c000000-7f2c1c800000 rw-p 00000000 00:00 0
        7ffd0d3f0000-7ffd0d411000 rw-p 00000000 00:00 0                          [stack]
        7ffd0d5fe000-7ffd0d600000 r-xp 00000000 00:00 0                          [vdso]
        """

    private let limits = """
        Limit                     Soft Limit           Hard Limit           Units
        Max cpu time              unlimited            unlimited            seconds
        Max stack size            8388608              unlimited            bytes
        Max open files            1024                 1048576              files
        """

    /// A stack pointer somewhere inside the `[stack]` mapping.
    private let mainStackPointer = UInt(0x7ffd_0d40_0000)
    /// A stack pointer inside the anonymous pthread stack.
    private let threadStackPointer = UInt(0x7f2c_1c40_0000)

    private func parse(_ maps: String, _ limits: String, _ stackPointer: UInt) -> StackGuard
        .StackExtent?
    {
        StackGuard.linuxStackExtent(maps: maps, limits: limits, stackPointer: stackPointer)
    }

    @Test("The floor is the stack top less the limit, plus the reserve")
    func floorIsTopMinusLimit() {
        // Top is the [stack] mapping's HIGH address, 0x7ffd0d411000.
        let expected = UInt(0x7ffd_0d41_1000) - 8_388_608 + StackGuard.reserveBytes
        #expect(parse(maps, limits, mainStackPointer)?.floor == expected)
    }

    /// The bug this parse replaced: taking the mapping's LOW address as the
    /// floor. That address tracks the current high-water mark, so it sits just
    /// under the live stack pointer — the guard would report "no headroom" on
    /// the first ask and truncate every nested view to "⋯". The real floor is
    /// nearly 8 MB below it.
    @Test("The mapping's low address is not mistaken for the floor")
    func lowAddressIsNotTheFloor() throws {
        let low = UInt(0x7ffd_0d3f_0000)
        let floor = try #require(parse(maps, limits, mainStackPointer)).floor
        #expect(floor < low)
        #expect(low - floor > 7_000_000, "the floor must be a whole stack below the touched extent")
    }

    /// The bug this parse fixes. On Linux the main actor is drained by a
    /// cooperative pool thread after the first suspension point, so the
    /// recursion runs on a pthread stack — an untagged anonymous mapping. That
    /// stack is allocated at full size and never grows, so its LOW address is
    /// the floor, and `RLIMIT_STACK` (which governs only the main stack) must
    /// not be subtracted from it.
    @Test("A pthread stack is bounded by its own mapping, not by RLIMIT_STACK")
    func threadStackUsesItsMappingLowAddress() throws {
        let extent = try #require(parse(maps, limits, threadStackPointer))
        #expect(extent.low == 0x7f2c_1c00_0000)
        #expect(extent.high == 0x7f2c_1c80_0000)
        #expect(extent.floor == UInt(0x7f2c_1c00_0000) + StackGuard.reserveBytes)
    }

    /// The whole point of tracking `high` as well as `floor`: a bound belonging
    /// to one thread must never be applied to another's stack pointer. The two
    /// extents here must not overlap at all.
    @Test("Each thread's extent covers only its own stack")
    func extentsDoNotOverlap() throws {
        let main = try #require(parse(maps, limits, mainStackPointer))
        let thread = try #require(parse(maps, limits, threadStackPointer))
        #expect(!(mainStackPointer >= thread.low && mainStackPointer < thread.high))
        #expect(!(threadStackPointer >= main.low && threadStackPointer < main.high))
    }

    /// A pool-thread stack mapped inside the window a raised `RLIMIT_STACK`
    /// would claim for the main stack. The kernel picks `mmap_base` from the
    /// limit in force at *exec*, so a limit raised afterwards describes space
    /// other threads already occupy.
    private let raisedLimitMaps = """
        7ffc00000000-7ffc00800000 rw-p 00000000 00:00 0
        7ffd0d3f0000-7ffd0d411000 rw-p 00000000 00:00 0                          [stack]
        """

    /// The defect that made a raised soft limit fatal: with the floor taken
    /// from `high - RLIMIT_STACK` alone, the main extent swallowed the pool
    /// thread's stack. `hasHeadroom()` reads "inside the extent" as "still the
    /// same thread", so that thread looked like it had main-stack headroom at
    /// any depth, and the recursion ran off the end of its own 8 MB stack.
    @Test("The main-stack window stops at the mapping below, not at RLIMIT_STACK")
    func mainStackIsClampedByTheMappingBelow() throws {
        let raised = limits.replacingOccurrences(
            of: "Max stack size            8388608",
            with: "Max stack size            536870912")
        let extent = try #require(parse(raisedLimitMaps, raised, mainStackPointer))
        #expect(
            extent.low >= 0x7ffc_0080_0000,
            "the floor stops at the neighbouring mapping, not 512 MB below the stack top")
        let poolStackPointer = UInt(0x7ffc_0040_0000)
        #expect(
            !(poolStackPointer >= extent.low && poolStackPointer < extent.high),
            "another thread's stack must not fall inside the main stack's extent")
    }

    /// An unlimited stack is not unknowable: it grows until it reaches
    /// whatever is mapped below it, which is a real bound. Disabling the guard
    /// here — as this did before — is what let a 100,000-deep tree SIGSEGV
    /// under `ulimit -s unlimited`.
    @Test("An unlimited stack is bounded by what it would grow into")
    func unlimitedIsBoundedByTheMappingBelow() throws {
        let unlimited = limits.replacingOccurrences(
            of: "Max stack size            8388608",
            with: "Max stack size            unlimited")
        let extent = try #require(parse(maps, unlimited, mainStackPointer))
        #expect(extent.low >= 0x7f2c_1c80_0000, "bounded by the end of the mapping below")
        #expect(extent.low < 0x7ffd_0d3f_0000, "but still well below the stack's touched extent")
    }

    /// The stack cannot grow flush against its neighbour: the kernel faults
    /// once it comes within `stack_guard_gap`. A floor placed at the
    /// neighbour's end would therefore sit *below* the real crash point.
    @Test("The floor clears the neighbouring mapping by the kernel's guard gap")
    func floorClearsTheGuardGap() throws {
        let unlimited = limits.replacingOccurrences(
            of: "Max stack size            8388608",
            with: "Max stack size            unlimited")
        let extent = try #require(parse(maps, unlimited, mainStackPointer))
        #expect(extent.low >= 0x7f2c_1c80_0000 + StackGuard.stackGuardGapBytes)
    }

    @Test("Missing information falls back to the layout rather than guessing")
    func missingInformationFallsBackToTheLayout() throws {
        // No limits at all: the mapping below still bounds the stack.
        let extent = try #require(parse(maps, "", mainStackPointer))
        #expect(extent.low >= 0x7f2c_1c80_0000)
        // No maps at all: nothing locates the stack, so the guard must disable.
        #expect(parse("", limits, mainStackPointer) == nil)
    }

    /// With nothing mapped below and no usable limit there is genuinely no
    /// bound to compute, and the guard must disable rather than invent one.
    @Test("A stack with neither a limit nor a neighbour disables the guard")
    func noLimitAndNoNeighbourDisablesTheGuard() {
        let lone = "7ffd0d3f0000-7ffd0d411000 rw-p 00000000 00:00 0    [stack]"
        #expect(parse(lone, "", mainStackPointer) == nil)
    }

    /// A stack pointer in no mapping at all cannot be bounded, so the guard
    /// must disable rather than guess at some other mapping's bounds.
    @Test("A stack pointer outside every mapping disables the guard")
    func unmappedStackPointerDisablesTheGuard() {
        #expect(parse(maps, limits, 0x1) == nil)
    }

    /// The `[stack]` tag is what selects the `RLIMIT_STACK` treatment. Without
    /// it the same mapping is read as an ordinary fixed-size stack, bounded by
    /// its own low address.
    @Test("Only the [stack] mapping gets the RLIMIT_STACK treatment")
    func onlyTheTaggedMappingUsesTheLimit() throws {
        let untagged = maps.replacingOccurrences(of: "[stack]", with: "[heap]")
        let extent = try #require(parse(untagged, limits, mainStackPointer))
        #expect(extent.low == 0x7ffd_0d3f_0000, "an untagged mapping is bounded by itself")
    }

    /// A limit larger than the address it is subtracted from would underflow
    /// `UInt` and trap. Contrived, but the arithmetic must be total — and the
    /// answer is the layout-derived bound, not a disabled guard.
    @Test("A limit wider than the stack top falls back to the layout")
    func oversizedLimitFallsBackToTheLayout() throws {
        let huge = limits.replacingOccurrences(
            of: "Max stack size            8388608",
            with: "Max stack size            99999999999999999")
        let extent = try #require(parse(maps, huge, mainStackPointer))
        #expect(extent.low >= 0x7f2c_1c80_0000)
    }
}

/// Covers the per-thread cache in ``StackGuard`` — the half of the fix that
/// the pure parse tests above cannot reach. Serialised, and each test restores
/// the cache it perturbs, because `cachedExtent` is process-wide state that
/// the render tests in `TUIkitTests` also depend on.
@MainActor
@Suite("Stack guard: per-thread extent cache", .serialized)
struct StackGuardExtentCacheTests {

    private func currentStackPointer() -> UInt {
        var probe: UInt = 0
        return withUnsafeMutablePointer(to: &probe) { UInt(bitPattern: $0) }
    }

    /// The core of the fix. A bound belonging to another thread must be
    /// discarded and re-derived, never applied to this thread's stack pointer.
    /// Without the `sp < high` half of the fast path this returns the wrong
    /// answer; without the re-derivation the cache stays foreign.
    @Test("A bound from another thread is replaced, not applied")
    func foreignBoundIsReplaced() {
        let saved = StackGuard.cachedExtent
        defer { StackGuard.cachedExtent = saved }

        // An extent no real stack pointer can fall inside.
        StackGuard.cachedExtent = StackGuard.StackExtent(low: 0x1000, floor: 0x2000, high: 0x3000)
        #expect(StackGuard.hasHeadroom(), "a shallow stack has headroom once its own bound is found")
        #expect(StackGuard.cachedExtent.high != 0x3000, "the foreign bound was replaced")
    }

    /// The re-derived bound must describe the stack actually in use — the
    /// property that was false before the fix, when the bound always came from
    /// the process main stack no matter which thread was running.
    @Test("The re-derived bound describes the stack actually in use")
    func rederivedBoundContainsTheStackPointer() {
        let saved = StackGuard.cachedExtent
        defer { StackGuard.cachedExtent = saved }

        StackGuard.cachedExtent = .unseeded
        #expect(StackGuard.hasHeadroom())

        let extent = StackGuard.cachedExtent
        // A platform that cannot report bounds disables the guard; that is a
        // legitimate outcome here, and the only one this cannot assert against.
        if extent != .disabled {
            let stackPointer = currentStackPointer()
            #expect(stackPointer >= extent.low && stackPointer < extent.high)
            #expect(stackPointer > extent.floor, "and a shallow stack sits above the floor")
        }
    }

    /// The guard doing its job: on the thread the bound belongs to, a stack
    /// pointer at or below the floor means stop descending — and the trip is
    /// counted, which is the only way a harness can tell a truncated render
    /// from a complete one (the `"⋯"` marker is clamped away to nothing when
    /// the truncated child was already measured at zero size).
    @Test("Inside the known stack but below its floor means no headroom")
    func belowTheFloorOnTheKnownStackTrips() {
        let saved = StackGuard.cachedExtent
        let savedCount = StackGuard.truncationCount
        defer {
            StackGuard.cachedExtent = saved
            StackGuard.truncationCount = savedCount
        }

        let stackPointer = currentStackPointer()
        // Margins far wider than any frame-layout difference between this
        // reading and the probe inside `hasHeadroom()`, which sits in a
        // different frame and moves with inlining decisions. At ±4 KB this
        // passed on 6.3.3 and failed on 6.2 — it was measuring the optimiser,
        // not the guard. A megabyte either side cannot be crossed by frame
        // layout, so what is left is the behaviour under test: a stack pointer
        // inside [low, high) but below floor means stop.
        let megabyte: UInt = 1 << 20
        StackGuard.cachedExtent = StackGuard.StackExtent(
            low: stackPointer - megabyte,
            floor: stackPointer + megabyte,
            high: stackPointer + 2 * megabyte)
        #expect(!StackGuard.hasHeadroom())
        #expect(StackGuard.truncationCount == savedCount + 1, "a trip is counted")
    }

    /// The counter must not move when the guard is simply doing nothing, or a
    /// harness would read a healthy render as truncated.
    @Test("A render with headroom to spare counts no truncations")
    func headroomCountsNoTruncation() {
        let saved = StackGuard.cachedExtent
        let savedCount = StackGuard.truncationCount
        defer {
            StackGuard.cachedExtent = saved
            StackGuard.truncationCount = savedCount
        }

        StackGuard.cachedExtent = .unseeded
        #expect(StackGuard.hasHeadroom())
        #expect(StackGuard.hasHeadroom())
        #expect(StackGuard.truncationCount == savedCount)
    }

    /// `disabled` spans the whole address space, so a containment test would
    /// match it and report "no headroom" — inverting "the guard is off" into a
    /// permanently blank screen.
    @Test("A guard that has given up reports headroom, not the reverse")
    func disabledReportsHeadroom() {
        let saved = StackGuard.cachedExtent
        defer { StackGuard.cachedExtent = saved }

        StackGuard.cachedExtent = .disabled
        #expect(StackGuard.hasHeadroom())
    }

    /// One failure to read procfs must not disarm the guard for the life of
    /// the process, so the latch needs more than a single miss to trip.
    @Test("The guard does not latch off on a single failed derivation")
    func oneFailureDoesNotLatchTheGuardOff() {
        #expect(StackGuard.maxDerivationFailures > 1)
    }
}
