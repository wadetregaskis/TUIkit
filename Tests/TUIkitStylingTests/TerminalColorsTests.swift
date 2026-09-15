//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorsTests.swift
//
//  `TerminalColors`: what the terminal reported about its own colours, published
//  as `TerminalWidthTraits` is, with a process value, a task-local pin and a
//  generation counter.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

@Suite("What the terminal reported about its colours")
struct TerminalColorsTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Sixteen different colours, so a slot read from the wrong offset shows.
    private static let sixteen = (0..<16).map { rgb(UInt8($0), UInt8($0 * 3), UInt8(255 - $0)) }

    @Test("Unknown says nothing at all")
    func unknownIsEmpty() {
        let unknown = TerminalColors.unknown
        #expect(unknown.foreground == nil)
        #expect(unknown.background == nil)
        #expect(unknown.slots == nil)
        #expect(unknown.prefersDark == nil)
        #expect(unknown == TerminalColors())
    }

    @Test("Slots are built only from exactly sixteen, and read back in order")
    func slotsRoundTrip() throws {
        let slots = try #require(TerminalColors.Slots(Self.sixteen))
        for index in 0..<16 {
            #expect(slots[index] == Self.sixteen[index], "slot \(index)")
        }
        #expect(TerminalColors.Slots(Array(Self.sixteen.prefix(15))) == nil)
        #expect(TerminalColors.Slots(Self.sixteen + [Self.rgb(1, 2, 3)]) == nil)
        #expect(TerminalColors.Slots([TerminalColors.RGB]()) == nil)

        var written = TerminalColors.Slots(repeating: Self.rgb(0, 0, 0))
        written[15] = Self.rgb(9, 8, 7)
        #expect(written[15] == Self.rgb(9, 8, 7))
        #expect(written[14] == Self.rgb(0, 0, 0), "a write must not reach the slot beside it")
    }

    /// The conformances are written by hand, because a tuple has neither, so
    /// each slot is changed on its own to show both walk all sixteen.
    @Test("Slots equality and hashing cover all sixteen slots")
    func slotsEqualityAndHashCoverEverySlot() throws {
        let base = try #require(TerminalColors.Slots(Self.sixteen))
        #expect(base == TerminalColors.Slots(Self.sixteen))
        #expect(base.hashValue == TerminalColors.Slots(Self.sixteen)?.hashValue)
        for index in 0..<16 {
            var changed = base
            changed[index] = Self.rgb(200, 100, 50)
            #expect(changed != base, "slot \(index) is not compared")
            #expect(changed.hashValue != base.hashValue, "slot \(index) is not hashed")
        }
    }

    @Test("Two sets of colours differ when any field does")
    func coloursCompareEveryField() throws {
        let slots = try #require(TerminalColors.Slots(Self.sixteen))
        let full = TerminalColors(
            foreground: Self.rgb(171, 178, 191), background: Self.rgb(40, 44, 52),
            slots: slots, prefersDark: true)
        var variants = [full]
        variants.append(TerminalColors(background: full.background, slots: slots, prefersDark: true))
        variants.append(TerminalColors(foreground: full.foreground, slots: slots, prefersDark: true))
        variants.append(
            TerminalColors(foreground: full.foreground, background: full.background, prefersDark: true))
        variants.append(
            TerminalColors(foreground: full.foreground, background: full.background, slots: slots))
        variants.append(
            TerminalColors(
                foreground: full.foreground, background: full.background, slots: slots,
                prefersDark: false))
        #expect(Set(variants).count == variants.count)
    }
}

/// These read or write the PROCESS-wide colours, so they are serialized, the
/// same treatment `TerminalWidthTraitsProcessTests` gets. Nothing outside this
/// suite assigns the process value.
@Suite("What the terminal reported about its colours, process-wide", .serialized)
struct TerminalColorsProcessTests {

    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    @Test("A process that has been told nothing has unknown colours")
    func defaultIsUnknown() {
        #expect(TerminalColors.current == .unknown)
    }

    /// The other reader is a plain thread, which belongs to no task, so it sees
    /// the process value. The pinned closure waits for it, so it reads while the
    /// pin is still in force. A detached task would not do: its body can run
    /// after the closure has returned, when a pin that wrote the process value
    /// and put it back would look task-local too.
    @Test("A pin is in force on its own task, only inside its scope")
    func pinIsTaskLocal() {
        let before = TerminalColors.generation
        let (inside, elsewhere) = TerminalColors.withCurrent(Self.reported) {
            (TerminalColors.current, Self.readOnAPlainThread())
        }
        #expect(inside == Self.reported)
        #expect(elsewhere == .unknown, "the pin reached a thread outside its task")
        #expect(TerminalColors.current == .unknown, "the pin outlived its scope")
        #expect(TerminalColors.generation == before, "a pin must not bump the generation")
    }

    /// `TerminalColors.current`, read on a new thread while this one waits.
    private static func readOnAPlainThread() -> TerminalColors? {
        // @unchecked Sendable, and not a race: the thread writes `value` once
        // before signalling, and this thread reads it only after the wait.
        final class Seen: @unchecked Sendable { var value: TerminalColors? }
        let seen = Seen()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            seen.value = TerminalColors.current
            done.signal()
        }
        done.wait()
        return seen.value
    }

    @Test("Changing the process colours bumps the generation; assigning the same value does not")
    func generationTracksRealChanges() {
        let saved = TerminalColors.current
        defer { TerminalColors.current = saved }
        let before = TerminalColors.generation

        TerminalColors.current = Self.reported
        let afterChange = TerminalColors.generation
        #expect(afterChange == before + 1, "a real change must bump the generation once")
        #expect(TerminalColors.current == Self.reported)

        TerminalColors.current = Self.reported
        #expect(TerminalColors.generation == afterChange, "the same value must not invalidate every cache")

        TerminalColors.current = .unknown
        #expect(TerminalColors.generation == afterChange + 1, "going back to unknown is a change too")
    }
}
