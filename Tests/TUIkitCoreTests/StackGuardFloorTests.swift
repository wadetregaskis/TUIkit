//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackGuardFloorTests.swift
//
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

/// Covers the Linux stack-floor parse, which never runs on the machine these
/// tests are usually run on. `StackGuard.linuxStackFloor(maps:limits:)` takes
/// the procfs *contents* rather than reading them precisely so that this — the
/// part with the edge cases — is exercised everywhere.
@Suite("Stack guard: Linux floor")
struct StackGuardLinuxFloorTests {

    /// A `/proc/self/maps` excerpt. The `[stack]` mapping is deliberately
    /// small (0x21000 = 132 KB), which is what it really looks like early in a
    /// process: it is grow-down and reaches only as far as the stack has been
    /// touched.
    private let maps = """
        55d3f4a00000-55d3f4a21000 r-xp 00000000 08:01 1234    /usr/bin/swift
        7f2c1c000000-7f2c1c021000 rw-p 00000000 00:00 0
        7ffd0d3f0000-7ffd0d411000 rw-p 00000000 00:00 0                          [stack]
        7ffd0d5fe000-7ffd0d600000 r-xp 00000000 00:00 0                          [vdso]
        """

    private let limits = """
        Limit                     Soft Limit           Hard Limit           Units
        Max cpu time              unlimited            unlimited            seconds
        Max stack size            8388608              unlimited            bytes
        Max open files            1024                 1048576              files
        """

    @Test("The floor is the stack top less the limit, plus the reserve")
    func floorIsTopMinusLimit() {
        // Top is the [stack] mapping's HIGH address, 0x7ffd0d411000.
        let expected = UInt(0x7ffd_0d41_1000) - 8_388_608 + StackGuard.reserveBytes
        #expect(StackGuard.linuxStackFloor(maps: maps, limits: limits) == expected)
    }

    /// The bug this parse replaced: taking the mapping's LOW address as the
    /// floor. That address tracks the current high-water mark, so it sits just
    /// under the live stack pointer — the guard would report "no headroom" on
    /// the first ask and truncate every nested view to "⋯". The real floor is
    /// nearly 8 MB below it.
    @Test("The mapping's low address is not mistaken for the floor")
    func lowAddressIsNotTheFloor() {
        let low = UInt(0x7ffd_0d3f_0000)
        let floor = StackGuard.linuxStackFloor(maps: maps, limits: limits)
        #expect(floor < low)
        #expect(low - floor > 7_000_000, "the floor must be a whole stack below the touched extent")
    }

    @Test("An unlimited stack disables the guard")
    func unlimitedDisablesTheGuard() {
        let unlimited = limits.replacingOccurrences(
            of: "Max stack size            8388608",
            with: "Max stack size            unlimited")
        #expect(StackGuard.linuxStackFloor(maps: maps, limits: unlimited) == 0)
    }

    @Test("Missing information disables the guard rather than guessing")
    func missingInformationDisablesTheGuard() {
        let noStackMapping = maps.replacingOccurrences(of: "[stack]", with: "[heap]")
        #expect(StackGuard.linuxStackFloor(maps: noStackMapping, limits: limits) == 0)
        #expect(StackGuard.linuxStackFloor(maps: maps, limits: "") == 0)
        #expect(StackGuard.linuxStackFloor(maps: "", limits: limits) == 0)
    }

    /// A limit larger than the address it is subtracted from would underflow
    /// `UInt` and trap. Contrived, but the arithmetic must be total.
    @Test("A limit wider than the stack top disables the guard")
    func oversizedLimitDisablesTheGuard() {
        let huge = limits.replacingOccurrences(
            of: "Max stack size            8388608",
            with: "Max stack size            99999999999999999")
        #expect(StackGuard.linuxStackFloor(maps: maps, limits: huge) == 0)
    }
}
