//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OptionalWholeBytesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitView

// MARK: - Measuring nil

#if _pointerBitWidth(_64) && (arch(arm64) || arch(x86_64))
/// Stores `Optional<T>.none` into `memory` IN PLACE, the way the runtime does
/// for code that does not know `T`'s layout: through `Optional<T>`'s own
/// `destructiveInjectEnumTag` value witness — the one piece of code that writes
/// part of an optional.
///
/// Test instrumentation, and deliberately low-level: generic Swift that stores
/// `nil` builds it in a temporary first and copies the temporary whole, at
/// -Onone at least, so what the witness leaves unwritten is the temporary's
/// junk — often the same junk on both runs, which reads as written. (A probe
/// was fooled exactly so.) Calling the witness on the memory itself is the
/// only way to see what it writes. The value-witness table sits one word
/// before the metadata, and the witness is its thirteenth word on a 64-bit
/// target; it is called through a C function type, which matches Swift's own
/// convention for these three arguments on arm64 and x86-64 — the two
/// architectures this runs on — and on nothing else, hence the condition.
private func injectNoneInPlace<T>(_: T.Type, into memory: UnsafeMutableRawPointer) {
    typealias Inject = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void
    let metadata = unsafeBitCast(Optional<T>.self as Any.Type, to: UnsafeRawPointer.self)
    let witnesses = metadata.load(fromByteOffset: -8, as: UnsafeRawPointer.self)
    let inject = unsafeBitCast(witnesses.load(fromByteOffset: 13 * 8, as: UnsafeRawPointer.self), to: Inject.self)
    inject(memory, 1, metadata)
}

/// The bytes of `T?` that `nil`, stored in place, leaves as they were: stored
/// twice, into memory filled two different ways, and a byte that differs is
/// one nothing wrote.
private func unwrittenBytesOfNil<T>(_: T.Type) -> Set<Int> {
    let size = MemoryLayout<T?>.size
    var runs: [[UInt8]] = []
    for pattern: UInt8 in [0xAA, 0x55] {
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T?>.alignment)
        memory.initializeMemory(as: UInt8.self, repeating: pattern, count: size)
        injectNoneInPlace(T.self, into: memory)
        runs.append(Array(UnsafeRawBufferPointer(start: memory, count: size)))
        memory.deallocate()
    }
    return Set((0..<size).filter { runs[0][$0] != runs[1][$0] })
}
#endif

// MARK: - Shapes

private final class Referent {}

private enum SmallChoice: Equatable {
    case first, second, third
}

private enum OneByteWithPayload {
    case flag(Bool)
    case none
}

private struct TwoWords {
    var first: Int
    var second: Int
}

private protocol Witnessed {}

// MARK: - Tests

/// The value hash reads an optional whole — the bytes it lies in, with no
/// `== nil` first — where every byte of every value is always written
/// (`ValueHashPlanBuilder`'s optional rule). The rule rests on what the
/// runtime writes when it stores `nil` in place, which the value-hash design
/// measured on one machine (2026-09-28); these measure it wherever the suite
/// runs, and check the plan against it both ways: every optional it reads
/// whole leaves no byte unwritten, and the ones it reads through `== nil`
/// leave some — which is also what shows the measurement can see an
/// unwritten byte at all.
@MainActor
@Suite("Every optional the value hash reads whole has every byte written")
struct OptionalWholeBytesTests {
    private let plans = ValueHashPlans()

    private func expectWhole<T>(_: T.Type) {
        #expect(plans.plan(for: T?.self).pointee.shape == .dense, "\(T?.self)")
        #if _pointerBitWidth(_64) && (arch(arm64) || arch(x86_64))
        #expect(unwrittenBytesOfNil(T.self).isEmpty, "\(T?.self)")
        #endif
    }

    @Test("A tag byte of its own over a dense payload: nil zero-fills the payload")
    func tagByteOptionals() {
        expectWhole(Int.self)
        expectWhole(Int?.self)
        expectWhole(Date.self)
        expectWhole(TwoWords.self)
        expectWhole((UInt8, UInt8).self)
        expectWhole(EmptyView.self)
    }

    @Test("One scalar whose spare values spell nil: written whole")
    func scalarOptionals() {
        expectWhole(Bool.self)
        expectWhole(Bool?.self)
        expectWhole([Int].self)
        expectWhole(Referent.self)
        // Not `Int.Type`: the runtime's `Int.Type?` — a pointer, whose `nil`
        // this would measure — is not how a struct stores one (a tag byte),
        // so the plan bypasses a metatype, and its optional with it.
        expectWhole(Any.Type.self)
        expectWhole(AnyObject.Type.self)
        expectWhole(SmallChoice.self)
        expectWhole(OneByteWithPayload.self)
    }

    /// The other side, and the proof the measurement sees anything.
    @Test("An optional whose nil leaves bytes unwritten is read through == nil")
    func partlyWrittenOptionals() {
        #if _pointerBitWidth(_64) && (arch(arm64) || arch(x86_64))
        // `nil` is a spare value of a string's second word; the first is left.
        #expect(unwrittenBytesOfNil(String.self) == Set(0..<8))
        // A spare value of the function pointer; the context is left.
        #expect(unwrittenBytesOfNil((() -> Void).self) == Set(8..<16))
        // A spare value of the metadata word; the witness table is left.
        #expect(unwrittenBytesOfNil((any Witnessed.Type).self) == Set(8..<16))
        #endif
        #expect(plans.plan(for: String?.self).pointee.shape == .steps)
        #expect(plans.plan(for: (() -> Void)?.self).pointee.shape == .steps)
        #expect(plans.plan(for: (any Witnessed.Type)?.self).pointee.shape == .steps)
    }
}
